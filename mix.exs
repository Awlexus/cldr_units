defmodule CldrUnits.Mixfile do
  use Mix.Project

  @version "2.3.0-dev"

  def project do
    [
      app: :ex_cldr_units,
      version: @version,
      elixir: "~> 1.5",
      name: "Cldr Units",
      source_url: "https://github.com/kipcole9/cldr_units",
      description: description(),
      package: package(),
      docs: docs(),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  defp description do
    """
    Unit formatting (volume, area, length, ...), conversion and arithmetic
    functions based upon the Common Locale Data Repository (CLDR).
    """
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ex_cldr, "~> 2.1"},
      {:ex_cldr_numbers, "~> 2.1"},
      {:ex_cldr_lists, "~> 2.0"},
      {:ex_doc, "~> 0.18", only: [:dev, :release]},
      {:jason, "~> 1.0", optional: true}
    ]
  end

  defp package do
    [
      maintainers: ["Kip Cole"],
      licenses: ["Apache 2.0"],
      links: links(),
      files: [
        "lib",
        "config",
        "mix.exs",
        "README*",
        "CHANGELOG*",
        "LICENSE*"
      ]
    ]
  end

  def docs do
    [
      source_ref: "v#{@version}",
      main: "readme",
      extras: ["README.md", "CHANGELOG.md", "LICENSE.md"],
      logo: "logo.png"
    ]
  end

  def links do
    %{
      "GitHub" => "https://github.com/kipcole9/cldr_units",
      "Readme" => "https://github.com/kipcole9/cldr_units/blob/v#{@version}/README.md",
      "Changelog" => "https://github.com/kipcole9/cldr_units/blob/v#{@version}/CHANGELOG.md"
    }
  end

  defp elixirc_paths(:test), do: ["lib", "mix", "test"]
  defp elixirc_paths(:dev), do: ["lib", "mix"]
  defp elixirc_paths(_), do: ["lib"]
end
