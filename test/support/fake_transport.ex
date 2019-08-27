defmodule Tablespoon.Transport.Fake do
  @moduledoc false
  @behaviour Tablespoon.Transport
  defstruct connected?: false, sent: []

  @impl Tablespoon.Transport
  def new(_opts \\ []) do
    %__MODULE__{}
  end

  @impl Tablespoon.Transport
  def connect(fake) do
    {:ok, %{fake | connected?: true}}
  end

  @impl Tablespoon.Transport
  def send(%__MODULE__{connected?: true} = fake, iodata) do
    binary = IO.iodata_to_binary(iodata)
    {:ok, %{fake | sent: fake.sent ++ [binary]}}
  end

  def send(_fake, _) do
    {:error, :not_connected}
  end

  @impl Tablespoon.Transport
  def stream(%__MODULE__{connected?: true} = fake, iodata) do
    {:ok, fake, [data: IO.iodata_to_binary(iodata)]}
  end

  def stream(fake, _message) do
    {:ok, fake, []}
  end
end
