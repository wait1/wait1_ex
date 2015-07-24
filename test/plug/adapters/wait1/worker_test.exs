defmodule Plug.Adapters.Wait1.Worker.Test do
  use ExUnit.Case, async: true

  alias Plug.Adapters.Wait1.Worker
  alias Plug.Adapters.Wait1.TestFixture

  @tag timeout: 100

  setup do
    opts = TestFixture.init([])
    init = %Plug.Conn{
      owner: self(),
      scheme: :ws,
      private: %{wait1_headers: []}
    }
    {:ok, %{init: [TestFixture, opts, init]}}
  end

  test "should handle a request to the root", context do
    {id, msg, _, _} = request(context)
    [[^id, 200, _, %{"hello" => "world"}]] = msg
  end

  test "should handle string paths", context do
    {id, msg, _, _} = request(context, "GET", "/")
    [[^id, 200, _, %{"hello" => "world"}]] = msg
  end

  test "should handle excessive slashes", context do
    {id, msg, _, _} = request(context, "GET", "////redirect////////")
    [[^id, 200, %{"content-location" => _}, %{"hello" => "world"}]] = msg
  end

  test "should handle a redirect", context do
    {id, msg, _, _} = request(context, "GET", ["redirect"])
    [[^id, 200, %{"content-location" => _}, _]] = msg
  end

  test "should handle invalidation", context do
    {id, msg, additional_reqs, _} = request(context, "POST", ["invalidate"])
    [[^id, 200, _, _]] = msg
    assert length(additional_reqs) > 1
  end

  test "should handle a raised error", context do
    {id, msg, _, _} = request(context, "GET", ["raise"])
    [[^id, 500, _, %{"error" => %{"message" => _}}]] = msg
  end

  test "should handle a thrown error", context do
    {id, msg, _, _} = request(context, "GET", ["throw"])
    [[^id, 500, _, %{"error" => %{"message" => _}}]] = msg
  end

  test "should handle several requests", context do
    {_, [_], _, _} = request(context)
    {_, [_], _, _} = request(context, "GET", ["raise"])
    {_, [_], _, _} = request(context, "GET", ["not-found"])
    {_, [_], _, _} = request(context, "GET", ["throw"])
    {_, [_], _, _} = request(context, "GET", ["redirect"])
  end

  defp request(%{init: [plug, opts, init]}, method \\ "GET", path \\ [], req_headers \\ %{}, qs \\ nil, body \\ nil) do
    id = req_id
    worker = Worker.start_link(plug, opts, init, id, method, path, req_headers, qs, body)
    receive do
      {:wait1_resp, ^worker, ^id, msg, additional_reqs, cookies} ->
        {id, Poison.decode!(msg), additional_reqs, cookies}
    end
  end

  defp req_id do
    :crypto.rand_bytes(10) |> Base.url_encode64
  end
end
