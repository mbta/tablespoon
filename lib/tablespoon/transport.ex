defmodule Tablespoon.Transport do
  @moduledoc """
  Behaviour for modules which send/receive binary data.
  """

  @type t :: term
  @type result :: {:data, binary} | :closed
  @type error :: term

  @callback new(Keyword.t()) :: t
  @callback connect(t) :: {:ok, t} | {:error, error}
  @callback stream(t, term) :: {:ok, t, [result]} | {:error, error} | :unknown
  @callback send(t, iodata) :: {:ok, t} | {:error, error}
end
