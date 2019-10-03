defmodule Tablespoon.UniqueRangeCounter do
  @moduledoc """
  Returns a unique value in a given range.

  Normally, we could use :erlang.unique_integer() to handle this. However,
  some clients require that the unique value be within a particular range
  (say, 256 to 65535) in order to fit into exactly 2 bytes.
  """
  use GenServer

  @name __MODULE__

  def start_link(_) do
    GenServer.start_link(__MODULE__, @name)
  end

  @doc """
  Return a unique integer in the given range: min_value <= x <= max_value.

  # Example

  iex> unique_integer(:key, 5, 10)
  5
  iex> unique_integer(:key, 5, 10)
  6
  iex> unique_integer(:key, 5, 10)
  7

  iex> unique_integer(:key2, 0, 1)
  0
  iex> unique_integer(:key2, 0, 1)
  1
  iex> unique_integer(:key2, 0, 1)
  0
  """
  @spec unique_integer(atom, integer, integer) :: integer
  def unique_integer(key, min_value, max_value)
      when is_atom(key) and is_integer(min_value) and is_integer(max_value) and
             min_value < max_value do
    :ets.update_counter(@name, key, {2, 1, max_value, min_value}, {key, min_value - 1})
  end

  # Server callbacks
  def init(table_name) do
    ^table_name =
      :ets.new(table_name, [
        :named_table,
        :public,
        {:read_concurrency, true},
        {:write_concurrency, true}
      ])

    {:ok, table_name}
  end
end
