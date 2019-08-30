defmodule Tablespoon.Transport.FakeBtdTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias Tablespoon.Protocol.NTCIP1211Extended, as: NTCIP
  alias Tablespoon.Protocol.PMPP
  alias Tablespoon.Transport.FakeBtd

  ntcip_message = %NTCIP.PriorityRequest{
    id: 1,
    vehicle_id: "1",
    vehicle_class: 2,
    vehicle_class_level: 0,
    strategy: 3,
    time_of_service_desired: 0,
    time_of_estimated_departure: 0,
    intersection_id: 40
  }

  ntcip =
    NTCIP.encode(%NTCIP{
      group: "group",
      pdu_type: :response,
      request_id: 0,
      message: ntcip_message
    })

  @packet PMPP.encode(%PMPP{address: 1, control: :information_poll, body: ntcip})

  describe "send/2" do
    test "sends a data reply" do
      t = FakeBtd.new()
      {:ok, t} = FakeBtd.connect(t)
      assert {:ok, t} = FakeBtd.send(t, @packet)
      assert_receive x
      assert {:ok, _, [{:data, _}]} = FakeBtd.stream(t, x)
    end

    test "when not connected, returns an error" do
      t = FakeBtd.new()
      assert {:error, :not_connected} = FakeBtd.send(t, @packet)
    end

    test "when drop_rate is 100, never sends a message" do
      t = FakeBtd.new(drop_rate: 100)
      {:ok, t} = FakeBtd.connect(t)
      assert {:ok, _} = FakeBtd.send(t, @packet)
      refute_receive _
    end

    test "when send_error_rate is 100, returns an error" do
      t = FakeBtd.new(send_error_rate: 100)
      {:ok, t} = FakeBtd.connect(t)
      assert {:error, :trigger_failed} = FakeBtd.send(t, @packet)
      refute_receive _
    end

    test "when delay_range is sent, waits to send the reply" do
      t = FakeBtd.new(delay_range: 5..10)
      {:ok, t} = FakeBtd.connect(t)
      assert {:ok, t} = FakeBtd.send(t, @packet)
      refute_received _
      # wait...
      assert_receive x
      assert {:ok, _, [{:data, _}]} = FakeBtd.stream(t, x)
    end
  end

  describe "stream/2" do
    test "when disconnect_rate is 100, always disconnects rather than sending a data response" do
      t = FakeBtd.new(disconnect_rate: 100)
      {:ok, t} = FakeBtd.connect(t)
      message = {t.ref, {:data, @packet}}
      assert {:ok, t, [:closed]} = FakeBtd.stream(t, message)
      refute t.ref
    end
  end
end
