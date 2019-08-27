defmodule Tablespoon.Transport.FakeBtd do
  @moduledoc """
  Transport implementation which pretends to be Btd.

  It always replies to packets with a good response.
  """
  @behaviour Tablespoon.Transport

  alias Tablespoon.Protocol.NTCIP1211Extended, as: NTCIP
  alias Tablespoon.Protocol.PMPP

  defstruct [:ref, :buffer]

  @impl Tablespoon.Transport
  def new(_opts \\ []) do
    %__MODULE__{}
  end

  @impl Tablespoon.Transport
  def connect(%__MODULE__{} = t) do
    ref = make_ref()
    {:ok, %{t | ref: ref}}
  end

  @impl Tablespoon.Transport
  def send(%__MODULE__{} = t, data) do
    {:ok, pmpp, ""} = PMPP.decode(IO.iodata_to_binary(data))
    {:ok, ntcip} = NTCIP.decode(pmpp.body)
    ntcip_response = NTCIP.encode(%{ntcip | pdu_type: :response})
    pmpp = PMPP.encode(%{pmpp | body: ntcip_response})
    Kernel.send(self(), {t.ref, {:data, IO.iodata_to_binary(pmpp)}})
    {:ok, t}
  end

  @impl Tablespoon.Transport
  def stream(%__MODULE__{ref: ref} = t, {ref, message}) do
    {:ok, t, [message]}
  end

  def stream(%__MODULE__{}, _) do
    :unknown
  end
end
