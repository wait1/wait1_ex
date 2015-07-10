defmodule Plug.Adapters.Wait1.Handler do
  @moduledoc false

  alias :cowboy_req, as: Request
  alias Plug.Adapters.Wait1.Protocol

  def init({transport, :http}, req, {plug, opts, onconnection}) when transport in [:tcp, :ssl] do
    case Request.header("upgrade", req) do
      {upgrade, _} when upgrade in ["Websocket", "websocket"] ->
        case onconnection.(req) do
          {:ok, req} ->
            case Request.parse_header("sec-websocket-protocol", req) do
              {:ok, protocols, req} when is_list(protocols) ->
                req = select_protocol(protocols, req)
                {:upgrade, :protocol, :cowboy_websocket, req, {plug, opts}}
              {:ok, _, req} ->
                {:upgrade, :protocol, :cowboy_websocket, req, {plug, opts}}
            end
          {:halt, req} ->
            {:shutdown, req, {plug, opts, onconnection}}
        end
      _ ->
        {:upgrade, :protocol, Protocol, req, {transport, plug, opts}}
    end
  end

  defdelegate websocket_init(transport, req, opts), to: Protocol
  defdelegate websocket_handle(msg, req, state), to: Protocol
  defdelegate websocket_info(msg, req, state), to: Protocol
  defdelegate websocket_terminate(reason, req, state), to: Protocol

  defp select_protocol([], req) do
    req
  end
  defp select_protocol(["wait1" | rest], req) do
    select_protocol(rest, Request.set_resp_header("sec-websocket-protocol", "wait1", req))
  end
  defp select_protocol([<<"wait1|t", token :: binary>> | rest], req) do
    headers = [{"authorization", "Bearer " <> token} | Request.get(:headers, req)]
    select_protocol(rest, Request.set([headers: headers], req))
  end
  defp select_protocol([<<"wait1|b", basic :: binary>> | rest], req) do
    headers = [{"authorization", "Basic " <> basic} | Request.get(:headers, req)]
    select_protocol(rest, Request.set([headers: headers], req))
  end
  defp select_protocol([_ | rest], req) do
    select_protocol(rest, req)
  end
end
