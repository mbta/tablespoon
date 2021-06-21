defmodule Tablespoon.Transport.Fake do
  @moduledoc false
  @behaviour Tablespoon.Transport
  defstruct connect_count: 0, close_count: 0, sent: [], open?: false

  @impl Tablespoon.Transport
  def new(_opts \\ []) do
    %__MODULE__{}
  end

  @impl Tablespoon.Transport
  def connect(fake) do
    {:ok, %{fake | connect_count: fake.connect_count + 1, open?: true}}
  end

  @impl Tablespoon.Transport
  def close(fake) do
    %{fake | open?: false}
  end

  @impl Tablespoon.Transport
  def send(%__MODULE__{connect_count: count} = fake, iodata) when count > 0 do
    binary = IO.iodata_to_binary(iodata)
    {:ok, %{fake | sent: fake.sent ++ [binary]}}
  end

  def send(_fake, _) do
    {:error, :not_connected}
  end

  @impl Tablespoon.Transport
  def stream(%__MODULE__{connect_count: count} = fake, :close) when count > 0 do
    {:ok, fake, [:closed]}
  end

  def stream(%__MODULE__{connect_count: count} = fake, :empty) when count > 0 do
    {:ok, fake, []}
  end

  def stream(%__MODULE__{connect_count: count} = fake, iodata) when count > 0 do
    {:ok, fake, [data: IO.iodata_to_binary(iodata)]}
  end

  def stream(fake, _message) do
    {:ok, fake, []}
  end
end
