defmodule PlugWait1.Mixfile do
  use Mix.Project

  def project do
    [app: :plug_wait1,
     version: "0.0.1",
     elixir: "~> 1.0",
     deps: deps]
  end

  def application do
    [applications: [:logger]]
  end

  defp deps do
    [{ :cowboy, ">= 1.0.0" },
     { :plug, "~> 0.13.0" },
     { :poison, "~> 1.3.1" },
     { :websocket_client, github: "jeremyong/websocket_client", only: [:test]}]
  end
end
