defmodule Plug.Adapters.Wait1 do
  @moduledoc """
  Adapter interface for the Wait1 websocket subprotocol.

  ## Options

  * `:ip` - the ip to bind the server to.
    Must be a tuple in the format `{x, y, z, w}`.

  * `:port` - the port to run the server.
    Defaults to 4000 (http) and 4040 (https).

  * `:acceptors` - the number of acceptors for the listener.
    Defaults to 100.

  * `:max_connections` - max number of connections supported.
    Defaults to `:infinity`.

  * `:dispatch` - manually configure Cowboy's dispatch.
    If this option is used, the given plug won't be initialized
    nor dispatched to (and doing so becomes the user responsibility).

  * `:ref` - the reference name to be used.
    Defaults to `plug.HTTP` (http) and `plug.HTTPS` (https).
    This is the value that needs to be given on shutdown.

  * `:compress` - Cowboy will attempt to compress the response body.

  """


  @doc """
  Run Wait1 under http.

  ## Example

      # Starts a new interface
      Plug.Adapters.Wait1.http MyPlug, [], port: 80

      # The interface above can be shutdown with
      Plug.Adapters.Wait1.shutdown MyPlug.HTTP

  """
  def http(plug, opts, cowboy_options \\ []) do
    Plug.Adapters.Cowboy.http(plug, opts, set_dispatch(plug, opts, cowboy_options))
  end

  @doc """
  Run Wait1 under https.

  see Plug.Adapters.Cowboy for more information

  ## Example

      # Starts a new interface
      Plug.Adapters.Wait1.https MyPlug, [],
        port: 443,
        password: "SECRET",
        otp_app: :my_app,
        keyfile: "ssl/key.pem",
        certfile: "ssl/cert.pem"

      # The interface above can be shutdown with
      Plug.Adapters.Wait1.shutdown MyPlug.HTTPS

  """
  def https(plug, opts, cowboy_options \\ []) do
    Plug.Adapters.Cowboy.https(plug, opts, set_dispatch(plug, opts, cowboy_options))
  end

  @doc """
  Shutdowns the given reference.
  """
  def shutdown(ref) do
    Plug.Adapters.Cowboy.shutdown(ref)
  end

  @doc """
  Returns a child spec to be supervised by your application.
  """
  def child_spec(scheme, plug, opts, cowboy_options \\ []) do
    cowboy_options = set_dispatch(plug, opts, cowboy_options)
    Plug.Adapters.Cowboy.child_spec(scheme, plug, opts, cowboy_options)
  end

  ## Helpers

  defp set_dispatch(plug, opts, options) do
    Keyword.put(options, :dispatch, dispatch_for(plug, opts, options))
  end

  defp dispatch_for(plug, opts, options) do
    URI.default_port("ws", 80)
    URI.default_port("wss", 443)
    opts = plug.init(opts)
    onconnection = Keyword.get(options, :onconnection, &onconnection/1)
    [{:_, [ {:_, Plug.Adapters.Wait1.Handler, {plug, opts, onconnection}} ]}]
  end

  defp onconnection(req) do
    {:ok, req}
  end
end
