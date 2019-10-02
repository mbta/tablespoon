defmodule Tablespoon.Transport.PMPPMultiplex do
  @moduledoc """
  Transport which serves to multiplex several senders over a single transport.

  Since we don't know who responses are for directly, we treat them as a FIFO queue. The first response is for the first sender, &c.
  """
  @behaviour Tablespoon.Transport

  @enforce_keys [:transport, :address, :id_mfa]
  defstruct [:transport, :address, :id_mfa, :from]

  @impl Tablespoon.Transport
  def new(opts) when is_list(opts) do
    struct!(__MODULE__, opts)
  end

  @impl Tablespoon.Transport
  def connect(%__MODULE__{} = t) do
    case DynamicSupervisor.start_child(dynamic_supervisor(), child_spec(t)) do
      {:ok, pid} ->
        monitor_and_set_from(t, pid)

      {:error, {:already_started, pid}} ->
        monitor_and_set_from(t, pid)

      e ->
        e
    end
  end

  @impl Tablespoon.Transport
  def send(%__MODULE__{from: from} = t, iodata) when from != nil do
    with :ok <- __MODULE__.Child.send(from, iodata) do
      {:ok, t}
    end
  catch
    :exit, _ ->
      {:error, :not_started}
  end

  def send(%__MODULE__{}, _) do
    {:error, :not_connected}
  end

  @impl Tablespoon.Transport
  def stream(%__MODULE__{from: {_pid, ref}} = t, {ref, response}) do
    handle_response(t, response)
  end

  def stream(%__MODULE__{from: {pid, ref}} = t, {:DOWN, ref, :process, pid, _}) do
    # parent process died, so treat that as a close
    handle_response(t, :closed)
  end

  def stream(%__MODULE__{}, _) do
    :unknown
  end

  defp monitor_and_set_from(t, pid) do
    ref = Process.monitor(pid)
    {:ok, %{t | from: {pid, ref}}}
  end

  defp handle_response(t, :closed = response) do
    t = %{t | from: nil}
    {:ok, t, [response]}
  end

  defp handle_response(t, response) do
    {:ok, t, [response]}
  end

  defp child_spec(%__MODULE__{transport: transport, address: address, id_mfa: {m, f, a}} = t) do
    {__MODULE__.Child, {transport, address, &apply(m, f, [&1 | a]), child_name(t)}}
  end

  defp child_name(%{transport: transport, address: address}) do
    {:via, Registry, {__MODULE__.Registry, {transport, address}}}
  end

  def registry, do: __MODULE__.Registry
  def dynamic_supervisor, do: __MODULE__.DynamicSupervisor
end
