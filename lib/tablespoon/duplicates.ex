defmodule Tablespoon.Duplicates do
  @moduledoc """
  Detect duplicate message IDs with a rolling timespan.
  """
  @enforce_keys [:tid]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          tid: :ets.tid()
        }

  @spec new :: t()
  def new do
    %__MODULE__{
      tid: :ets.new(:duplicates, [:set, :public, {:read_concurrency, true}])
    }
  end

  @doc """
  Returns a boolean indicating whether we've seen the given term before.

  If not, store the term and the time we saw it.

  ## Examples

      iex> dup = Tablespoon.Duplicates.new()
      iex> Tablespoon.Duplicates.seen?(dup, 1, 1)
      false
      iex> Tablespoon.Duplicates.seen?(dup, 2, 2)
      false
      iex> Tablespoon.Duplicates.seen?(dup, 1, 3)
      true
  """
  @spec seen?(t(), term(), integer()) :: boolean
  def seen?(dups, term, seen_at)

  def seen?(%__MODULE__{tid: tid}, term, seen_at) do
    :ets.insert_new(tid, {term, seen_at}) == false
  end

  @doc """
  Expire terms seen before the given timestamp.

  ## Example

      iex> dup = Tablespoon.Duplicates.new()
      iex> Tablespoon.Duplicates.seen?(dup, 1, 0)
      false
      iex> Tablespoon.Duplicates.expire(dup, 1)
      :ok
      iex> Tablespoon.Duplicates.seen?(dup, 1, 2)
      false
  """
  @spec expire(t(), integer()) :: :ok
  def expire(dup, seen_before)

  def expire(%__MODULE__{tid: tid}, seen_before) do
    :ets.select_delete(tid, [{{:_, :"$1"}, [{:<, :"$1", seen_before}], [true]}])

    :ok
  end
end
