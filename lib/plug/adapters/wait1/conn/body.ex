defmodule Plug.Adapters.Wait1.Conn.Body do
  defstruct body: nil
end

defimpl Poison.Encoder, for: Plug.Adapters.Wait1.Conn.Body do
  def encode(val, options) do
    case val.body do
      "" ->
        "null"
      nil ->
        "null"
      body when is_map(body) ->
        Poison.Encoder.encode(body, options)
      body ->
        body
    end
  end
end
