defmodule Plug.Adapters.Wait1 do
  def http(plug, opts, options \\ []) do
    Plug.Adapters.Cowboy.http(plug, opts, set_dispatch(options, plug, opts))
  end
  def https(plug, opts, options \\ []) do
    Plug.Adapters.Cowboy.https(plug, opts, set_dispatch(options, plug, opts))
  end
  def shutdown(ref) do
    Plug.Adapters.Cowboy.shutdown(ref)
  end

  defp set_dispatch(options, plug, opts) do
    Keyword.put(options, :dispatch, dispatch_for(plug, opts))
  end

  defp dispatch_for(plug, opts) do
    opts = plug.init(opts)
    [{:_, [ {:_, Plug.Adapters.Wait1.Handler, {plug, opts}} ]}]
  end
end
