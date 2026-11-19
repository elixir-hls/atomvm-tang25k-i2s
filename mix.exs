defmodule AtomVMTang25KI2S.MixProject do
  use Mix.Project

  def project do
    [
      app: :atomvm_tang25k_i2s,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: ["lib"],
      deps: deps(),
      description: "I2S audio for Elixir HLS on the Tang Primer 25K: a pipeline sink for I2S amplifiers such as the MAX98357A",
      package: [
        licenses: ["Apache-2.0"],
        links: %{"GitHub" => "https://github.com/elixir-hls/atomvm-tang25k-i2s"},
        files: ~w(gateware lib mix.exs README.md LICENSE),
        exclude_patterns: [~r/__pycache__/, ~r/\.pyc$/]
      ]
    ]
  end

  def application, do: []

  defp deps do
    [
      {:elixir_hls, "~> 0.1"}
    ]
  end
end
