defmodule Plug.Adapters.Wait1.Worker do
  @moduledoc false
  alias Plug.Adapters.Wait1.Conn

  def start_link(plug, opts, init) do
    spawn_link(__MODULE__, :loop, [self(), plug, opts, init])
  end

  def loop(parent, plug, opts, init) do
    receive do
      {:update_cookies, cookies} ->
        init = Conn.update_cookies(init, cookies)
        __MODULE__.loop(parent, plug, opts, init)
      {:handle_request, id, method, path, req_headers, qs, req_body} ->
        send(parent, handle_request(id, method, path, req_headers, qs, req_body, plug, opts, init))
        __MODULE__.loop(parent, plug, opts, init)
    end
  end

  defp handle_request(id, method, path, req_headers, qs, req_body, plug, opts, init) do
    {resp_status, resp_headers, resp_body, resp_cookies} = request(method, path, req_headers, qs, req_body, plug, opts, init, nil)
    msg = encode(id, resp_status, resp_headers, resp_body)
    additional_reqs = invalidates(resp_headers, req_headers)
    {:wait1_resp, self(), id, msg, additional_reqs, resp_cookies}
  rescue
    err ->
      format_error(err, :error, id)
  catch
    err ->
      format_error(err, :throw, id)
  end

  defp format_error(err, type, id) do
    body = %{
      "error" => %{
        "message" => if Mix.env == :prod do
          "Internal server error"
        else
          Exception.format(type, err, :erlang.get_stacktrace())
        end
      }
    }
    msg = Poison.encode!([[id, 500, %{}, body]])
    {:wait1_resp, self(), id, msg, [], []}
  end

  defp request(method, path, req_headers, qs, body, plug, opts, init, redirect) do
    init
    |> Conn.conn(method, path, req_headers, qs, body)
    |> plug.call(opts)
    |> response(plug, opts, init, redirect)
  end

  defp response(conn = %{adapter: {Conn, %{status: resp_status, headers: resp_headers, body: resp_body}}, resp_cookies: resp_cookies}, plug, opts, init, redirect) do
    case Enum.reduce(resp_headers, %{}, &join_headers/2) do
      %{"location" => location} when resp_status == 302 or resp_status == 303 ->
        %{path: path, query: query} = URI.parse(location)
        request("GET", path, conn.req_headers, query, nil, plug, opts, init, location)
      resp_headers when is_binary(redirect) ->
        resp_headers = Map.put(resp_headers, "content-location", redirect)
        {resp_status, resp_headers, resp_body, resp_cookies}
      resp_headers ->
        {resp_status, resp_headers, resp_body, resp_cookies}
    end
  end

  defp join_headers({name, value}, acc) do
    case Map.get(acc, name) do
      nil ->
        Map.put(acc, name, value)
      values when is_list(values) ->
        Map.put(acc, name, [value | values])
      prev ->
        Map.put(acc, name, [value, prev])
    end
  end

  defp encode(id, resp_status, resp_headers, resp_body) do
    resp_body = %Plug.Adapters.Wait1.Conn.Body{body: resp_body}
    Poison.encode!([[id, resp_status, resp_headers, resp_body]])
  end

  defp invalidates(%{"x-invalidates" => link}, req_headers) when is_list(link) do
    Enum.map(link, &(invalidate(&1, req_headers)))
  end
  defp invalidates(%{"x-invalidates" => link}, req_headers) do
    [invalidate(link, req_headers)]
  end
  defp invalidates(_, _) do
    []
  end

  defp invalidate(path, req_headers) do
    %{path: path, query: qs} = URI.parse(path)
    [-1, "GET", path, req_headers, qs, nil]
  end
end