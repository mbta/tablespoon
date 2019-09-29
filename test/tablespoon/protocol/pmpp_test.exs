defmodule Tablespoon.Protocol.PMPPTest do
  @moduledoc false
  use ExUnit.Case, async: true
  use ExUnitProperties
  alias Tablespoon.Protocol.PMPP

  describe "encode/decode" do
    property "encode/decode are parallel operations" do
      check all(
              message <- gen_message(),
              extra <- StreamData.binary()
            ) do
        encoded = PMPP.encode(message)
        binary = IO.iodata_to_binary([encoded, extra])
        assert {:ok, ^message, ^extra} = PMPP.decode(binary)
      end
    end
  end

  @message %PMPP{
    address: 5,
    control: :information_poll,
    body: "x"
  }
  @encoded <<0x7E, 0x05, 0x13, 0xC1, "x", 0xC5, 0xD4, 0x7E>>

  describe "encode/1" do
    test "properly encodes a message" do
      assert IO.iodata_to_binary(PMPP.encode(@message)) == @encoded
    end

    test "properly encodes a message with an iodata body" do
      message = %{@message | body: [@message.body]}
      assert IO.iodata_to_binary(PMPP.encode(message)) == @encoded
    end

    test "properly encodes a message from the old software" do
      message = %PMPP{
        address: 5,
        control: :information_poll,
        body:
          <<0x30, 0x47, 0x02, 0x01, 0x00, 0x04, 0x0D, 0x61, 0x64, 0x6D, 0x69, 0x6E, 0x69, 0x73,
            0x74, 0x72, 0x61, 0x74, 0x6F, 0x72, 0xA3, 0x33, 0x02, 0x01, 0x00, 0x02, 0x01, 0x00,
            0x02, 0x01, 0x00, 0x30, 0x28, 0x30, 0x26, 0x06, 0x0D, 0x2B, 0x06, 0x01, 0x04, 0x01,
            0x89, 0x36, 0x04, 0x02, 0x0B, 0x02, 0x05, 0x00, 0x04, 0x15, 0xF1, 0x20, 0x20, 0x20,
            0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x33, 0x38, 0x32, 0x35,
            0x02, 0x00, 0x02>>
      }

      expected =
        <<0x7E, 0x05, 0x13, 0xC1, 0x30, 0x47, 0x02, 0x01, 0x00, 0x04, 0x0D, 0x61, 0x64, 0x6D,
          0x69, 0x6E, 0x69, 0x73, 0x74, 0x72, 0x61, 0x74, 0x6F, 0x72, 0xA3, 0x33, 0x02, 0x01,
          0x00, 0x02, 0x01, 0x00, 0x02, 0x01, 0x00, 0x30, 0x28, 0x30, 0x26, 0x06, 0x0D, 0x2B,
          0x06, 0x01, 0x04, 0x01, 0x89, 0x36, 0x04, 0x02, 0x0B, 0x02, 0x05, 0x00, 0x04, 0x15,
          0xF1, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20,
          0x33, 0x38, 0x32, 0x35, 0x02, 0x00, 0x02, 0x09, 0x09, 0x7E>>

      assert IO.iodata_to_binary(PMPP.encode(message)) == expected
    end
  end

  describe "decode/1" do
    test "properly decodes a message" do
      assert PMPP.decode(@encoded) == {:ok, @message, ""}
    end

    test "fails on a too small message" do
      assert PMPP.decode(<<0x7E, 0x7E, "extra">>) == {:error, :invalid, "extra"}
      assert PMPP.decode(<<0x7E, 0x00, 0x7E, "extra">>) == {:error, :invalid, "extra"}
    end

    test "modifying an internal byte fails to decode with a :crc_failed error" do
      replaced = :binary.replace(@encoded, "x", "y")
      assert PMPP.decode(replaced <> "extra") == {:error, :crc_failed, "extra"}
    end

    test "messages which are not a full frame returns a :too_short error" do
      short = :binary.part(@encoded, 0, 3)
      assert PMPP.decode(short) == {:error, :too_short, short}
    end

    property "does not crash on any input" do
      check all(data <- gen_body()) do
        PMPP.decode(data)
      end
    end
  end

  def gen_message do
    address = StreamData.integer(0..255)

    control =
      [:poll, :information_poll, :information_poll]
      |> Enum.map(&constant/1)
      |> one_of()

    gen all(
          address <- address,
          control <- control,
          body <- gen_body()
        ) do
      %PMPP{
        address: address,
        control: control,
        body: body
      }
    end
  end

  def gen_body do
    # ensure we include bytes which need to be escaped
    [
      {1, constant(0x7E)},
      {1, constant(0x7D)},
      {1, constant(0x5E)},
      {1, constant(0x5D)},
      {10, binary()}
    ]
    |> frequency()
    |> list_of()
    |> map(&IO.iodata_to_binary/1)
  end
end
