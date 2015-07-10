defmodule Plug.Adapters.Wait1.Conn do
  @behaviour Plug.Conn.Adapter
  @moduledoc false

  alias :cowboy_req, as: Request
  alias Plug.Adapters.Wait1.Conn.QS

  @doc """
  Initialize the connection for future connections on this request.
  """
  def init(req, transport) do
    {host, req} = Request.host req
    {port, req} = Request.port req
    {peer, req} = Request.peer req
    {remote_ip, _} = peer

    conn = %Plug.Conn{
      host: host,
      owner: self(),
      peer: peer,
      port: port,
      remote_ip: remote_ip,
      scheme: scheme(transport)
    }

    {headers, req} = Request.headers req
    wait1_headers = Enum.filter(headers, fn({name, _}) ->
      case name do
        "cookie" -> true
        <<"x-forwarded-", _ :: binary>> -> true
        <<"x-orig-", _ :: binary>> -> true
        "user-agent" -> true
        "accept-language" -> true
        "origin" -> true
        "authorization" -> true
        _ -> false
      end
    end)
    conn = Plug.Conn.put_private(conn, :wait1_headers, wait1_headers)
    {:ok, conn, req}
  end

  @doc """
  Create a connection for the given request
  """
  def conn(init, method, [""], hdrs, qs, body) do
    conn(init, method, [], hdrs, qs, body)
  end
  def conn(init, method, path, hdrs, qs, body) when is_binary(path) do
    case String.split(path, "/") do
      [""] ->
        conn(init, method, [], hdrs, qs, body)
      ["", ""] ->
        conn(init, method, [], hdrs, qs, body)
      ["" | rest] ->
        rest = filter_slashes(rest, [])
        conn(init, method, rest, hdrs, qs, body)
      rest ->
        rest = filter_slashes(rest, [])
        conn(init, method, rest, hdrs, qs, body)
    end
  end
  def conn(init, method, path, hdrs, qs, body) when is_binary(qs) do
    conn(init, method, path, hdrs, Plug.Conn.Query.decode(qs), body)
  end
  def conn(init, method, path, hdrs, qs, body) when is_map(hdrs) do
    conn(init, method, path, :maps.to_list(hdrs), qs, body)
  end
  def conn(init = %{private: %{wait1_headers: headers}}, method, path, hdrs, qs, body) do
    %{ init |
      adapter: {__MODULE__, %{}},
      params: merge_params(qs, body),
      query_params: qs || %{},
      body_params: body || %{},
      query_string: %QS{kvs: qs},
      method: method,
      path_info: path,
      req_headers: hdrs ++ headers
    }
  end

  @doc """
  Update the initial connection's cookies
  """
  def update_cookies(init, resp_cookies) do
    headers = Enum.map(resp_cookies, fn({key, %{value: value}}) ->
      {"cookie", "#{key}=#{value}"}
    end)
    Plug.Conn.put_private(init, :wait1_headers, headers ++ init.private.wait1_headers)
  end

  defp filter_slashes([], acc) do
    :lists.reverse(acc)
  end
  defp filter_slashes(["" | rest], acc) do
    filter_slashes(rest, acc)
  end
  defp filter_slashes([part | rest], acc) do
    filter_slashes(rest, [part | acc])
  end

  defp merge_params(other, param) when not is_map(other) do
    merge_params(%{}, param)
  end
  defp merge_params(param, other) when not is_map(other) do
    merge_params(param, %{})
  end
  defp merge_params(param1, param2) do
    Map.merge(param1, param2)
  end

  defp scheme(:tcp), do: :ws
  defp scheme(:ssl), do: :wss

  def send_resp(req, status, headers, body) do
    req = Map.merge(req, %{
      status: status,
      headers: headers,
      body: body
    })
    {:ok, nil, req}
  end

  def send_chunked(req, _status, _headers, _body) do
    {:ok, nil, req}
  end

  def send_chunked(_req, _, _) do
    raise :not_implemented
  end

  def send_file(_req, _, _, _, _, _) do
    raise :not_implemented
  end

  def chunk(req, _body) do
    {:ok, nil, req}
  end

  def read_req_body(req, _opts \\ []) do
    {:ok, "", req}
  end

  def parse_req_multipart(req, _opts, _callback) do
    {:ok, [], req}
  end
end
