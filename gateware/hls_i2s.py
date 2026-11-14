"""
I2S for elixir-hls / atomvm-tang25k-hls (EHLS.I2S on the Elixir side, EHLS.Blocks); supported:
output (an input, i2s_in, would share its BCLK / LRCLK):

  i2s_out  sink: stereo frames {R[31:16], L[15:0]} (signed 16 bit), I2S at 48 kHz
           (audio_out.v: a FIFO with rate adaptation; always ready, or with the option
           wait: ready while the FIFO is below its high mark). For I2S amplifiers
           such as the MAX98357A (left channel first, 32 BCLK per channel).

Default pins: PMOD J5 of the Sipeed Tang Primer 25K Dock, as in usb-rtl-sdr-tv; an
application moves them with use EHLS, blocks: [{EHLS.I2S, pins: [dout: "j5:7", ...]}]
(configure).
"""
import os

from migen import ClockSignal, Instance, Signal
from litex.build.generic_platform import IOStandard, Pins, Subsignal
from litex.gen import LiteXModule
from litex.soc.interconnect import stream

RTL_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "rtl")

# i2s_out waits (sink.ready) while its FIFO is at the high mark: for frames that come faster
# than they are played, in batches from the CPU (a stage on: :cpu before it). Without it the
# sink is always ready and the FIFO adapts the rate, as a source that cannot wait (the tuner in
# the FPGA) needs; frames that come in a batch are then lost beyond the FIFO's 1024.
WAIT = False

# signal -> LiteX connector pin
PINS = {
    "lrclk": "j5:2",       # J5-7 K11
    "bclk":  "j5:6",       # J5-8 L11
    "dout":  "j5:7",       # J5-6 K5
}


def configure(options):
    """options: {"pins": {signal: pin}} over PINS, {"wait": bool}."""
    global WAIT
    for k, v in options.items():
        if k == "wait":
            if not isinstance(v, bool):
                raise SystemExit(f"hls_i2s: wait is true or false, not {v!r}")
            WAIT = v
            continue
        if k != "pins":
            raise SystemExit(f"hls_i2s: unknown option {k}")
        for sig, pin in v.items():
            if sig not in PINS:
                raise SystemExit(f"hls_i2s: unknown pin {sig} (one of {', '.join(PINS)})")
            PINS[sig] = pin


class I2SOut(LiteXModule):
    """Sink: stereo frames {R[31:16], L[15:0]} (signed 16-bit), played at 48 kHz on the I2S
    pins (audio_out.v: FIFO with rate adaptation; always ready, or with WAIT ready while the FIFO
    is below its high mark, HI, so that it never drops for being full)."""
    HI = 768
    def __init__(self, soc, enable, fs=48000):
        platform = soc.platform
        platform.add_extension([
            ("i2s", 0, *[Subsignal(s, Pins(PINS[s])) for s in ("lrclk", "bclk", "dout")],
             IOStandard("LVCMOS33")),
        ])
        pads = platform.request("i2s")
        self.sink = stream.Endpoint([("data", 32)])
        edge_inc = int(round(2**32 * 128 * fs / soc.sys_clk_freq))
        self.drops, self.repeats, self.underruns, self.overruns = (Signal(16) for _ in range(4))
        level = Signal(11)
        # stopped (enable 0), the frames are taken and not played, as without WAIT
        self.comb += self.sink.ready.eq(~enable | (level < self.HI) if WAIT else 1)
        self.specials += Instance("audio_out",
            p_NO_VOL=1,
            i_clk=ClockSignal(), i_en=enable, i_edge_inc=edge_inc, i_vol=12,
            i_in_valid=self.sink.valid & enable,
            i_in_left=self.sink.data[0:16], i_in_right=self.sink.data[16:32],
            o_bclk=pads.bclk, o_lrclk=pads.lrclk, o_dout=pads.dout,
            o_drops=self.drops, o_repeats=self.repeats,
            o_underruns=self.underruns, o_overruns=self.overruns, o_level=level)
        platform.add_source(os.path.join(RTL_DIR, "audio_out.v"))


BLOCKS = {"i2s_out": I2SOut}
PERIPHERALS = {}
