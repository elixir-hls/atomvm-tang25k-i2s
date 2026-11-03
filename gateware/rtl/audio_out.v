// audio_out.v (from usb-rtl-sdr-tang25k 45ab615 via usb-rtl-sdr-tv 42056a9; NO_VOL added) — stereo audio FIFO + I2S transmitter (two MAX98357A, one set to L, one to R),
// sys clock domain.
//
// The FM decoder delivers L / R frames in bursts (one USB packet at a time) at the RTL-SDR's
// rate (960 kS/s / 20 = 48 kHz by its own crystal). The I2S side plays at
// `fs` = CLK_HZ * edge_inc / 2^32 / 128 (48 kHz) by the FPGA clock. The FIFO absorbs the bursts;
// the small rate difference between the two crystals is absorbed by the fill level:
//   level > HI : drop one frame (play the one after it)      -> `drops`
//   level < LO : play the previous frame again               -> `repeats`
//   empty      : repeat the last frame, wait to refill       -> `underruns`
//   full       : the incoming frame is lost                  -> `overruns`
// Playing starts once the FIFO is half full (and again after it ran empty).
//
// I2S: 64 BCLK per frame (32 per channel, 16-bit sample MSB first then zeros), data changes
// on BCLK falling edges, LRCLK 0 = left, changes one BCLK before the channel's MSB
// (standard I2S). Left slot = L, right slot = R. BCLK = 64 x fs comes from a 32-bit
// phase accumulator (edges on carry): jitter one clock (20 ns), like the original's 10/11.
// `vol`: 0 = mute, 1..15 = -33 .. +9 dB in 3 dB steps (12 = 0 dB, the sample as it is),
// with saturation.
module audio_out #(
    parameter AW = 10,                      // FIFO depth 2^AW samples
    parameter HI = 768,
    parameter LO = 256,
    parameter NO_VOL = 0                    // 1: no volume (0 dB; no multiplier)
) (
    input  wire               clk,
    input  wire               en,
    input  wire [31:0]        edge_inc,     // 2^32 * (2 * 64 * fs) / clk  (BCLK edges per clock)
    input  wire [3:0]         vol,
    input  wire               in_valid,
    input  wire signed [15:0] in_left,
    input  wire signed [15:0] in_right,

    output reg                bclk = 1'b0,
    output reg                lrclk = 1'b0,
    output reg                dout = 1'b0,

    output reg  [15:0]        drops = 16'd0,
    output reg  [15:0]        repeats = 16'd0,
    output reg  [15:0]        underruns = 16'd0,
    output reg  [15:0]        overruns = 16'd0,
    output wire [AW:0]        level
);
    // ---- FIFO ----
    reg [31:0] mem [0:(1<<AW)-1];                 // {R, L}
    reg [AW:0] wp = 0, rp = 0;
    assign level = wp - rp;
    wire full  = level == (1 << AW);
    wire empty = level == 0;

    // ---- I2S timing ----
    reg  [31:0] acc = 32'd0;
    wire [32:0] acc_n = {1'b0, acc} + {1'b0, edge_inc};
    reg  [6:0]  edge_k = 7'd0;              // 0..127: even = rising, odd = falling
    reg  [31:0] sh = 32'd0;                 // bits still to send in this channel
    reg  signed [15:0] cur_l = 16'sd0, cur_r = 16'sd0;   // frame being played
    reg         playing = 1'b0;

    // volume: gain in 1/256 (2^((vol-12)/2)), with saturation
    reg [9:0] gain;
    always @(*) begin
        case (vol)
            4'd0:  gain = 10'd0;    4'd1:  gain = 10'd6;    4'd2:  gain = 10'd8;
            4'd3:  gain = 10'd11;   4'd4:  gain = 10'd16;   4'd5:  gain = 10'd23;
            4'd6:  gain = 10'd32;   4'd7:  gain = 10'd45;   4'd8:  gain = 10'd64;
            4'd9:  gain = 10'd91;   4'd10: gain = 10'd128;  4'd11: gain = 10'd181;
            4'd12: gain = 10'd256;  4'd13: gain = 10'd362;  4'd14: gain = 10'd512;
            default: gain = 10'd724;
        endcase
    end
    // one multiplier for both slots: the left word is loaded at edge 1, the right at edge 65
    wire signed [15:0] cur = edge_k[6] ? cur_r : cur_l;
    wire signed [26:0] prod = cur * $signed({1'b0, gain});
    wire signed [18:0] wide = prod >>> 8;
    wire signed [15:0] loud = NO_VOL ? cur :
                              (wide > 19'sd32767) ? 16'sh7FFF :
                              (wide < -19'sd32768) ? 16'sh8000 : wide[15:0];

    // read decision at the start of a frame
    reg  [1:0] pop_n;                                       // samples to take from the FIFO
    always @(*) begin
        if (!playing || empty) pop_n = 2'd0;
        else if (level > HI && level >= 2) pop_n = 2'd2;
        else if (level < LO) pop_n = 2'd0;
        else pop_n = 2'd1;
    end
    wire [AW-1:0] rd_idx = rp[AW-1:0] + ((pop_n == 2'd2) ? 1 : 0);

    always @(posedge clk) begin
        // write side
        if (in_valid) begin
            if (!full) begin
                mem[wp[AW-1:0]] <= {in_right, in_left};
                wp <= wp + 1'b1;
            end else begin
                overruns <= overruns + 16'd1;
            end
        end
        if (!en) begin
            playing <= 1'b0;
            bclk <= 1'b0; lrclk <= 1'b0; dout <= 1'b0;
            edge_k <= 7'd0;
            acc <= 32'd0;
        end else begin
            if (!playing && level >= (1 << (AW - 1))) playing <= 1'b1;
            acc <= acc_n[31:0];
            if (acc_n[32]) begin
                edge_k <= edge_k + 7'd1;
                if (!edge_k[0]) begin
                    bclk <= 1'b1;                              // rising: receiver samples dout
                end else begin
                    bclk <= 1'b0;                              // falling: set the next bit
                    // falling edge #n prepares bit position n+1 of the 64-bit frame
                    if (edge_k == 7'd127) begin
                        // next frame, left channel MSB; fetch the sample
                        if (pop_n != 2'd0) begin
                            {cur_r, cur_l} <= mem[rd_idx];
                            rp  <= rp + pop_n;
                            if (pop_n == 2'd2) drops <= drops + 16'd1;
                        end else if (playing) begin
                            if (empty) begin
                                underruns <= underruns + 16'd1;
                                playing <= 1'b0;
                            end else repeats <= repeats + 16'd1;
                        end
                        lrclk <= 1'b0;
                    end else if (edge_k == 7'd63) begin
                        lrclk <= 1'b1;                         // right channel from position 32
                    end
                end
            end
            // data: a separate pass so the new sample (cur) loads the shifter one edge later
            if (acc_n[32] && edge_k[0]) begin
                if (edge_k == 7'd127) begin
                    dout <= 1'b0;                              // position 0 (I2S delay bit)
                end else if (edge_k == 7'd1) begin
                    dout <= loud[15];                          // position 1: MSB
                    sh   <= {loud[14:0], 17'h00000};
                end else if (edge_k == 7'd63) begin
                    dout <= 1'b0;                              // position 32: delay bit (right)
                end else if (edge_k == 7'd65) begin
                    dout <= loud[15];
                    sh   <= {loud[14:0], 17'h00000};
                end else begin
                    dout <= sh[31];
                    sh   <= {sh[30:0], 1'b0};
                end
            end
        end
    end
endmodule
