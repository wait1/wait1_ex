defmodule Plug.Adapters.Wait1.Handler.Test do
  use ExUnit.Case, async: true

  alias Plug.Adapters.Wait1.TestFixture

  setup_all do
    port = 8081
    {:ok, _} = Plug.Adapters.Wait1.http(TestFixture, [], port: port)

    on_exit fn ->
      :ok = Plug.Adapters.Wait1.shutdown(TestFixture.HTTP)
    end

    {:ok, %{
      client: __MODULE__.Client.start_link(port)
    }}
  end

  test "should respond to the root", context do
    resps = request(context, [
      ["GET", []]
    ])
    [[200, _, %{"hello" => "world"}]] = resps
  end

  test "should handle invalidation", context do
    {resps, invalidations} = request(context, [
      ["POST", ["invalidate"]]
    ], 2)
    assert length(resps) == 1
    assert length(invalidations) == 2
  end

  test "should handle invalidation with redirect", context do
    {resps, invalidations} = request(context, [
      ["POST", ["invalidate-w-redirect"]]
    ], 2)
    assert length(resps) == 1
    assert length(invalidations) == 2
  end

  test "should handle errors", context do
    [[500, _, _],
     [500, _, _]] = request(context, [
      ["GET", ["raise"]],
      ["GET", ["throw"]]
    ])
  end

  test "should persist cookies server-side", context do
    resps = request(context, [
      ["GET", ["cookie-set"], %{}, %{"foo" => "bar"}]
    ])
    [[200, _, _]] = resps

    resps = request(context, [
      ["GET", ["cookie-get"]]
    ])
    [[200, _, %{"foo" => "bar"}]] = resps

    resps = request(context, [
      ["GET", ["cookie-set"], %{}, %{"foo" => "baz"}]
    ])
    [[200, _, _]] = resps

    resps = request(context, [
      ["GET", ["cookie-get"]]
    ])
    [[200, _, %{"foo" => "baz"}]] = resps
  end
  
  defp request(context, reqs, invalidations \\ 0) when is_list(reqs) do
    reqs = Enum.map(reqs, fn(req) ->
      [req_id | req]
    end)

    client = context[:client]

    if invalidations === 0 do
      send(client, {:requests, reqs, self()})
      await(reqs, [])
    else
      invalidations = :lists.seq(1, invalidations) |> Enum.map(fn(_) -> [-1] end)

      send(client, {:subscribe, self()})
      send(client, {:requests, reqs, self()})
      main = await(reqs, [])
      invalidations = await(invalidations, [])

      send(client, {:unsubscribe, self()})
      {main, invalidations}
    end
  end

  defp req_id do
    :crypto.rand_bytes(10) |> Base.url_encode64
  end

  defp await([], acc) do
    :lists.reverse(acc)
  end
  defp await([[id | _] | reqs], acc) do
    receive do
      {:wait1_response, ^id, resp} ->
        await(reqs, [resp | acc])
    end
  end

  defmodule Client do
    def start_link(port) do
      {:ok, pid} = :websocket_client.start_link("ws://localhost:#{port}", __MODULE__, [])
      pid
    end

    def init([], _) do
      {:ok, {%{}, HashSet.new()}}
    end

    def websocket_handle({:text, msg}, _, {pending, subscribers}) do
      resps = Poison.decode!(msg)
      pending = Enum.reduce(resps, pending, fn([id | resp], pending) ->
        case Dict.get(pending, id) do
          nil ->
            Enum.each(subscribers, fn(subscriber) ->
              send(subscriber, {:wait1_response, id, resp})
            end)
            pending
          caller ->
            send(caller, {:wait1_response, id, resp})
            Dict.delete(pending, id)
        end
      end)
      {:ok, {pending, subscribers}}
    end
    def websocket_handle(_other, _, state) do
      {:ok, state}
    end

    def websocket_info({:subscribe, caller}, _, {pending, subscribers}) do
      {:ok, {pending, Set.put(subscribers, caller)}}
    end
    def websocket_info({:unsubscribe, caller}, _, {pending, subscribers}) do
      {:ok, {pending, Set.delete(subscribers, caller)}}
    end
    def websocket_info({:requests, reqs, caller}, _, {pending, subscribers}) do
      pending = Enum.reduce(reqs, pending, fn([id | _], pending) ->
        Dict.put(pending, id, caller)
      end)
      msg = Poison.encode!(reqs)
      {:reply, {:text, msg}, {pending, subscribers}}
    end
  end
end