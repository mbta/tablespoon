defmodule Tablespoon.Transport.FakeModem do
  @moduledoc """
  Transport implementation which pretends to be a modem.

  It sends an initial "OK\n" line, then responds to any lines it receives with "OK".
  """
  @behaviour Tablespoon.Transport

  alias Tablespoon.Protocol.Line
  require Logger
  defstruct [:ref, :buffer]

  @impl Tablespoon.Transport
  def new(_opts \\ []) do
    %__MODULE__{}
  end

  @impl Tablespoon.Transport
  def connect(%__MODULE__{} = t) do
    ref = make_ref()
    t = %{t | ref: ref, buffer: ""}
    reply_ok(t)
    {:ok, t}
  end

  @impl Tablespoon.Transport
  def send(%__MODULE__{} = t, data) do
    buffer = IO.iodata_to_binary([t.buffer, data])
    t = %{t | buffer: buffer}
    handle_buffer(t)
  end

  @impl Tablespoon.Transport
  def stream(%__MODULE__{ref: ref} = t, {ref, message}) do
    {:ok, t, [message]}
  end

  def stream(%__MODULE__{}, _) do
    :unknown
  end

  defp reply_ok(t) do
    Kernel.send(self(), {t.ref, {:data, "OK"}})
    Kernel.send(self(), {t.ref, {:data, "\r"}})
    Kernel.send(self(), {t.ref, {:data, "\n"}})
  end

  defp handle_buffer(t) do
    case Line.decode(t.buffer) do
      {:ok, line, rest} ->
        t = %{t | buffer: rest}
        handle_line(t, line)

      {:error, :too_short} ->
        {:ok, t}
    end
  end

  defp handle_line(t, "") do
    handle_buffer(t)
  end

  defp handle_line(t, "AT*RELAYOUT" <> _) do
    reply_ok(t)
    handle_buffer(t)
  end
end
