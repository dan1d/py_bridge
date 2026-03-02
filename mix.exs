defmodule PyBridge.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/dan1d/py_bridge"

  def project do
    [
      app: :py_bridge,
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      docs: docs(),
      name: "PyBridge",
      description: "JSON-RPC 2.0 bridge for calling Python functions from Elixir over stdin/stdout Ports."
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:telemetry, "~> 1.2"},
      {:nimble_pool, "~> 1.0", optional: true},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "PyBridge",
      source_url: @source_url,
      extras: ["README.md"]
    ]
  end
end
