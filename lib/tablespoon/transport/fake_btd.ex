defmodule Tablespoon.Transport.FakeBtd do
  @moduledoc """
  Transport implementation which pretends to be Btd.

  By default, it always replies to packets with a good response.

  However, there are some configuration variables that can be set to change that.

  - drop_rate: the percent of messages which are not sent (1 to 100)
  - send_error_rate: the percent of messages which result in a sending error (1 to 100)
  - disconnect_rate: the percent of replies which result in a disconnection (to 100)
  - delay_range: a range of milliseconds by which to delay replies
  """
  @behaviour Tablespoon.Transport

  alias Tablespoon.Protocol.NTCIP1211Extended, as: NTCIP

  defstruct [
    :ref,
    drop_rate: 0,
    send_error_rate: 0,
    disconnect_rate: 0,
    delay_range: 0..0
  ]

  @impl Tablespoon.Transport
  def new(opts \\ []) do
    struct(__MODULE__, opts)
  end

  @impl Tablespoon.Transport
  def connect(%__MODULE__{} = t) do
    ref = make_ref()
    {:ok, %{t | ref: ref}}
  end

  @impl Tablespoon.Transport
  def send(%__MODULE__{ref: nil}, _data) do
    {:error, :not_connected}
  end

  def send(%__MODULE__{} = t, data) do
    cond do
      trigger?(t.drop_rate) ->
        {:ok, t}

      trigger?(t.send_error_rate) ->
        {:error, :trigger_failed}

      true ->
        {:ok, ntcip} = NTCIP.decode(IO.iodata_to_binary(data))
        ntcip_response = NTCIP.encode(%{ntcip | pdu_type: :response})
        message = {t.ref, {:data, IO.iodata_to_binary(ntcip_response)}}
        delay = Enum.random(t.delay_range)
        _ = Process.send_after(self(), message, delay)
        {:ok, t}
    end
  end

  @impl Tablespoon.Transport
  def stream(%__MODULE__{ref: ref} = t, {ref, message}) do
    if trigger?(t.disconnect_rate) do
      t = %{t | ref: nil}
      {:ok, t, [:closed]}
    else
      {:ok, t, [message]}
    end
  end

  def stream(%__MODULE__{}, _) do
    :unknown
  end

  def trigger?(rate) do
    Enum.random(1..100) <= rate
  end
end
