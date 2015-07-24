defmodule Plug.Adapters.Wait1.Worker do
  require Logger

  @moduledoc false
  alias Plug.Adapters.Wait1.Conn

  def start_link(plug, opts, init, id, method, path, req_headers, qs, req_body) do
    spawn_link(__MODULE__, :handle_request, [self(), plug, opts, init, id, method, path, req_headers, qs, req_body])
  end

  def handle_request(parent, plug, opts, init, id, method, path, req_headers, qs, req_body) do
    {resp_status, resp_headers, resp_body, resp_cookies} = request(parent, method, path, req_headers, qs, req_body, plug, opts, init, nil)
    msg = encode(id, resp_status, resp_headers, resp_body)
    additional_reqs = invalidates(resp_headers, req_headers)
    send(parent, {:wait1_resp, self(), id, msg, additional_reqs, resp_cookies})
  # Usually we wouldn't catch errors but we want to be able to set the status code and response body to something meaningful
  rescue
    err ->
      send(parent, format_error(err, :error, id))
  catch
    err ->
      send(parent, format_error(err, :throw, id))
  end

  defp format_error(err, type, id) do
    stacktrace = :erlang.get_stacktrace()
    {message, method, path} = extract_connection_error(err)
    exception = Exception.format(type, message, stacktrace)

    Logger.error(fn ->
      ["Internal Server Error ", method, " ", path, "\n", exception]
    end)

    body = %{
      "error" => %{
        "message" => if Mix.env == :prod do
          "Internal server error"
        else
          exception
        end
      }
    }

    msg = Poison.encode!([[id, 500, %{}, body]])
    {:wait1_resp, self(), id, msg, [], []}
  end

  defp extract_connection_error({message, %Plug.Conn{method: method} = conn}) when is_binary(message) do
    {message, method, Plug.Conn.full_path(conn)}
  end
  defp extract_connection_error({message, %Plug.Conn{method: method} = conn}) do
    {inspect(message), method, Plug.Conn.full_path(conn)}
  end
  defp extract_connection_error(message) do
    {message, "", ""}
  end

  defp request(parent, method, path, req_headers, qs, body, plug, opts, init, redirect) do
    init
    |> Conn.conn(method, path, req_headers, qs, body)
    |> plug.call(opts)
    |> response(parent, plug, opts, init, redirect)
  end

  defp response(conn = %{adapter: {Conn, %{status: resp_status, headers: resp_headers, body: resp_body}}, resp_cookies: resp_cookies}, parent, plug, opts, init, redirect) do
    case Enum.reduce(resp_headers, %{}, &join_headers/2) do
      %{"location" => location} = resp_headers when resp_status == 302 or resp_status == 303 ->
        req_headers = conn.req_headers
        handle_redirect(parent, resp_headers, resp_cookies, req_headers)
        %{path: path, query: query} = URI.parse(location)
        request(parent, "GET", path, req_headers, query, nil, plug, opts, init, location)
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

  defp handle_redirect(parent, resp_headers, resp_cookies, req_headers) do
    additional_reqs = invalidates(resp_headers, req_headers)
    send(parent, {:wait1_redirect, self(), additional_reqs, resp_cookies})
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
