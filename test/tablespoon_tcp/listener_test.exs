defmodule TablespoonTcp.ListenerTest do
  @moduledoc false
  use ExUnit.Case, async: true
  import TablespoonTcp.Listener

  describe "start_link/1" do
    test "starts a TCP listener on the given port" do
      port_number = random_port_number()
      opts = [server: true, port: port_number]
      assert {:ok, _pid} = start_link(opts)
      assert {:ok, port} = :gen_tcp.connect('127.0.0.1', port_number, active: false)
      assert :ok = :gen_tcp.send(port, "T")
      # not {:error, :closed}
      assert {:error, :timeout} = :gen_tcp.recv(port, 0, 100)
    end
  end

  describe "children/1" do
    test "with no server, no children are started" do
      assert children([]) == []
      assert children(server: false) == []
    end
  end

  defp random_port_number do
    {:ok, port} = :gen_tcp.listen(0, [])
    {:ok, port_number} = :inet.port(port)
    :ok = :gen_tcp.close(port)
    port_number
  end
end
