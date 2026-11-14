defmodule EHLS.I2S do
  @moduledoc """
  I2S for elixir-hls / atomvm-tang25k-hls (`EHLS.Blocks`; FPGA side: gateware/hls_i2s.py).
  Supported: output (`i2s_out`); an input (`i2s_in`, a source) belongs here too, sharing the
  output's BCLK / LRCLK:

      use EHLS, blocks: [EHLS.I2S]
      use EHLS, blocks: [{EHLS.I2S, pins: [dout: "j5:7"]}]   # other pins than the defaults
      use EHLS, blocks: [{EHLS.I2S, wait: true}]             # frames from the CPU, in batches

    * `i2s_out()`: sink, stereo frames `{R[31:16], L[15:0]}` (signed 16 bit), I2S at 48 kHz.
      Its FIFO (1024 frames) adapts the rate: it is always ready, as a source that cannot wait
      (a tuner in the FPGA) needs. With `wait: true` the FIFO is 2048 frames (43 ms) and it waits
      while the FIFO is at its high mark (1984): for frames that come faster than they are
      played, as batches from a stage on the CPU before it, which would be lost beyond the FIFO
      otherwise, and whose next batch may start late.
  """
  @behaviour EHLS.Blocks

  @impl true
  def soc, do: :litex

  @impl true
  def blocks, do: %{i2s_out: {:sink, 0}}

  @impl true
  def peripherals, do: []

  @impl true
  def gateware, do: "hls_i2s"

  # what i2s_out's FIFO did so far (16-bit counts) and its level now; read with
  # :hwstream.reg_read(:hw_kernels.reg(:hls_i2s, :underruns))
  @impl true
  def registers, do: %{drops: :r, repeats: :r, underruns: :r, overruns: :r, level: :r}
end
