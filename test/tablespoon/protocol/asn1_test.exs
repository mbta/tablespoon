defmodule Tablespoon.Protocol.ASN1Test do
  use ExUnit.Case, async: true
  use ExUnitProperties
  import Tablespoon.PropertyHelpers
  import Tablespoon.Protocol.ASN1

  @encoded_sample <<0x30, 0x47, 0x02, 0x01, 0x00, 0x04, 0x0D, 0x61, 0x64, 0x6D, 0x69, 0x6E, 0x69,
                    0x73, 0x74, 0x72, 0x61, 0x74, 0x6F, 0x72, 0xA3, 0x33, 0x02, 0x01, 0x00, 0x02,
                    0x01, 0x00, 0x02, 0x01, 0x00, 0x30, 0x28, 0x30, 0x26, 0x06, 0x0D, 0x2B, 0x06,
                    0x01, 0x04, 0x01, 0x89, 0x36, 0x04, 0x02, 0x0B, 0x02, 0x05, 0x00, 0x04, 0x15,
                    0xF1, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20,
                    0x20, 0x33, 0x38, 0x32, 0x35, 0x02, 0x00, 0x02>>

  describe "decode/1" do
    test "the sample packet" do
      extra = "extra"

      expected =
        {:ok,
         [
           0,
           "administrator",
           {:tag, 3,
            [
              0,
              0,
              0,
              [
                [
                  [1, 3, 6, 1, 4, 1, 1206, 4, 2, 11, 2, 5, 0],
                  <<241, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 51, 56, 50, 53, 2, 0,
                    2>>
                ]
              ]
            ]}
         ], extra}

      actual = decode(@encoded_sample <> extra)
      assert actual == expected
    end

    property "does not crash when receiving invalid packets" do
      check all(packet <- modified_packet(@encoded_sample)) do
        case decode(packet) do
          {:ok, _, _} ->
            :ok

          {:error, _} ->
            :ok
        end
      end
    end
  end
end
