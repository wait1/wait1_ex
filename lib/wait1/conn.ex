defmodule Plug.Adapters.Wait1.Conn do
  @behaviour Plug.Conn.Adapter
  alias :cowboy_req, as: Request

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
    cookies = for {"cookie", _} = h <- headers, do: h
    conn = Plug.Conn.put_private(conn, :wait1_cookies, cookies)
    {:ok, conn, req}
  end

  def conn(init, method, path, qs, hdrs, body) do
    cookies = Map.get(init.private, :wait1_cookies)
    %{ init |
      adapter: {__MODULE__, %{req_body: body}},
      method: method,
      path_info: path,
      query_string: qs,
      req_headers: Map.to_list(hdrs) ++ cookies
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
