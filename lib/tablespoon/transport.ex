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

  @doc "Call connect/1 on the implementation struct"
  def connect(struct) do
    struct.__struct__.connect(struct)
  end

  @doc "Call stream/2 on the implementation struct"
  def stream(struct, message) do
    struct.__struct__.stream(struct, message)
  end

  @doc "Call send/2 on the implementation struct"
  def send(struct, iodata) do
    struct.__struct__.send(struct, iodata)
  end
end
