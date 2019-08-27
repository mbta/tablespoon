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
  @type result :: {:sent, Query.t()} | {:failed, Query.t(), error}
  @callback new(Transport.t(), Keyword.t()) :: t
  @callback connect(t) :: {:ok, t} | {:error, error}
  @callback send(t, Query.t()) :: {:ok, t, [result]} | {:error, error}
  @callback stream(t, term) :: {:ok, t, [result]} | {:error, error}

  def connect(%{__struct__: module} = comm) do
    module.connect(comm)
  end

  def send(%{__struct__: module} = comm, %Query{} = q) do
    module.send(comm, q)
  end

  def stream(%{__struct__: module} = comm, message) do
    module.stream(comm, message)
  end
end
