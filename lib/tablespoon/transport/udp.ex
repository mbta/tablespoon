defmodule Tablespoon.Transport.UDP do
  @moduledoc """
  Transport for sending/receiving bytes over UDP.

  To use:

  udp = UDP.new(host: host, port: por)
  {:ok, udp} = UDP.send(udp, "packet")
  receive do
    x ->
      {:ok, udp, results} = UDP.stream(udp, x)
  end
  """
  @behaviour Tablespoon.Transport

  @enforce_keys [:host, :port]
  defstruct @enforce_keys ++ [:socket]

  @impl Tablespoon.Transport
  def new(opts) do
    opts = Keyword.update!(opts, :host, &:erlang.binary_to_list/1)
    struct!(__MODULE__, opts)
  end

  @impl Tablespoon.Transport
  def connect(%__MODULE__{} = udp) do
    with {:ok, socket} <- :gen_udp.open(0, [:binary, {:active, true}]) do
      udp = %{udp | socket: socket}
      {:ok, udp}
    end
  end

  @impl Tablespoon.Transport
  def send(%__MODULE__{} = udp, packet) do
    with :ok <- :gen_udp.send(udp.socket, udp.host, udp.port, packet) do
      {:ok, udp}
    end
  end

  @impl Tablespoon.Transport
  def stream(%__MODULE__{socket: socket, port: port} = udp, {:udp, socket, _ip, port, packet}) do
    {:ok, udp, [data: packet]}
  end

  def stream(%__MODULE__{}, _) do
    :unknown
  end
end
