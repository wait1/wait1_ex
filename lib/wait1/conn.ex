defmodule Plug.Adapters.Wait1.Conn do
  @behaviour Plug.Conn.Adapter
  alias :cowboy_req, as: Request

  defmodule QS do
    defstruct kvs: nil
  end

  defimpl String.Chars, for: QS do
    def to_string(%{:kvs => kvs}) when is_map(kvs) do
      Plug.Conn.Query.encode(kvs)
    end
    def to_string(%{:kvs => kvs}) when is_binary(kvs) do
      kvs
    end
    def to_string(_) do
      ""
    end
  end

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
        _ -> false
      end
    end)
    conn = Plug.Conn.put_private(conn, :wait1_headers, wait1_headers)
    {:ok, conn, req}
  end

  def conn(init, method, path, hdrs, qs, body) when is_binary(path) do
    case String.split("/", path) do
      [""] ->
        conn(init, method, [], hdrs, qs, body)
      ["", ""] ->
        conn(init, method, [], hdrs, qs, body)
      [_ | rest] ->
        conn(init, method, rest, hdrs, qs, body)
    end
  end
  def conn(init, method, path, hdrs, qs, body) when is_binary(qs) do
    conn(init, method, path, hdrs, Plug.Conn.Query.decode(qs), body)
  end
  def conn(init, method, path, hdrs, qs, body) do
    headers = Map.get(init.private, :wait1_headers)
    %{ init |
      adapter: {__MODULE__, %{}},
      params: merge_params(qs, body),
      query_string: %QS{kvs: qs},
      method: method,
      path_info: path,
      req_headers: Map.to_list(hdrs) ++ headers
    }
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
