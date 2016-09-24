defmodule Plug.Parsers.Wait1 do
  def parse(conn = %{scheme: scheme}, "application", "json", _headers, opts) when scheme == :ws or scheme == :wss do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} when is_map(body) ->
        {:ok, body, conn}
      {:ok, other, conn} ->
        {:ok, %{"_json" => other}, conn}
    end
  end
  def parse(conn, _, _, _, _) do
    {:next, conn}
  end
end
