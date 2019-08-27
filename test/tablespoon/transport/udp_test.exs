defmodule Tablespoon.Transport.UDPTest do
  @moduledoc false
  use ExUnit.Case, async: true
  alias Tablespoon.Transport.UDP

  @localhost "127.0.0.1"

  setup do
    {:ok, receiver} = :gen_udp.open(0, [:binary, {:active, true}])
    {:ok, receiver_port} = :inet.port(receiver)
    {:ok, receiver: receiver, receiver_port: receiver_port}
  end

  describe "send/1" do
    test "send a packet to the given host/port", %{
      receiver: receiver,
      receiver_port: receiver_port
    } do
      {:ok, udp} = UDP.connect(UDP.new(host: @localhost, port: receiver_port))
      test_packet = inspect(:erlang.unique_integer())

      assert {:ok, ^udp} = UDP.send(udp, test_packet)
      assert_receive {:udp, ^receiver, _, _, ^test_packet}
    end

    test "returns an error if we can't send to the port" do
      {:ok, udp} = UDP.connect(UDP.new(host: @localhost, port: 0))
      assert {:error, _} = UDP.send(udp, "packet")
    end
  end

  describe "stream/2" do
    test "receives a packet", %{receiver: receiver, receiver_port: receiver_port} do
      {:ok, udp} = UDP.connect(UDP.new(host: @localhost, port: receiver_port))
      test_packet = inspect(:erlang.unique_integer())

      assert {:ok, ^udp} = UDP.send(udp, "")
      assert_receive {:udp, ^receiver, host, port, _}
      :gen_udp.send(receiver, host, port, test_packet)

      receive do
        x ->
          assert {:ok, ^udp, [data: ^test_packet]} = UDP.stream(udp, x)
      end
    end

    test "ignores unknown messages" do
      udp = UDP.new(host: @localhost, port: 0)
      assert UDP.stream(udp, :other_message) == :unknown
    end
  end
end
