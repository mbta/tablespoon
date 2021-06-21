defmodule Tablespoon.Communicator do
  @moduledoc """
  Communicate with a remote service to handle TSP requests.

  A Communicator wraps up a Transport and a Protocol to turn Query messages
  into the appropriate requests upstream. It's also responsible for
  processing responses to let the intersection know whether sending the
  request succeeded or failed.
  """

  alias Tablespoon.{Query, Transport}

  @type t :: struct
  @type error :: term
  @type result :: {:sent, Query.t()} | {:failed, Query.t(), error} | {:error, error}
  @callback new(Transport.t(), Keyword.t()) :: t
  @callback connect(t) :: {:ok, t, [result]} | {:error, error}
  @callback close(t) :: {:ok, t, [result]}
  @callback send(t, Query.t()) :: {:ok, t, [result]} | {:error, error}
  @callback stream(t, term) :: {:ok, t, [result]} | :unknown

  @doc """
  The name of the Communicator, based on the struct.

  iex> Communicator.name(Communicator.Modem.new(nil))
  "Modem"
  """
  @spec name(t) :: String.t()
  def name(%{__struct__: module}) do
    module
    |> Module.split()
    |> List.last()
  end

  @spec connect(t) :: {:ok, t, [result]} | {:error, error}
  def connect(%{__struct__: module} = comm) do
    module.connect(comm)
  end

  @spec close(t) :: {:ok, t, [result]}
  def close(%{__struct__: module} = comm) do
    module.close(comm)
  end

  @spec send(t, Query.t()) :: {:ok, t, [result]} | {:error, error}
  def send(%{__struct__: module} = comm, %Query{} = q) do
    module.send(comm, q)
  end

  @spec stream(t, term) :: {:ok, t, [result]} | {:error, error} | :unknown
  def stream(%{__struct__: module} = comm, message) do
    module.stream(comm, message)
  end
end
