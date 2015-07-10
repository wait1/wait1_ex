defmodule Plug.Adapters.Wait1.Protocol do
  @moduledoc false
  alias Plug.Adapters.Wait1.Conn
  alias Plug.Adapters.Cowboy.Handler
  alias Plug.Adapters.Wait1.Worker
  @already_sent {:plug_conn, :sent}

  require Logger

  require Record
  Record.defrecordp :state, [plug: nil, opts: nil, conn: nil, workers: nil, size: 3]

  def upgrade(req, env, _, transport) do
    Handler.upgrade(req, env, Handler, transport)
  end

  def websocket_init(transport, req, {plug, opts}) do
    :erlang.process_flag(:trap_exit, true)
    {:ok, conn, req} = Conn.init(req, transport)
    ## TODO make worker count configurable
    size = 3
    workers = start_workers(plug, opts, conn, size)
    {:ok, req, state(plug: plug, opts: opts, conn: conn, workers: workers, size: size)}
  end

  def websocket_handle({:text, content}, req, state(workers: workers) = state) do
    case parse(content) do
      {:error, _} ->
        {:reply, {:text, "[[-1,\"invalid request\"]]"}, req, state}
      {:ok, requests} ->
        case Enum.filter(requests, &(handle(&1, workers))) do
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

  def websocket_info({:wait1_resp, worker, _id, msg, additional_reqs, resp_cookies}, req, state = state(workers: workers)) do
    handle_additional_requests(additional_reqs, workers)
    update_cookies(resp_cookies, worker, state)
    {:reply, {:text, msg}, req, state}
  end
  def websocket_info({:plug_conn, :sent}, req, state) do
    {:ok, req, state}
  end
  def websocket_info({:DOWN, _ref, :process, _pid, :normal}, req, state) do
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

  defp start_workers(plug, opts, init, count) do
    :lists.seq(1, count)
    |> Enum.map(fn(_) ->
      Worker.start_link(plug, opts, init)
    end)
    |> Stream.cycle()
  end

  defp parse(content) do
    case Poison.decode(content) do
      {:ok, reqs} when is_list(reqs) ->
        {:ok, reqs}
      error ->
        error
    end
  end

  defp handle([id, method, path], workers) do
    [worker] = Enum.take(workers, 1)
    send(worker, {:handle_request, id, method, path, %{}, nil, nil})
    nil
  end
  defp handle([id, method, path, headers], workers) do
    [worker] = Enum.take(workers, 1)
    send(worker, {:handle_request, id, method, path, headers, nil, nil})
    nil
  end
  defp handle([id, method, path, headers, qs], workers) do
    [worker] = Enum.take(workers, 1)
    send(worker, {:handle_request, id, method, path, headers, qs, nil})
    nil
  end
  defp handle([id, method, path, headers, qs, body], workers) do
    [worker] = Enum.take(workers, 1)
    send(worker, {:handle_request, id, method, path, headers, qs, body})
    nil
  end
  defp handle(req, _workers) do
    {:error, req}
  end

  defp handle_additional_requests([additional_req | additional_reqs], workers) do
    handle(additional_req, workers)
    handle_additional_requests(additional_reqs, workers)
  end
  defp handle_additional_requests(_, _) do
    :ok
  end

  defp update_cookies(resp_cookies, worker, state(workers: workers, size: size)) when is_map(resp_cookies) do
    if Map.size(resp_cookies) > 0 do
      workers
      |> Enum.take(size)
      |> Enum.each(fn
        (pid) when pid == worker -> nil
        (pid) -> send(pid, {:update_cookies, resp_cookies})
      end)
    end
  end
  defp update_cookies(_, _, _) do
    :ok
  end
end
