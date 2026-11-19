# atomvm-tang25k-i2s

I2S audio for [atomvm-tang25k-hls](https://github.com/elixir-hls/atomvm-tang25k-hls) (with [elixir-hls](https://github.com/elixir-hls/elixir-hls)):
the package covers I2S as a whole, its blocks one direction each. Supported: output, a
pipeline sink for I2S amplifiers such as the MAX98357A.

In the application's mix.exs, beside its target:

```elixir
{:atomvm_tang25k_i2s, "~> 0.1"}
```

| Block | Direction | |
|---|---|---|
| `i2s_out()` | sink: FPGA -> amplifier / DAC | supported |
| `i2s_in()` | source: ADC / microphone -> FPGA | not yet |

Input and output share one BCLK / LRCLK (as a full-duplex codec or an ADC next to a DAC
need), so an input goes into this package beside the output, with a `din` pin, the clock
direction (the FPGA drives the clocks, or takes a codec's) as an option, and the sample rate
common to both.

```elixir
use EHLS, blocks: [EHLS.I2S]

definstance tone do
  ticks(48_000) |> tone_wave() |> i2s_out()
end
```

## Output

`i2s_out()`: stereo frames `{R[31:16], L[15:0]}` (signed 16 bit), played at 48 kHz; a FIFO
with rate adaptation (gateware/rtl/audio_out.v) takes the frames as they come, so the sink is
always ready.

## Pins

Default: PMOD J5 of the Sipeed Tang Primer 25K Dock:

| Signal | Pin | Dock |
|---|---|---|
| `lrclk` | j5:2 | J5-7 (K11) |
| `bclk` | j5:6 | J5-8 (L11) |
| `dout` | j5:7 | J5-6 (K5) |

Other pins: `use EHLS, blocks: [{EHLS.I2S, pins: [dout: "j5:7", ...]}]`.

## Example

`examples/tone_demo.ex`: a 440 Hz triangle from a defhls oscillator (its phase the kernel's
state), `ticks(48_000) |> tone_wave() |> i2s_out()`.

```sh
cd examples
H=../../atomvm-tang25k-hls/scripts
$H/build_kernel.sh lib/tone_demo.ex && $H/build_soc.sh && $H/build_atomvm.sh && $H/flash.sh vm lib
$H/build_ex.sh tone_demo ToneDemo && $H/run.sh tone_demo
```

From usb-rtl-sdr-tang25k.

## License

Apache-2.0 (see [LICENSE](LICENSE)).
