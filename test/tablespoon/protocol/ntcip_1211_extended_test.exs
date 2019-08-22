defmodule Tablespoon.Protocol.NTCIP1211ExtendedTest do
  use ExUnit.Case, async: true
  use ExUnitProperties
  alias Tablespoon.Protocol.NTCIP1211Extended, as: NTCIP

  describe "encode/decode" do
    property "returns the same value" do
      check all message <- gen_message() do
        <<encoded::binary>> = NTCIP.encode(message)
        {:ok, decoded} = NTCIP.decode(encoded)
        assert message == decoded
      end
    end
  end

  @sample_message %NTCIP{
    group: "administrator",
    pdu_type: :set,
    request_id: 0,
    message: %NTCIP.PriorityCancel{
      id: 241,
      vehicle_id: "3825",
      vehicle_class: 2,
      vehicle_class_level: 0,
      strategy: 2
    }
  }

  @encoded_sample <<0x30, 0x47, 0x02, 0x01, 0x00, 0x04, 0x0D, 0x61, 0x64, 0x6D, 0x69, 0x6E, 0x69,
                    0x73, 0x74, 0x72, 0x61, 0x74, 0x6F, 0x72, 0xA3, 0x33, 0x02, 0x01, 0x00, 0x02,
                    0x01, 0x00, 0x02, 0x01, 0x00, 0x30, 0x28, 0x30, 0x26, 0x06, 0x0D, 0x2B, 0x06,
                    0x01, 0x04, 0x01, 0x89, 0x36, 0x04, 0x02, 0x0B, 0x02, 0x05, 0x00, 0x04, 0x15,
                    0xF1, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20,
                    0x20, 0x33, 0x38, 0x32, 0x35, 0x02, 0x00, 0x02>>

  describe "encode/1" do
    test "encodes a message the same way the old software did" do
      assert NTCIP.encode(@sample_message) == @encoded_sample
    end
  end

  describe "decode/1" do
    test "decodes a message the same way the old software did" do
      assert NTCIP.decode(@encoded_sample) == {:ok, @sample_message}
    end

    test "fails if there's not enough data" do
      assert NTCIP.decode(:binary.part(@encoded_sample, 0, 20)) == {:error, :invalid}
    end
  end

  def gen_message do
    pdu_type =
      [:set, :response]
      |> Enum.map(&StreamData.constant/1)
      |> StreamData.one_of()

    StreamData.fixed_map(%{
      __struct__: StreamData.constant(NTCIP),
      group: StreamData.binary(),
      pdu_type: pdu_type,
      request_id: StreamData.integer(),
      message: StreamData.one_of([gen_priority_request(), gen_priority_cancel()])
    })
  end

  def gen_priority_request do
    StreamData.fixed_map(%{
      __struct__: StreamData.constant(NTCIP.PriorityRequest),
      id: priority_id(),
      vehicle_id: vehicle_id(),
      vehicle_class: vehicle_class(),
      vehicle_class_level: vehicle_class_level(),
      strategy: strategy(),
      time_of_service_desired: time(),
      time_of_estimated_departure: time(),
      intersection_id: intersection_id()
    })
  end

  def gen_priority_cancel do
    StreamData.fixed_map(%{
      __struct__: StreamData.constant(NTCIP.PriorityCancel),
      id: priority_id(),
      vehicle_id: vehicle_id(),
      vehicle_class: vehicle_class(),
      vehicle_class_level: vehicle_class_level(),
      strategy: strategy()
    })
  end

  def priority_id, do: StreamData.integer(1..255)

  def vehicle_id do
    base = StreamData.string(:ascii, max_length: 17)
    StreamData.map(base, &String.trim_leading(&1, " "))
  end

  def vehicle_class, do: StreamData.integer(1..10)
  def vehicle_class_level, do: StreamData.integer(1..10)
  def strategy, do: StreamData.integer(1..255)
  def time, do: StreamData.integer(1..65_535)
  def intersection_id, do: StreamData.integer(1..65_535)
end
