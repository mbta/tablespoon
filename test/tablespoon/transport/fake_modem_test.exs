defmodule Tablespoon.Transport.FakeModemTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias Tablespoon.Transport.FakeModem

  @packet "AT*RELAYOUT5=0\r\n"

  describe "send/2" do
    test "sends a data reply" do
      t = FakeModem.new()
      {:ok, t} = FakeModem.connect(t)
      receive_connect_messages(t)
      assert {:ok, t} = FakeModem.send(t, @packet)
      receive_echo(t)
      assert_receive x
      assert {:ok, _, [{:data, _}]} = FakeModem.stream(t, x)
    end

    test "when not connected, returns an error" do
      t = FakeModem.new()
      assert {:error, :not_connected} = FakeModem.send(t, @packet)
    end

    test "when send_error_rate is 100, returns an error" do
      t = FakeModem.new(send_error_rate: 100)
      {:ok, t} = FakeModem.connect(t)
      receive_connect_messages(t)
      assert {:error, :trigger_failed} = FakeModem.send(t, @packet)
      refute_receive _
    end

    test "when response_error_rate is 100, replies with an error" do
      t = FakeModem.new(response_error_rate: 100)
      {:ok, t} = FakeModem.connect(t)
      receive_connect_messages(t)
      assert {:ok, t} = FakeModem.send(t, @packet)
      receive_echo(t)
      assert_receive x
      assert {:ok, _, [{:data, "ERROR"}]} = FakeModem.stream(t, x)
    end

    test "when delay_range is sent, waits to send the reply" do
      t = FakeModem.new(delay_range: 5..10)
      {:ok, t} = FakeModem.connect(t)
      assert {:ok, t} = FakeModem.send(t, @packet)
      refute_received _
      # wait...
      receive_echo(t)
      assert_receive x
      assert {:ok, _, [{:data, _}]} = FakeModem.stream(t, x)
    end
  end

  describe "stream/2" do
    test "when disconnect_rate is 100, always disconnects rather than sending a data response" do
      t = FakeModem.new(disconnect_rate: 100)
      {:ok, t} = FakeModem.connect(t)
      message = {t.ref, {:data, @packet}}
      assert {:ok, t, [:closed]} = FakeModem.stream(t, message)
      refute t.ref
    end
  end

  defp receive_connect_messages(t) do
    # we get some initial messages on calling connect/1
    ref = t.ref
    assert_receive {^ref, {:data, "OK"}}
    assert_receive {^ref, {:data, "\r"}}
    assert_receive {^ref, {:data, "\n"}}
  end

  defp receive_echo(t) do
    # we get an echo of the request we sent
    ref = t.ref
    assert_receive {^ref, {:data, "AT*RELAYOUT" <> _}}
    assert_receive {^ref, {:data, "\r"}}
    assert_receive {^ref, {:data, "\n"}}
  end
end
