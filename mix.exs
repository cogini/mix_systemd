defmodule MixSystemd.MixProject do
  use Mix.Project

  @github "https://github.com/cogini/mix_systemd"
  @version "0.7.6"

  def project do
    [
      app: :mix_systemd,
      version: @version,
      elixir: "~> 1.12",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      source_url: @github,
      homepage_url: @github,
      docs: docs(),
      dialyzer: [
        plt_add_apps: [:mix, :eex]
        # plt_add_deps: true,
        # flags: ["-Werror_handling", "-Wrace_conditions"],
        # flags: ["-Wunmatched_returns", :error_handling, :race_conditions, :underspecs],
        # ignore_warnings: "dialyzer.ignore-warnings"
      ],
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :eex]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, "~> 0.21", only: :dev, runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
    ]
  end

  defp description do
    "Generates systemd unit files for an application."
  end

  defp package do
    [
      maintainers: ["Jake Morrison"],
      licenses: ["Apache 2.0"],
      links: %{"GitHub" => @github}
    ]
  end

  defp docs do
    [
      source_url: @github,
      extras: ["README.md", "CHANGELOG.md"],
      # api_reference: false,
      source_url_pattern: "#{@github}/blob/master/%{path}#L%{line}"
    ]
  end
end
