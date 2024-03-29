defmodule Tablespoon.IntersectionTest do
  @moduledoc false
  use ExUnit.Case
  alias Tablespoon.Communicator.Modem
  alias Tablespoon.{Intersection, Intersection.Config, Query}
  alias Tablespoon.Transport.FakeModem
  import ExUnit.CaptureLog

  @moduletag :capture_log

  @alias "test_alias"
  @config %Config{
    alias: @alias,
    warning_timeout_ms: 60_000,
    warning_not_before_time: {7, 0, 0},
    warning_not_after_time: {23, 0, 0},
    communicator: Modem.new(FakeModem.new()),
    log_termination?: false
  }

  doctest Intersection

  setup do
    start_supervised!(Tablespoon.Intersection.Duplicates)
    {:ok, _pid} = Intersection.start_link(config: @config)
    :ok
  end

  describe "send_query/1" do
    setup :log_level_info

    @tag capture_log: false
    test "logs the query" do
      query =
        Query.new(
          id: "test_query_id",
          type: :cancel,
          intersection_alias: @alias,
          approach: :south,
          vehicle_id: "vehicle_id",
          vehicle_latitude: -1.2,
          vehicle_longitude: 3.4,
          event_time: 0
        )

      log =
        capture_log(fn ->
          :ok = Intersection.send_query(query)
          :ok = Intersection.flush(@alias)
        end)

      assert log =~ "Query - alias=test_alias comm=Modem"
      assert log =~ "type=cancel"
      assert log =~ "v_id=vehicle_id"
      assert log =~ "approach=south"
      assert log =~ "event_time=1970-01-01T00:00:00Z"
      assert log =~ "lat=-1.2"
      assert log =~ "lon=3.4"
      assert log =~ "test_query_id"
    end

    @tag capture_log: false
    test "logs the response" do
      query =
        Query.new(
          id: "test_response_id",
          type: :request,
          intersection_alias: @alias,
          approach: :north,
          vehicle_id: "vehicle_id",
          vehicle_latitude: -1.2,
          vehicle_longitude: 3.4,
          event_time: 0
        )

      log =
        capture_log(fn ->
          :ok = Intersection.send_query(query)
          Process.sleep(10)
          :ok = Intersection.flush(@alias)
        end)

      assert log =~ "Response - alias=test_alias comm=Modem"
      assert log =~ "type=request"
      assert log =~ "v_id=vehicle_id"
      assert log =~ "approach=north"
      assert log =~ "event_time=1970-01-01T00:00:00Z"
      assert log =~ "processing_time_us="
      assert log =~ "lat=-1.2"
      assert log =~ "lon=3.4"
      assert log =~ "test_response_id"
    end

    @tag capture_log: false
    test "logs a warning if there's an invalid alias" do
      query =
        Query.new(
          id: "test_invalid_alias",
          type: :request,
          intersection_alias: @alias <> "_invalid",
          approach: :north,
          vehicle_id: "vehicle_id",
          event_time: 0
        )

      log =
        capture_log(fn ->
          :ok = Intersection.send_query(query)
        end)

      assert log =~ "Query received for invalid Intersection alias=test_alias_invalid"
    end

    @tag capture_log: false
    test "logs a message if the server is terminated before the response comes back" do
      config = %{
        @config
        | alias: "test_supervisor_stop",
          communicator: Modem.new(FakeModem.new(delay_range: 10_000..10_000)),
          log_termination?: true
      }

      # run under a supervisor to ensure we're trapping exits. If we call
      # GenServer.stop/1 directly, the terminate/2 callback is always called.
      {supervisor_pid, _} =
        with_log(fn ->
          {:ok, supervisor_pid} =
            Supervisor.start_link(
              [
                {Intersection, config: config}
              ],
              strategy: :one_for_one
            )

          supervisor_pid
        end)

      query =
        Query.new(
          id: "test_response_during_close",
          type: :request,
          intersection_alias: config.alias,
          approach: :north,
          vehicle_id: "vehicle_id",
          vehicle_latitude: -1.2,
          vehicle_longitude: 3.4,
          event_time: 0
        )

      log =
        capture_log(fn ->
          :ok = Intersection.send_query(query)
          :ok = Supervisor.stop(supervisor_pid)
        end)

      assert log =~ "Terminating alias=#{config.alias}"
      assert log =~ "Failure - alias=#{config.alias}"
    end
  end

  describe "handle_continue(:connect)" do
    setup :log_level_info

    @tag capture_log: false
    test "if we fail to connect, will fail future requests" do
      config = %{
        @config
        | alias: "test_connect_failure",
          communicator: Modem.new(FakeModem.new(connect_error_rate: 100))
      }

      {:ok, state, _} = Intersection.init(config: config)

      log =
        capture_log(fn ->
          {:noreply, _state, _} = Intersection.handle_continue(:connect, state)
        end)

      assert log =~ "unable to start"

      query =
        Query.new(
          id: "test_response_id",
          type: :request,
          intersection_alias: @alias,
          approach: :north,
          vehicle_id: "vehicle_id",
          event_time: 0
        )

      log =
        capture_log(fn ->
          {:noreply, state} = Intersection.handle_cast({:query, query}, state)
          refute state.connected?
          assert state.reconnect_ref
        end)

      assert log =~ "error=:not_connected"
    end

    @tag capture_log: false
    test "if we fail to connect multiple times, do not immediately reconnect" do
      config = %{
        @config
        | alias: "test_multi_connect_failure",
          communicator: Modem.new(FakeModem.new(connect_error_rate: 100))
      }

      {:ok, state, _} = Intersection.init(config: config)

      capture_log(fn ->
        assert {:noreply, state, {:continue, :connect}} =
                 Intersection.handle_continue(:connect, state)

        assert {:noreply, _state} = Intersection.handle_continue(:connect, state)
      end)
    end

    test "if we're already connected, do not reconnect" do
      {:ok, state, {:continue, :connect}} = Intersection.init(config: @config)
      assert {:noreply, state, timeout} = Intersection.handle_continue(:connect, state)
      assert is_integer(timeout)
      old_config = state.config
      assert {:noreply, state, timeout} = Intersection.handle_continue(:connect, state)
      assert state.config == old_config
      assert is_integer(timeout)
    end
  end

  describe "handle_info(:timeout)" do
    setup do
      {:ok, state, _timeout} = Intersection.init(config: @config)
      {:ok, state: state}
    end

    @tag capture_log: false
    test "logs a warning during the timeframe", %{state: state} do
      state = %{state | time_fn: fn -> {12, 0, 0} end}

      log =
        capture_log(fn ->
          assert Intersection.handle_info(:timeout, state) ==
                   {:noreply, state, state.config.warning_timeout_ms}
        end)

      assert log =~ "not received"
    end

    @tag capture_log: false
    test "does not log a warning before the timeframe", %{state: state} do
      state = %{state | time_fn: fn -> {6, 0, 0} end}

      log =
        capture_log(fn ->
          Intersection.handle_info(:timeout, state)
        end)

      assert log == ""
    end

    @tag capture_log: false
    test "does not log a warning after the timeframe", %{state: state} do
      state = %{state | time_fn: fn -> {23, 50, 0} end}

      log =
        capture_log(fn ->
          Intersection.handle_info(:timeout, state)
        end)

      assert log == ""
    end
  end

  describe "handle_info(:reconnect)" do
    @tag :capture_log
    test "does not change the current connection status" do
      {:ok, state, _} = Intersection.init(config: @config)
      refute state.connected?

      {:noreply, state, {:continue, :connect}} = Intersection.handle_info(:reconnect, state)
      refute state.connected?

      {:noreply, state, _} = Intersection.handle_continue(:connect, state)
      assert state.connected?

      {:noreply, state, {:continue, :connect}} = Intersection.handle_info(:reconnect, state)
      assert state.connected?
    end
  end

  describe "handle_results/2" do
    setup :log_level_info

    setup do
      {:ok, state, _} = Intersection.init(config: @config)
      {:ok, %{state: state}}
    end

    @tag capture_log: false
    test "logs a failure response", %{state: state} do
      query =
        Query.new(
          id: "test_failure_id",
          type: :request,
          intersection_alias: @alias,
          approach: :north,
          vehicle_id: "vehicle_id",
          vehicle_latitude: -1.2,
          vehicle_longitude: 3.4,
          event_time: 0
        )

      log =
        capture_log(fn ->
          Intersection.handle_results({:failed, query, :test_error}, state)
        end)

      assert log =~ "Failure - alias=test_alias comm=Modem"
      assert log =~ "type=request"
      assert log =~ "v_id=vehicle_id"
      assert log =~ "approach=north"
      assert log =~ "event_time=1970-01-01T00:00:00Z"
      assert log =~ "processing_time_us="
      assert log =~ "lat=-1.2"
      assert log =~ "lon=3.4"
      assert log =~ "test_failure_id"
      assert log =~ "error=:test_error"
    end
  end

  describe "fuse" do
    setup :log_level_info

    @tag capture_log: false
    test "a blown fuse results in a :blown_fuse error" do
      intersection_alias = "test_blown_fuse"

      config = %{
        @config
        | alias: intersection_alias,
          communicator: Modem.new(FakeModem.new(send_error_rate: 100))
      }

      # first query fails normally
      # second query fails and melts the fuse
      # third query fails due to the blown fuse
      queries =
        for id <- 1..3 do
          Query.new(
            id: id,
            type: :request,
            intersection_alias: intersection_alias,
            approach: :north,
            vehicle_id: "vehicle_id",
            event_time: 0
          )
        end

      log =
        capture_log(fn ->
          {:ok, pid} =
            Intersection.start_link(
              config: config,
              fuse_options: {{:standard, 1, 300_000}, {:reset, 300_000}}
            )

          for query <- queries do
            :ok = Intersection.send_query(query)
          end

          :ok = Intersection.flush(intersection_alias)
          GenServer.stop(pid)
        end)

      assert log =~ "error=:blown_fuse" or log =~ "error=:not_connected"
    end
  end

  describe "retry_after/1" do
    test "does not exceed one hour" do
      for count <- 0..20 do
        assert Intersection.retry_after(count) <= 3_600_000, "retry took too long with #{count}"
      end
    end
  end

  describe "local_time/0" do
    test "returns {hour, minute, second} tuple in the given timezone" do
      time_zone = "America/Los_Angeles"
      now = DateTime.now!(time_zone)
      {hour, minute, second} = Intersection.local_time(time_zone)
      assert Time.diff(Time.new!(hour, minute, second), now) <= 1
    end
  end

  defp log_level_info(_) do
    log_level = Logger.level()

    on_exit(fn ->
      Logger.configure(level: log_level)
    end)

    Logger.configure(level: :info)
    :ok
  end
end
