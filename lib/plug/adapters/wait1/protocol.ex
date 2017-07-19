defmodule Plug.Adapters.Wait1.Protocol do
  @moduledoc false
  alias Plug.Adapters.Wait1.Conn
  alias Plug.Adapters.Cowboy.Handler
  alias Plug.Adapters.Wait1.Worker

  require Logger

  require Record
  Record.defrecordp :state, [plug: nil, opts: nil, conn: nil]

  def upgrade(req, env, _, transport) do
    Handler.upgrade(req, env, Handler, transport)
  end

  def websocket_init(transport, req, {plug, opts}) do
    :erlang.process_flag(:trap_exit, true)
    {:ok, conn, req} = Conn.init(req, transport)
    {:ok, req, state(plug: plug, opts: opts, conn: conn), Application.get_env(:plug_wait1, :websocket_timeout, :infinity)}
  end

  def websocket_handle({:text, content}, req, state) do
    case parse(content) do
      {:error, _} ->
        {:reply, {:text, "[[-1,\"invalid request\"]]"}, req, state}
      {:ok, requests} ->
        case handle_requests(requests, state) do
          {[], state} ->
            {:ok, req, state}
          {errors, state} ->
            body = for {:error, invalid} <- errors do
              [-1, "invalid request #{inspect(invalid)}"]
            end |> Poison.encode!()
            {:reply, {:text, body}, req, state}
        end
    end
  end
  def websocket_handle({:ping, _}, req, state) do
    {:reply, :pong, req, state}
  end
  def websocket_handle({:pong, _}, req, state) do
    {:ok, req, state}
  end
  def websocket_handle(other, req, state) do
    Logger.warn("Plug.Adapters.Wait1: unhandled request #{inspect(other)}")
    {:ok, req, state}
  end

  def websocket_info({:wait1_resp, _worker, _id, msg, additional_reqs, resp_cookies}, req, state) do
    {resp, state} = merge_response(msg, additional_reqs, resp_cookies, [], state)
    {:reply, {:text, resp}, req, state}
  end
  def websocket_info({:wait1_redirect, _worker, additional_reqs, resp_cookies}, req, state) do
    handle_additional_requests(additional_reqs, state)
    state = update_cookies(resp_cookies, state)
    {:ok, req, state}
  end
  def websocket_info({:plug_conn, :sent}, req, state) do
    {:ok, req, state}
  end
  def websocket_info({:EXIT, _pid, :normal}, req, state) do
    {:ok, req, state}
  end
  def websocket_info({:EXIT, _pid, error}, req, state) do
    Logger.error("Plug.Adapters.Wait1: #{inspect(error)}")
    {:shutdown, req, state}
  end
  def websocket_info(other, req, state) do
    Logger.warn("Plug.Adapters.Wait1: unhandled message #{inspect(other)}")
    {:ok, req, state}
  end

  def websocket_terminate(_reason, _req, _state) do
    :ok
  end

  defp parse(content) do
    case Poison.decode(content) do
      {:ok, reqs} when is_list(reqs) ->
        {:ok, reqs}
      error ->
        error
    end
  end

  defp handle_requests(requests, state) do
    Enum.reduce(requests, {[], state}, fn(req, {errors, state}) ->
      case handle(req, state) do
        :error ->
          {[req | errors], state}
        state ->
          {errors, state}
      end
    end)
  end

  defp handle([_id, "SET", headers], state(conn: conn = %{private: %{wait1_headers: prev}}) = state) when is_map(headers) do
    headers = Enum.reduce(headers, prev, fn({key, value}, acc) ->
      :lists.keystore(key, 1, acc, {key, value})
    end)
    state(state, conn: Plug.Conn.put_private(conn, :wait1_headers, headers))
  end
  defp handle([id, method, path], state(plug: plug, opts: opts, conn: conn) = state) do
    Worker.start_link(plug, opts, conn, id, method, path, %{}, nil, nil)
    state
  end
  defp handle([id, method, path, req_headers], state(plug: plug, opts: opts, conn: conn) = state) do
    Worker.start_link(plug, opts, conn, id, method, path, req_headers, nil, nil)
    state
  end
  defp handle([id, method, path, req_headers, qs], state(plug: plug, opts: opts, conn: conn) = state) do
    Worker.start_link(plug, opts, conn, id, method, path, req_headers, qs, nil)
    state
  end
  defp handle([id, method, path, req_headers, qs, req_body], state(plug: plug, opts: opts, conn: conn) = state) do
    Worker.start_link(plug, opts, conn, id, method, path, req_headers, qs, req_body)
    state
  end
  defp handle(_req, _state) do
    :error
  end

  defp buffer(buffer, state) when length(buffer) < 10 do
    receive do
      {:wait1_resp, _worker, _id, msg, additional_reqs, resp_cookies} ->
        merge_response(msg, additional_reqs, resp_cookies, buffer, state)
    after
      5 ->
        {Poison.encode!(buffer), state}
    end
  end
  defp buffer(buffer, state) do
    {Poison.encode!(buffer), state}
  end

  defp merge_response(msg, additional_reqs, resp_cookies, buffer, state) do
    state = update_cookies(resp_cookies, state)
    handle_additional_requests(additional_reqs, state)
    buffer([%Plug.Adapters.Wait1.Conn.Body{body: msg} | buffer], state)
  end

  defp handle_additional_requests([additional_req | additional_reqs], state) do
    handle(additional_req, state)
    handle_additional_requests(additional_reqs, state)
  end
  defp handle_additional_requests(_, _) do
    :ok
  end

  defp update_cookies(resp_cookies, state = state(conn: conn)) when is_map(resp_cookies) do
    if Map.size(resp_cookies) > 0 do
      state(state, conn: Conn.update_cookies(conn, resp_cookies))
    else
      state
    end
  end
  defp update_cookies(_, state) do
    state
  end
end
