defmodule Tablespoon.Intersection do
  @moduledoc """
  Process representing a single intersection with TSP.
  """
  use GenServer
  require Logger
  alias __MODULE__.Config
  alias Tablespoon.{Communicator, Query}

  # how long to wait before trying to reconnect to an intersection at most: 1hr
  @max_reconnect_timeout 3_600_000

  def start_link(opts) do
    config = Keyword.fetch!(opts, :config)
    GenServer.start_link(__MODULE__, opts, name: name(config.alias))
  end

  @doc "Send the given Query to the appropriate Intersection"
  @spec send_query(Query.t()) :: :ok
  def send_query(%Query{} = q) do
    name = name(q.intersection_alias)

    if GenServer.whereis(name) do
      GenServer.cast(name, {:query, q})
    else
      _ =
        Logger.warn(fn ->
          event_time_iso =
            q.event_time
            |> DateTime.from_unix!(:native)
            |> DateTime.truncate(:second)
            |> DateTime.to_iso8601()

          "Query received for invalid Intersection alias=#{q.intersection_alias} type=#{q.type} q_id=#{
            q.id
          } v_id=#{q.vehicle_id} approach=#{q.approach} event_time=#{event_time_iso}"
        end)

      :ok
    end
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

  def child_spec(opts) do
    config = Keyword.fetch!(opts, :config)

    %{
      id: {__MODULE__, config.alias},
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  def name(intersection_alias) do
    {:via, Registry, {registry(), intersection_alias}}
  end

  def registry, do: __MODULE__.Registry

  # Server callbacks
  defstruct [
    :config,
    :fuse_name,
    connected?: false,
    connect_failure_count: 0,
    time_fn: &:erlang.time/0
  ]

  @typep t :: %__MODULE__{
           config: Config.t(),
           fuse_name: atom,
           connected?: boolean,
           connect_failure_count: non_neg_integer,
           time_fn: (() -> :calendar.time())
         }

  @impl GenServer
  def init(opts) do
    config = Keyword.fetch!(opts, :config)
    fuse_name = String.to_atom("intersection_fuse_#{config.alias}")
    state = %__MODULE__{config: config, fuse_name: fuse_name}
    install_fuse(state, Keyword.get_lazy(opts, :fuse_options, &default_fuse_options/0))
    {:ok, state, {:continue, :connect}}
  end

  @impl GenServer
  def handle_cast({:query, q}, %{config: config} = state) do
    {:ok, communicator, results} =
      cond do
        not state.connected? ->
          {:ok, config.communicator, [{:failed, q, :not_connected}]}

        fuse_blown?(state) ->
          {:ok, config.communicator, [{:failed, q, :blown_fuse}]}

        true ->
          Communicator.send(config.communicator, q)
      end

    _ =
      Logger.info(fn ->
        event_time_iso =
          q.event_time
          |> DateTime.from_unix!(:native)
          |> DateTime.truncate(:second)
          |> DateTime.to_iso8601()

        "Query - alias=#{config.alias} comm=#{Communicator.name(config.communicator)} type=#{
          q.type
        } q_id=#{q.id} v_id=#{q.vehicle_id} approach=#{q.approach} event_time=#{event_time_iso} lat=#{
          q.vehicle_latitude
        } lon=#{q.vehicle_longitude}"
      end)

    config = %{config | communicator: communicator}
    state = %{state | config: config}
    state = Enum.reduce(results, state, &handle_results/2)
    state_no_reply(state)
  end

  @impl GenServer
  def handle_call(:flush, _from, state) do
    {:message_queue_len, len} = Process.info(self(), :message_queue_len)
    {:reply, {:ok, len}, state}
  end

  @impl GenServer
  def handle_continue(:connect, %{config: config} = state) do
    state =
      case Communicator.connect(config.communicator) do
        {:ok, communicator, results} ->
          config = %{config | communicator: communicator}
          state = %{state | config: config, connected?: true}
          state = Enum.reduce(results, state, &handle_results/2)

          _ =
            Logger.info(fn ->
              "started Intersection alias=#{config.alias} comm=#{Communicator.name(communicator)}"
            end)

          state

        {:error, _} = e ->
          state = %{state | connect_failure_count: state.connect_failure_count + 1}

          _ =
            Logger.warn(fn ->
              "unable to start Intersection alias=#{config.alias} comm=#{
                Communicator.name(config.communicator)
              } count=#{state.connect_failure_count} error=#{inspect(e)}"
            end)

          state
      end

    state_no_reply(state)
  end

  @impl GenServer
  def handle_info(:timeout, %{config: config} = state) do
    time = state.time_fn.()

    _ =
      if time >= config.warning_not_before_time and time <= config.warning_not_after_time do
        Logger.warn(fn ->
          "Intersection has not received a message in #{config.warning_timeout_ms}ms - alias=#{
            config.alias
          }"
        end)
      end

    {:noreply, state, config.warning_timeout_ms}
  end

  def handle_info(:reconnect, state) do
    {:noreply, state, {:continue, :connect}}
  end

  def handle_info(message, %{config: config} = state) do
    case Communicator.stream(config.communicator, message) do
      {:ok, communicator, results} ->
        config = %{config | communicator: communicator}
        state = %{state | config: config}
        state = Enum.reduce(results, state, &handle_results/2)
        state_no_reply(state)

      :unknown ->
        _ =
          Logger.warn(fn ->
            "unexpected message alias=#{config.alias} comm=#{
              Communicator.name(config.communicator)
            } message=#{inspect(message)}"
          end)

        {:noreply, state, config.warning_timeout_ms}
    end
  end

  @spec handle_results(Communicator.result(), t()) :: t()
  def handle_results({:sent, q}, %{config: config} = state) do
    _ =
      Logger.info(fn ->
        event_time_iso =
          q.event_time
          |> DateTime.from_unix!(:native)
          |> DateTime.truncate(:second)
          |> DateTime.to_iso8601()

        processing_time = Query.processing_time(q, :microsecond)

        "Response - alias=#{config.alias} comm=#{Communicator.name(config.communicator)} type=#{
          q.type
        } q_id=#{q.id} v_id=#{q.vehicle_id} approach=#{q.approach} event_time=#{event_time_iso} processing_time_us=#{
          processing_time
        } lat=#{q.vehicle_latitude} lon=#{q.vehicle_longitude}"
      end)

    %{state | connect_failure_count: 0}
  end

  def handle_results({:failed, q, error}, %{config: config} = state) do
    if error not in [:closed, :not_connected, :blown_fuse] do
      # not_connected/closed is handled by re-connecting, and a blown fuse doesn't need to
      # melt twice.
      fuse_melt(state)
    end

    _ =
      Logger.info(fn ->
        event_time_iso =
          q.event_time
          |> DateTime.from_unix!(:native)
          |> DateTime.truncate(:second)
          |> DateTime.to_iso8601()

        processing_time = Query.processing_time(q, :microsecond)

        "Failure - alias=#{config.alias} comm=#{Communicator.name(config.communicator)} type=#{
          q.type
        } q_id=#{q.id} v_id=#{q.vehicle_id} approach=#{q.approach} event_time=#{event_time_iso} processing_time_us=#{
          processing_time
        } error=#{inspect(error)} lat=#{q.vehicle_latitude} lon=#{q.vehicle_longitude}"
      end)

    state
  end

  def handle_results({:error, error}, %{config: config} = state) do
    state = %{state | connected?: false, connect_failure_count: state.connect_failure_count + 1}

    _ =
      Logger.warn(fn ->
        "Lost connection - alias=#{config.alias} comm=#{Communicator.name(config.communicator)} count=#{
          state.connect_failure_count
        } error=#{inspect(error)}"
      end)

    state
  end

  def reconnect_after(state) do
    Process.send_after(self(), :reconnect, retry_after(state.connect_failure_count))
    state
  end

  defp retry_after(connect_failure_count) do
    after_time = trunc(500 * :math.pow(2, connect_failure_count))
    min(after_time, @max_reconnect_timeout)
  end

  defp state_no_reply(%{config: %{warning_timeout_ms: timeout}, connected?: true} = state) do
    {:noreply, state, timeout}
  end

  defp state_no_reply(%{connect_failure_count: 1} = state) do
    {:noreply, state, {:continue, :connect}}
  end

  defp state_no_reply(state) do
    state = reconnect_after(state)
    {:noreply, state}
  end

  defp default_fuse_options do
    Application.get_env(:tablespoon, :fuse_options)
  end

  defp install_fuse(state, options) do
    :ok = :fuse.install(state.fuse_name, options)
  end

  defp fuse_blown?(state) do
    :fuse.ask(state.fuse_name, :sync) == :blown
  end

  defp fuse_melt(state) do
    :ok = :fuse.melt(state.fuse_name)
  end
end
