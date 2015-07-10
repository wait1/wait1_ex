defmodule Plug.Adapters.Wait1.Conn.QS do
  defstruct kvs: nil
end

defimpl String.Chars, for: Plug.Adapters.Wait1.Conn.QS do
  def to_string(%{:kvs => kvs}) when is_map(kvs) do
    Plug.Conn.Query.encode(kvs)
  end
  def to_string(%{:kvs => kvs}) when is_binary(kvs) do
    kvs
  end
  def to_string(_) do
    ""
  end
end