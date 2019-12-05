defmodule Tablespoon.PropertyHelpers do
  @moduledoc "Helper functions for property tests"
  use ExUnitProperties

  @doc "Randomly modify a given packet"
  def modified_packet(packet, gen_replacement \\ StreamData.binary(min_length: 0, max_length: 3))
      when is_binary(packet) do
    sized(fn size ->
      packet_modifications(packet, size, gen_replacement)
    end)
  end

  defp packet_modifications(packet, 0, _) do
    constant(packet)
  end

  defp packet_modifications("", _, _) do
    constant("")
  end

  defp packet_modifications(packet, size, gen_replacement) do
    gen all(
          index <- integer(0..(byte_size(packet) - 1)),
          <<head::binary-size(index), _::binary-1, tail::binary>> = packet,
          head <- packet_modifications(head, size - 1, gen_replacement),
          tail <-
            packet_modifications(tail, size - 1, gen_replacement),
          replacement <- gen_replacement
        ) do
      head <> replacement <> tail
    end
  end
end
