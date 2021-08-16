defmodule Tablespoon.MixProject do
  use Mix.Project

  def project do
    [
      app: :tablespoon,
      version: "0.1.0",
      elixir: "~> 1.6",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: [:phoenix] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      test_coverage: [
        tool: LcovEx
      ],
      dialyzer: [
        plt_add_deps: :transitive,
        flags: [
          :error_handling,
          :race_conditions,
          :unmatched_returns
        ]
      ]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Tablespoon.Application, []},
      extra_applications: [:logger, :runtime_tools, :snmp, :ssh, :xmerl]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.5.1"},
      {:phoenix_html, "~> 3.0.1"},
      {:jason, "~> 1.0"},
      {:plug_cowboy, "~> 2.0"},
      {:credo, "~> 1.1", only: [:dev, :test], runtime: false},
      {:lcov_ex, "~> 0.2", only: [:dev, :test], runtime: false},
      {:stream_data, "~> 0.5.0", only: [:test]},
      {:dialyxir, "~> 1.1.0", only: [:dev, :test], runtime: false},
      {:logger_splunk_backend, "~> 2.0", only: [:prod]},
      {:logster, "~> 1.0"},
      {:ehmon, github: "mbta/ehmon", branch: "master", only: [:prod]},
      {:fuse, "~> 2.4.2"},
      {:ranch, "~> 1.7.1"}
    ]
  end
end
