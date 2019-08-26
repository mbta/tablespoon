defmodule Tablespoon.Communicator do
  @moduledoc """
  Communicate with a remote service to handle TSP requests.

  A Communicator wraps up a Transport and a Protocol to turn Query messages
  into the appropriate requests upstream. It's also responsible for
  processing responses to let the intersection know whether sending the
  request succeeded or failed.
  """

  @type t :: struct
  @type error :: term
  @type result :: {:sent, Tablespoon.Query.t()} | {:failed, Tablespoon.Query.t(), error}
  @callback new(Tablespoon.Transport.t(), Keyword.t()) :: t
  @callback connect(t) :: {:ok, t} | {:error, error}
  @callback send(t, Tablespoon.Query.t()) :: {:ok, t, [result]} | {:error, error}
  @callback stream(t, term) :: {:ok, t, [result]} | {:error, error}
end
