defmodule Tablespoon.Intersection.Duplicates do
  @moduledoc """
  Wrapper around Tablespoon.Duplicates, which maintains a global duplicate table.
  """
  require Logger
  use GenServer

  alias Tablespoon.{Duplicates, Query}

  @term_key __MODULE__

  # how often to scan for / clear duplicate message cache: 30m
  @scan_frequency 30 * 60_000

  def start_link(opts) do
    scan_frequency = Keyword.get(opts, :scan_frequency, @scan_frequency)
    GenServer.start_link(__MODULE__, scan_frequency)
  end

  @spec seen?(Query.t()) :: boolean
  def seen?(q) do
    case :persistent_term.get(@term_key) do
      %Duplicates{} = dups ->
        key = {q.intersection_alias, q.type, q.id}
        Duplicates.seen?(dups, key, q.received_at_mono)

      nil ->
        false
    end
  end

  @impl GenServer
  def init(scan_frequency) do
    dups = Duplicates.new()
    :persistent_term.put(__MODULE__, dups)
    {:ok, {dups, scan_frequency}, scan_frequency}
  end

  @impl GenServer
  def handle_info(:timeout, {dups, scan_frequency} = state) do
    Logger.info("#{__MODULE__} clearing duplicate message cache after #{scan_frequency}ms")
    Duplicates.expire(dups, System.monotonic_time() - scan_frequency)
    {:noreply, state, scan_frequency}
  end
end
