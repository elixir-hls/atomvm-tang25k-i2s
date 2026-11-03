defmodule EHLS.I2S do
  @moduledoc """
  I2S for elixir-hls / atomvm-tang25k-hls (`EHLS.Blocks`; FPGA side: gateware/hls_i2s.py).
  Supported: output (`i2s_out`); an input (`i2s_in`, a source) belongs here too, sharing the
  output's BCLK / LRCLK:

      use EHLS, blocks: [EHLS.I2S]
      use EHLS, blocks: [{EHLS.I2S, pins: [dout: "j5:7"]}]   # other pins than the defaults

    * `i2s_out()`: sink, stereo frames `{R[31:16], L[15:0]}` (signed 16 bit), I2S at 48 kHz.
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
end
