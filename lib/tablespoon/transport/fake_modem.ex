defmodule Tablespoon.Transport.FakeModem do
  @moduledoc """
  Transport implementation which pretends to be a modem.

  By default, sends an initial "OK\n" line, then responds to any lines it receives with "OK".

  However, there are some configuration variables that can be set to change that.

  - send_error_rate: the percent of messages which result in a sending error (1 to 100)
  - disconnect_rate: the percent of replies which result in a disconnection (to 100)
  - delay_range: a range of milliseconds by which to delay replies
  """
  @behaviour Tablespoon.Transport

  alias Tablespoon.Protocol.Line
  require Logger

  defstruct [
    :ref,
    :buffer,
    connect_error_rate: 0,
    send_error_rate: 0,
    response_error_rate: 0,
    disconnect_rate: 0,
    delay_range: 0..0
  ]

  @impl Tablespoon.Transport
  def new(opts \\ []) do
    struct(__MODULE__, opts)
  end

  @impl Tablespoon.Transport
  def connect(%__MODULE__{} = t) do
    if trigger?(t.connect_error_rate) do
      {:error, :failed_to_connect}
    else
      ref = make_ref()
      t = %{t | ref: ref, buffer: ""}
      reply(t)
      {:ok, t}
    end
  end

  @impl Tablespoon.Transport
  def close(%__MODULE__{} = t) do
    %{t | ref: nil, buffer: ""}
  end

  @impl Tablespoon.Transport
  def send(%__MODULE__{ref: nil}, _) do
    {:error, :not_connected}
  end

  def send(%__MODULE__{} = t, data) do
    if trigger?(t.send_error_rate) do
      {:error, :trigger_failed}
    else
      buffer = IO.iodata_to_binary([t.buffer, data])
      t = %{t | buffer: buffer}
      handle_buffer(t)
    end
  end

  @impl Tablespoon.Transport
  def stream(%__MODULE__{ref: ref} = t, {ref, message}) do
    if trigger?(t.disconnect_rate) do
      t = %{t | ref: nil, buffer: ""}
      {:ok, t, [:closed]}
    else
      {:ok, t, [message]}
    end
  end

  def stream(%__MODULE__{}, _) do
    :unknown
  end

  defp reply(t, data \\ "OK") do
    delay = Enum.random(t.delay_range)

    Enum.each([data, "\r", "\n"], fn message ->
      send_after(self(), {t.ref, {:data, message}}, delay)
    end)

    :ok
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

  defp handle_line(t, "AT*RELAYOUT" <> _ = line) do
    reply(t, line)

    if trigger?(t.response_error_rate) do
      reply(t, "ERROR")
    else
      reply(t)
    end

    handle_buffer(t)
  end

  defp handle_line(t, "") do
    handle_buffer(t)
  end

  def trigger?(rate) do
    Enum.random(1..100) <= rate
  end

  defp send_after(pid, message, delay) when delay > 0 do
    Process.send_after(pid, message, delay)
  end

  defp send_after(pid, message, _delay) do
    Kernel.send(pid, message)
  end
end
