defmodule Tablespoon.Protocol.PMPPTest do
  @moduledoc false
  use ExUnit.Case, async: true
  use ExUnitProperties
  alias Tablespoon.Protocol.PMPP

  describe "encode/decode" do
    property "encode/decode are parallel operations" do
      check all message <- gen_message(),
                extra <- StreamData.binary() do
        encoded = PMPP.encode(message)
        assert {:ok, ^message, ^extra} = PMPP.decode(encoded <> extra)
      end
    end
  end

  @message %PMPP{
    address: 5,
    control: :information_poll,
    body: "x"
  }
  @encoded <<0x7E, 0x05, 0x13, "x", 0xBF, 0x47, 0x7E>>

  describe "encode/1" do
    test "properly encodes a message" do
      assert PMPP.encode(@message) == @encoded
    end

    test "properly encodes a message from the old software" do
      message = %PMPP{
        address: 5,
        control: :information_poll,
        body:
          <<0xC1, 0x30, 0x47, 0x02, 0x01, 0x00, 0x04, 0x0D, 0x61, 0x64, 0x6D, 0x69, 0x6E, 0x69,
            0x73, 0x74, 0x72, 0x61, 0x74, 0x6F, 0x72, 0xA3, 0x33, 0x02, 0x01, 0x00, 0x02, 0x01,
            0x00, 0x02, 0x01, 0x00, 0x30, 0x28, 0x30, 0x26, 0x06, 0x0D, 0x2B, 0x06, 0x01, 0x04,
            0x01, 0x89, 0x36, 0x04, 0x02, 0x0B, 0x02, 0x05, 0x00, 0x04, 0x15, 0xF1, 0x20, 0x20,
            0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x33, 0x38, 0x32,
            0x35, 0x02, 0x00, 0x02>>
      }

      expected =
        <<0x7E, 0x05, 0x13, 0xC1, 0x30, 0x47, 0x02, 0x01, 0x00, 0x04, 0x0D, 0x61, 0x64, 0x6D,
          0x69, 0x6E, 0x69, 0x73, 0x74, 0x72, 0x61, 0x74, 0x6F, 0x72, 0xA3, 0x33, 0x02, 0x01,
          0x00, 0x02, 0x01, 0x00, 0x02, 0x01, 0x00, 0x30, 0x28, 0x30, 0x26, 0x06, 0x0D, 0x2B,
          0x06, 0x01, 0x04, 0x01, 0x89, 0x36, 0x04, 0x02, 0x0B, 0x02, 0x05, 0x00, 0x04, 0x15,
          0xF1, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20,
          0x33, 0x38, 0x32, 0x35, 0x02, 0x00, 0x02, 0x09, 0x09, 0x7E>>

      assert PMPP.encode(message) == expected
    end
  end

  describe "decode/1" do
    test "properly decodes a message" do
      assert PMPP.decode(@encoded) == {:ok, @message, ""}
    end

    test "modifying an internal byte fails to decode with a :crc_failed error" do
      replaced = :binary.replace(@encoded, "x", "y")
      assert PMPP.decode(replaced <> "extra") == {:error, :crc_failed, "extra"}
    end

    test "messages which are not a full frame returns a :too_short error" do
      short = :binary.part(@encoded, 0, 3)
      assert PMPP.decode(short) == {:error, :too_short, short}
    end
  end

  def gen_message do
    address = StreamData.integer(0..255)

    control =
      [:poll, :information_poll, :information_poll]
      |> Enum.map(&StreamData.constant/1)
      |> StreamData.one_of()

    # ensure we include bytes which need to be escaped
    body =
      [
        {5, StreamData.binary()},
        {1, StreamData.constant(0x7E)},
        {1, StreamData.constant(0x7D)}
      ]
      |> StreamData.frequency()
      |> StreamData.list_of()
      |> StreamData.map(&IO.iodata_to_binary/1)

    StreamData.fixed_map(%{
      __struct__: StreamData.constant(PMPP),
      address: address,
      control: control,
      body: body
    })
  end
end
