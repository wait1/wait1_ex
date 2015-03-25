defmodule Plug.Adapters.Wait1 do
  def http(plug, opts, options \\ []) do
    Plug.Adapters.Cowboy.http(plug, opts, set_dispatch(plug, opts, options))
  end
  def https(plug, opts, options \\ []) do
    Plug.Adapters.Cowboy.https(plug, opts, set_dispatch(plug, opts, options))
  end
  def shutdown(ref) do
    Plug.Adapters.Cowboy.shutdown(ref)
  end

  defp set_dispatch(plug, opts, options) do
    Keyword.put(options, :dispatch, dispatch_for(plug, opts, options))
  end

  defp dispatch_for(plug, opts, options) do
    opts = plug.init(opts)
    [{:_, [ {:_, Plug.Adapters.Wait1.Handler, {plug, opts, Keyword.get(options, :onconnection, &onconnection/1)}} ]}]
  end

  defp onconnection(req) do
    {:ok, req}
  end
end
