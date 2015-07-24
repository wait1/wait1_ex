defmodule Plug.Adapters.Wait1.Protocol do
  @moduledoc false
  alias Plug.Adapters.Wait1.Conn
  alias Plug.Adapters.Cowboy.Handler
  alias Plug.Adapters.Wait1.Worker
  @already_sent {:plug_conn, :sent}

  require Logger

  require Record
  Record.defrecordp :state, [plug: nil, opts: nil, conn: nil]

  def upgrade(req, env, _, transport) do
    Handler.upgrade(req, env, Handler, transport)
  end

  def websocket_init(transport, req, {plug, opts}) do
    :erlang.process_flag(:trap_exit, true)
    {:ok, conn, req} = Conn.init(req, transport)
    {:ok, req, state(plug: plug, opts: opts, conn: conn)}
  end

  def websocket_handle({:text, content}, req, state) do
    case parse(content) do
      {:error, _} ->
        {:reply, {:text, "[[-1,\"invalid request\"]]"}, req, state}
      {:ok, requests} ->
        case Enum.filter(requests, &(handle(&1, state))) do
          [] ->
            {:ok, req, state}
          errors ->
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
    handle_additional_requests(additional_reqs, state)
    state = update_cookies(resp_cookies, state)
    {:reply, {:text, msg}, req, state}
  end
  def websocket_info({:wait1_redirect, _worker, additional_reqs, resp_cookies}, req, state) do
    handle_additional_requests(additional_reqs, state)
    update_cookies(resp_cookies, state)
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

  defp handle([id, method, path], state(plug: plug, opts: opts, conn: conn)) do
    Worker.start_link(plug, opts, conn, id, method, path, %{}, nil, nil)
    nil
  end
  defp handle([id, method, path, req_headers], state(plug: plug, opts: opts, conn: conn)) do
    Worker.start_link(plug, opts, conn, id, method, path, req_headers, nil, nil)
    nil
  end
  defp handle([id, method, path, req_headers, qs], state(plug: plug, opts: opts, conn: conn)) do
    Worker.start_link(plug, opts, conn, id, method, path, req_headers, qs, nil)
    nil
  end
  defp handle([id, method, path, req_headers, qs, req_body], state(plug: plug, opts: opts, conn: conn)) do
    Worker.start_link(plug, opts, conn, id, method, path, req_headers, qs, req_body)
    nil
  end
  defp handle(req, _state) do
    {:error, req}
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
