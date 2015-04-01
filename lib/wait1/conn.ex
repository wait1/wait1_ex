defmodule Plug.Adapters.Wait1.Conn do
  @behaviour Plug.Conn.Adapter
  alias :cowboy_req, as: Request

  defmodule QS do
    defstruct kvs: nil
  end

  defimpl String.Chars, for: QS do
    def to_string(qs) do
      Plug.Conn.Query.encode(qs.kvs)
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

  def conn(init, method, path, hdrs, nil) do
    headers = Map.get(init.private, :wait1_headers)
    %{ init |
      adapter: {__MODULE__, %{req_body: nil}},
      method: method,
      path_info: path,
      req_headers: Map.to_list(hdrs) ++ headers
    }
  end
  def conn(init, method, path, hdrs, body) do
    headers = Map.get(init.private, :wait1_headers)
    %{ init |
      adapter: {__MODULE__, %{req_body: body}},
      params: body,
      query_string: %QS{kvs: body},
      method: method,
      path_info: path,
      req_headers: Map.to_list(hdrs) ++ headers
    }
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
    {:ok, req.req_body, req}
  end

  def parse_req_multipart(req, _opts, _callback) do
    {:ok, [], req}
  end
end
