defmodule Tablespoon.Intersection do
  @moduledoc """
  Process representing a single intersection with TSP.
  """
  use GenServer
  require Logger
  alias __MODULE__.Config
  alias Tablespoon.{Communicator, Query}

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
    if intersection_alias
       |> name
       |> GenServer.call(:flush) == {:ok, 0} do
      :ok
    else
      Process.sleep(1)
      flush(intersection_alias)
    end
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
    {:ok, communicator} = Communicator.connect(config.communicator)
    config = %{config | communicator: communicator}

    _ =
      Logger.info(fn ->
        "started Intersection id=#{config.id} alias=#{config.alias} comm=#{
          Communicator.name(communicator)
        }"
      end)

    {:ok, %__MODULE__{config: config}, config.warning_timeout_ms}
  end

  @impl GenServer
  def handle_cast({:query, q}, %{config: config} = state) do
    {:ok, communicator, results} = Communicator.send(config.communicator, q)

    _ =
      Logger.info(fn ->
        event_time_iso =
          q.event_time
          |> DateTime.from_unix!(:native)
          |> DateTime.truncate(:second)
          |> DateTime.to_iso8601()

        "Query - id=#{config.id} alias=#{config.alias} comm=#{
          Communicator.name(config.communicator)
        } type=#{q.type} q_id=#{q.id} v_id=#{q.vehicle_id} approach=#{q.approach} event_time=#{
          event_time_iso
        }"
      end)

    config = %{config | communicator: communicator}
    config = Enum.reduce(results, config, &handle_results/2)
    state = %{state | config: config}

    {:noreply, state, config.warning_timeout_ms}
  end

  def handle_cast(message, state) do
    super(message, state)
  end

  @impl GenServer
  def handle_call(:flush, _from, state) do
    {:message_queue_len, len} = Process.info(self(), :message_queue_len)
    {:reply, {:ok, len}, state}
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

    _ =
      if time >= config.warning_not_before_time and time <= config.warning_not_after_time do
        Logger.warn(fn ->
          "Intersection has not received a message in #{config.warning_timeout_ms}ms - id=#{
            config.id
          } alias=#{config.alias}"
        end)
      end

    {:noreply, state, config.warning_timeout_ms}
  end

  def handle_info(message, %{config: config} = state) do
    case Communicator.stream(config.communicator, message) do
      {:ok, communicator, results} ->
        config = %{config | communicator: communicator}
        config = Enum.reduce(results, config, &handle_results/2)
        state = %{state | config: config}
        {:noreply, state, config.warning_timeout_ms}

      :unknown ->
        super(message, state)
    end
  end

  @spec handle_results(Communicator.result(), Config.t()) :: Config.t()
  def handle_results({:sent, q}, config) do
    _ =
      Logger.info(fn ->
        event_time_iso =
          q.event_time
          |> DateTime.from_unix!(:native)
          |> DateTime.truncate(:second)
          |> DateTime.to_iso8601()

        processing_time = Query.processing_time(q, :microsecond)

        "Response - id=#{config.id} alias=#{config.alias} comm=#{
          Communicator.name(config.communicator)
        } type=#{q.type} q_id=#{q.id} v_id=#{q.vehicle_id} approach=#{q.approach} event_time=#{
          event_time_iso
        } processing_time_us=#{processing_time}"
      end)

    config
  end

  def handle_results({:failed, q, error}, config) do
    _ =
      Logger.info(fn ->
        event_time_iso =
          q.event_time
          |> DateTime.from_unix!(:native)
          |> DateTime.truncate(:second)
          |> DateTime.to_iso8601()

        processing_time = Query.processing_time(q, :microsecond)

        "Failure - id=#{config.id} alias=#{config.alias} comm=#{
          Communicator.name(config.communicator)
        } type=#{q.type} q_id=#{q.id} v_id=#{q.vehicle_id} approach=#{q.approach} event_time=#{
          event_time_iso
        } processing_time_us=#{processing_time} error=#{inspect(error)}"
      end)

    config
  end
end
