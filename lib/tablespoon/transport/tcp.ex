defmodule Tablespoon.Transport.TCP do
  @moduledoc """
  Transport for sending/receiving bytes over TCP.

  To use:

  tcp = TCP.new(host: host, port: port)
  {:ok, tcp} = TCP.send(tcp, "packet")
  receive do
    x ->
      {:ok, tcp, results} = TCP.stream(tcp, x)
  end
  """
  require Logger
  @behaviour Tablespoon.Transport

  @tcp_always_opts [:binary, {:active, true}]
  @tcp_default_opts [{:nodelay, true}, {:keepalive, true}]
  @connect_timeout 5_000
  # 2 hours
  @keepalive_timeout_s 7_200

  @enforce_keys [:host, :port]
  defstruct @enforce_keys ++
              [:socket, keepalive_timeout_s: @keepalive_timeout_s, opts: @tcp_default_opts]

  @impl Tablespoon.Transport
  def new(opts) do
    struct!(__MODULE__, opts)
  end

  @impl Tablespoon.Transport
  def connect(%__MODULE__{} = tcp) do
    tcp = close(tcp)

    case :gen_tcp.connect(
           :erlang.binary_to_list(tcp.host),
           tcp.port,
           @tcp_always_opts ++ tcp.opts,
           @connect_timeout
         ) do
      {:ok, socket} ->
        {:ok, local_port} = :inet.port(socket)

        _ =
          Logger.info(
            "#{__MODULE__} connected uri=#{tcp.host}:#{tcp.port} local_port=#{local_port} socket=#{inspect(socket)}"
          )

        _ = set_tcp_keepalive_timeout(socket, tcp.keepalive_timeout_s)

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
  def close(%__MODULE__{} = tcp) do
    _ =
      if tcp.socket do
        # shutdown for writing to ensure that any buffered data is sent
        _ = :gen_tcp.shutdown(tcp.socket, :write)
        :ok = :gen_tcp.close(tcp.socket)
        log_close(tcp)
      end

    %{tcp | socket: nil}
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
      Logger.warning(
        "#{__MODULE__} unexpected error uri=#{tcp.host}:#{tcp.port} socket=#{inspect(socket)} error=#{inspect(error)}"
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

  @doc """
  Set the TCP KeepAlive timeout to a new value.

  This uses an OS-specific constant, defined by tcp_keepidle/1.
  """
  @spec set_tcp_keepalive_timeout(port, pos_integer) :: :ok | {:error, term}
  def set_tcp_keepalive_timeout(socket, keepalive_s)
      when is_port(socket) and is_integer(keepalive_s) and keepalive_s > 0 do
    ipproto_tcp = 6

    with {:ok, tcp_keepidle} <- tcp_keepidle(:os.type()) do
      value = <<keepalive_s::native-integer-32>>
      :inet.setopts(socket, [{:raw, ipproto_tcp, tcp_keepidle, value}])
    end
  end

  # lazily based on the values Go uses: https://github.com/golang/go/search?p=1&q=TCP_KEEPIDLE
  defp tcp_keepidle({:unix, :darwin}), do: {:ok, 16}
  defp tcp_keepidle({:unix, :linux}), do: {:ok, 4}
  defp tcp_keepidle({:unix, :freebsd}), do: {:ok, 256}
  defp tcp_keepidle({:unix, :netbsd}), do: {:ok, 3}
  defp tcp_keepidle(os), do: {:error, {:unknown_os, os}}

  defp log_close(tcp) do
    _ =
      Logger.info(
        "#{__MODULE__} connection closed uri=#{tcp.host}:#{tcp.port} socket=#{inspect(tcp.socket)}"
      )

    :ok
  end
end
