defmodule Tablespoon.Intersection do
  @moduledoc """
  Process representing a single intersection with TSP.
  """
  use GenServer
  require Logger
  alias Tablespoon.Query

  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: name(config.alias))
  end

  @doc "Send the given Query to the appropriate Intersection"
  @spec send_query(Query.t()) :: :ok
  def send_query(%Query{} = q) do
    name = name(q.intersection_alias)
    GenServer.cast(name, {:query, q})
  end

  @doc "For testing only: ensures the messages have been processed"
  @spec flush(Query.intersection_alias()) :: :ok
  def flush(intersection_alias) do
    intersection_alias
    |> name
    |> GenServer.call(:flush)
  end

  def child_spec(config) do
    %{
      id: {__MODULE__, config.id},
      start: {__MODULE__, :start_link, [config]}
    }
  end

  def name(intersection_alias) do
    {:via, Registry, {registry(), intersection_alias}}
  end

  def registry, do: __MODULE__.Registry

  # Server callbacks
  defstruct [:config, time_fn: nil]

  @impl GenServer
  def init(config) do
    Logger.info(fn ->
      "started Intersection id=#{config.id} alias=#{config.alias}"
    end)

    {:ok, %__MODULE__{config: config}, config.warning_timeout_ms}
  end

  @impl GenServer
  def handle_cast({:query, q}, %{config: config} = state) do
    Logger.info(fn ->
      event_time_iso =
        q.event_time
        |> DateTime.from_unix!(:native)
        |> DateTime.truncate(:second)
        |> DateTime.to_iso8601()

      processing_time = Query.processing_time(q, :microsecond)

      "Query - id=#{config.id} alias=#{config.alias} type=#{q.type} v_id=#{q.vehicle_id} approach=#{
        q.approach
      } event_time=#{event_time_iso} processing_time_us=#{processing_time}"
    end)

    {:noreply, state, config.warning_timeout_ms}
  end

  def handle_cast(message, state) do
    super(message, state)
  end

  @impl GenServer
  def handle_call(:flush, _from, state) do
    {:reply, :ok, state}
  end

  def handle_call(message, from, state) do
    super(message, from, state)
  end

  @impl GenServer
  def handle_info(:timeout, state) do
    config = state.config

    time =
      if state.time_fn do
        state.time_fn.()
      else
        :erlang.time()
      end

    if time >= config.warning_not_before_time and time <= config.warning_not_after_time do
      Logger.warn(fn ->
        "Intersection has not received a message in #{config.warning_timeout_ms}ms - id=#{
          config.id
        } alias=#{config.alias}"
      end)
    end

    {:noreply, state, config.warning_timeout_ms}
  end

  def handle_info(message, state) do
    super(message, state)
  end
end
