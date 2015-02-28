defmodule Plug.Adapters.Wait1.Handler do
  @moduledoc false
  @connection Plug.Adapters.Wait1.Conn
  @fallback Plug.Adapters.Cowboy.Handler
  @already_sent {:plug_conn, :sent}

  def init({transport, :http}, req, {plug, opts}) when transport in [:tcp, :ssl] do
    case :cowboy_req.header("upgrade", req) do
      {"websocket", _} ->
        {:upgrade, :protocol, :cowboy_websocket}
      _ ->
        {:upgrade, :protocol, __MODULE__, req, {transport, plug, opts}}
    end
  end

  def upgrade(req, env, _, state) do
    @fallback.upgrade(req, env, @fallback, state)
  end

  def websocket_init(transport, req, {plug, opts}) do
    {:ok, req, {plug, opts, @connection.init(req, transport)}}
  end

  def websocket_handle({:text, content}, req, state) do
    case parse(content, state) do
      {:error, _} ->
        {:reply, {:text, "[[0,\"invalid request\"]]"}, req, state}
      {:ok, _reqs} ->
        {:ok, req, state}
    end
  end

  def websocket_info({:hyper_resp, _, res}, req, state) do
    {:reply, {:text, res}, req, state}
  end
  def websocket_info({:plug_conn, :sent}, req, state) do
    {:ok, req, state}
  end
  def websocket_info({:DOWN, _ref, :process, _pid, :normal}, req, state) do
    {:ok, req, state}
  end
  def websocket_info(_info, req, state) do
    IO.inspect _info
    {:ok, req, state}
  end

  def websocket_terminate(_reason, _req, _state) do
    :ok
  end

  defp parse(content, state) do
    case Poison.decode(content) do
      {:ok, reqs} when is_list(reqs) ->
        handle(reqs, state, [])
      error ->
        error
    end
  end

  defp handle([], _, acc) do
    {:ok, acc}
  end
  defp handle([[id, method, path, headers] | reqs], state, acc) do
    ref = spawn_monitor(__MODULE__, :handler, [id, method, path, headers, nil, state])
    handle(reqs, state, [ref | acc])
  end
  defp handle([[id, method, path, headers, body] | reqs], state, acc) do
    ref = spawn_monitor(__MODULE__, :handler, [id, method, path, headers, body, state])
    handle(reqs, state, [ref | acc])
  end
  defp handle([req | reqs], state, acc) do
    IO.inspect {:invalid, req}
    handle(reqs, state, acc)
  end

  defmodule Body do
    defstruct body: nil
  end

  def handler(id, method, [""], headers, body, state) do
    handler(id, method, [], headers, body, state)
  end
  def handler(id, method, path, headers, body, {plug, opts, init} = state) do
    conn = @connection.conn(init, method, path, "", headers, body)
    %{adapter: {@connection, res}} = conn |> plug.call(opts)
    headers = :maps.from_list(res.headers)
    response(id, res.status, headers, res.body, state, headers)
  end

  def response(id, 303, %{"location" => location}, _, state, headers) do
    parts = URI.parse(location)
    # TODO handle query string
    [_ | path] = String.split(parts.path, "/")
    handler(id, "GET", path, headers, nil, state)
  end
  def response(id, status, headers, body, {_, _, init}, _) do
    res_body = %Plug.Adapters.Wait1.Handler.Body{body: body}
    out = Poison.encode!([[id, status, headers, res_body]])
    send init.owner, {:hyper_resp, id, out}
  end
end

defimpl Poison.Encoder, for: Plug.Adapters.Wait1.Handler.Body do
  def encode(val, _options) do
    val.body
  end
end
