defmodule Plug.Adapters.Wait1.TestFixture do
  use Plug.Router

  plug :match
  plug :dispatch

  def init(options) do
    # initialize options
    options
  end

  get "/" do
    send_resp(conn, 200, Poison.encode!(%{"hello" => "world"}))
  end
  get "/redirect" do
    conn
    |> put_resp_header("location", "/")
    |> send_resp(303, "")
  end
  post "/invalidate" do
    %{conn | resp_headers: [{"x-invalidates", "/"}, {"x-invalidates", "/redirect"}]}
    |> send_resp(200, "")
  end
  get "/raise" do
    put_resp_header(conn, "foo", "bar")
    raise :fake_error
  end
  get "/throw" do
    put_resp_header(conn, "foo", "bar")
    throw :fake_error
  end

  match _ do
    send_resp(conn, 404, "")
  end
end

ExUnit.start()
