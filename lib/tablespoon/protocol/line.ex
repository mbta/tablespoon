defmodule Tablespoon.Protocol.Line do
  @moduledoc """
  Implementation of a simple line-based protocol.

  Accepts any line ending in \n with 0 or more \r beforehand.
  """

  @type error :: :too_short

  @suffix "\n"

  @doc "Encode a line and the suffix"
  @spec encode(binary) :: iodata
  def encode(line) do
    [line, @suffix]
  end

  @doc "Decode a line and any extra data"
  @spec decode(binary) :: {:ok, binary, binary} | {:error, error}
  def decode(binary) when is_binary(binary) do
    case :binary.split(binary, @suffix) do
      [line, rest] ->
        {:ok, String.trim_trailing(line, "\r"), rest}

      [_] ->
        {:error, :too_short}
    end
  end
end
