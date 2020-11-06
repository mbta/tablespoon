defmodule Tablespoon.Transport.TCP do
  @moduledoc """
  Transport for sending/receiving bytes over TCP.

  To use:

  tcp = TCP.new(host: host, port: port)
  {:ok, tcp} = UDP.send(tcp, "packet")
  receive do
    x ->
      {:ok, tcp, results} = TCP.stream(tcp, x)
  end
  """
  require Logger
  @behaviour Tablespoon.Transport

  @tcp_opts [:binary, {:active, true}, {:nodelay, true}, {:keepalive, true}]
  @connect_timeout 5_000

  @enforce_keys [:host, :port]
  defstruct @enforce_keys ++ [:socket]

  @impl Tablespoon.Transport
  def new(opts) do
    struct!(__MODULE__, opts)
  end

  @impl Tablespoon.Transport
  def connect(%__MODULE__{} = tcp) do
    if tcp.socket do
      _ = :gen_tcp.close(tcp.socket)
      log_close(tcp)
    end

    case :gen_tcp.connect(
           :erlang.binary_to_list(tcp.host),
           tcp.port,
           @tcp_opts,
           @connect_timeout
         ) do
      {:ok, socket} ->
        _ =
          Logger.info(
            "#{__MODULE__} connected uri=#{tcp.host}:#{tcp.port} socket=#{inspect(socket)}"
          )

        tcp = %{tcp | socket: socket}
        {:ok, tcp}

      {:error, e} ->
        _ =
          Logger.info(
            "#{__MODULE__} failed to connect to uri=#{tcp.host}:#{tcp.port} error=#{inspect(e)}"
          )

        {:error, e}
    end
  end

  @impl Tablespoon.Transport
  def send(%__MODULE__{socket: socket} = tcp, packet) when is_port(socket) do
    with :ok <- :gen_tcp.send(tcp.socket, packet) do
      {:ok, tcp}
    end
  end

  @impl Tablespoon.Transport
  def stream(%__MODULE__{socket: socket} = tcp, {:tcp, socket, packet}) do
    {:ok, tcp, [data: packet]}
  end

  def stream(%__MODULE__{socket: socket} = tcp, {:tcp_error, socket, error}) do
    _ =
      Logger.warn(
        "#{__MODULE__} unexpected error uri=#{tcp.host}:#{tcp.port} socket=#{inspect(socket)} error=#{
          inspect(error)
        }"
      )

    # treat it as a closed connection
    stream(tcp, {:tcp_closed, socket})
  end

  def stream(%__MODULE__{socket: socket} = tcp, {:tcp_closed, socket}) do
    log_close(tcp)
    :ok = :gen_tcp.close(socket)
    tcp = %{tcp | socket: nil}
    {:ok, tcp, [:closed]}
  end

  def stream(%__MODULE__{}, _) do
    :unknown
  end

  defp log_close(tcp) do
    _ =
      Logger.info(
        "#{__MODULE__} connection closed uri=#{tcp.host}:#{tcp.port} socket=#{inspect(tcp.socket)}"
      )

    :ok
  end
end
