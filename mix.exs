defmodule PlugWait1.Mixfile do
  use Mix.Project

  def project do
    [app: :plug_wait1,
     version: "0.2.2",
     elixir: "~> 1.0",
     description: "Plug adapter for the wait1 protocol",
     package: package,
     deps: deps]
  end

  def application do
    [applications: [:logger]]
  end

  defp deps do
    [{:cowboy, ">= 1.0.0"},
     {:plug, "~> 1.2.0"},
     {:poison, "~> 2.2.0"},
     {:websocket_client, github: "jeremyong/websocket_client", only: [:test]},
     {:ex_doc, ">= 0.0.0", only: :dev}]
  end

  defp package do
    [files: ["lib", "mix.exs", "README*"],
     maintainers: ["Cameron Bytheway"],
     licenses: ["MIT"],
     links: %{"GitHub" => "https://github.com/wait1/plug_wait1"}]
  end
end
