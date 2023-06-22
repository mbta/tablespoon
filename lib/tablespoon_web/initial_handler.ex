defmodule TablespoonWeb.InitialHandler do
  @moduledoc """
  The initial Handler, called on all incoming connections to the HTTP port.

  Reads the first bytes from the socket to decide whether to treat it as an HTTP
  request or as a Transitmaster XML packet.

  See also https://github.com/mtrudel/bandit/blob/main/lib/bandit/delegating_handler.ex
  """

  use ThousandIsland.Handler

  require Logger

  @type on_switch_handler ::
          {:switch, Bandit.HTTP1.Handler, data :: binary(), state :: term()}

  # Dialyzer complains about the `switch` returns, but it's okay: they're
  # handled by Bandit.DelegatingHandler.
  @impl ThousandIsland.Handler
  @spec handle_connection(ThousandIsland.Socket.t(), state :: term()) ::
          ThousandIsland.Handler.handler_result() | on_switch_handler()
  def handle_connection(socket, state) do
    case sniff_wire(socket) do
      {:transitmaster, data} ->
        {:switch, TablespoonTcp.Handler, data, state}

      {:unknown, data} ->
        {:switch, Bandit.HTTP1.Handler, data, state}

      _ ->
        {:close, state}
    end
  end

  @transitmaster_header Tablespoon.Protocol.TransitmasterXml.header()
  @transitmaster_header_size byte_size(@transitmaster_header)

  # Returns the protocol as suggested by received data, if possible
  @spec sniff_wire(ThousandIsland.Socket.t()) ::
          {:transitmaster, binary()}
          | {:unknown, binary()}
          | {:error, :closed | :timeout | :inet.posix()}
  defp sniff_wire(socket) do
    case ThousandIsland.Socket.recv(socket, @transitmaster_header_size) do
      {:ok, @transitmaster_header} -> {:transitmaster, @transitmaster_header}
      {:ok, other} -> {:unknown, other}
      {:error, error} -> {:error, error}
    end
  end
end
