defmodule Tablespoon.Protocol.LineTest do
  @moduledoc false
  use ExUnit.Case, async: true
  use ExUnitProperties
  import Tablespoon.Protocol.Line

  describe "encode/decode" do
    property "returns the same binary" do
      check all contents <- contents() do
        assert decode(IO.iodata_to_binary(encode(contents))) == {:ok, contents, ""}
      end
    end
  end

  describe "decode" do
    property "handles any number of extra carriage returns or extra data" do
      check all contents <- contents(),
                end_of_line <- end_of_line(),
                extra <- StreamData.list_of(StreamData.one_of([contents(), end_of_line()])) do
        assert decode(IO.iodata_to_binary([contents, end_of_line, extra])) ==
                 {:ok, contents, IO.iodata_to_binary(extra)}
      end
    end

    property "returns {:error, :too_short} without a newline" do
      check all contents <- contents() do
        assert decode(contents) == {:error, :too_short}
      end
    end
  end

  def contents do
    StreamData.string(?\s..?Z)
  end

  def end_of_line do
    [?\r]
    |> StreamData.string()
    |> StreamData.map(&(&1 <> "\n"))
  end
end
