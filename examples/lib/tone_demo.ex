defmodule ToneDemo do
  @moduledoc """
  P0: a pipeline that runs in the FPGA on its own: 48 kHz ticks -> a defhw oscillator (its
  phase is the kernel's state) -> I2S. The CPU only starts and stops it.
  """
  use EHLS, blocks: [EHLS.I2S]

  # 440 Hz triangle wave: phase advances 2^32 * 440 / 48000 per sample; both channels
  defhw tone_wave(_tick :: u32, phase :: u32 \\ 0) :: u32 do
    t = phase >>> 15
    tri = if t < 65536, do: t, else: 131_071 - t
    s = (tri - 32768) >>> 5          # quiet: +-1024 of +-32768
    {(s &&& 0xFFFF) ||| (s &&& 0xFFFF) <<< 16, phase + 39_370_534}
  end

  defpipeline tone do
    ticks(48_000) |> tone_wave() |> i2s_out()
  end

  def start do
    tone(:start)
    IO.puts("tone: 440 Hz for 10 s, from the FPGA alone")
    :timer.sleep(10_000)
    tone(:stop)
    IO.puts("tone: stopped")
    :ok
  end
end
