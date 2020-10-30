defmodule Tablespoon.Protocol.ASN1 do
  @moduledoc """
  Simple ASN.1 parser to support NTCIP1211.

  We use the built-in `:snmp_pdus` to send messages, but we receiving
  otherwise invalid packets and need to parse them ourselves.
  """

  @type error :: term

  @spec decode(binary) :: {:ok, term, binary} | {:error, error}
  def decode(<<5::integer-3, tag::integer-5, binary::binary>>) do
    # tagged SEQUENCE
    with {:ok, binary, rest} <- decode_octet_string(binary),
         {:ok, sequence} <- decode_sequence(binary) do
      {:ok, {:tag, tag, sequence}, rest}
    end
  end

  def decode(<<1::integer-8, 1, boolean::binary-1, rest::binary>>) do
    # BOOLEAN
    {:ok, boolean != <<0>>, rest}
  end

  def decode(<<2::integer-8, binary::binary>>) do
    # INTEGER
    with {:ok, length, binary} <- decode_ber_length(binary),
         integer_length = length * 8,
         <<value::signed-big-integer-size(integer_length), rest::binary>> <- binary do
      {:ok, value, rest}
    else
      <<_::binary>> -> {:error, :wrong_length}
      e -> e
    end
  end

  def decode(<<3::integer-8, binary::binary>>) do
    # BITSTRING (treat like OCTET STRING)
    decode_octet_string(binary)
  end

  def decode(<<4::integer-8, binary::binary>>) do
    # OCTET STRING
    decode_octet_string(binary)
  end

  def decode(<<6::integer-8, binary::binary>>) do
    # OBJECT_IDENTIFIER
    with {:ok, binary, rest} <- decode_octet_string(binary) do
      id = decode_object_identifier(binary)
      {:ok, id, rest}
    end
  end

  def decode(<<_::bits-3, 16::integer-5, binary::binary>>) do
    # SEQUENCE
    with {:ok, binary, rest} <- decode_octet_string(binary),
         {:ok, sequence} <- decode_sequence(binary) do
      {:ok, sequence, rest}
    end
  end

  def decode(<<prefix::integer-8, _::binary>>) do
    {:error, {:unknown, prefix}}
  end

  def decode("") do
    {:error, :wrong_length}
  end

  @doc """
  Decode a BER length along with the rest of the binary.

  There are two cases:
  - length < 128: high bit is 0, length is the 7 low bits
  - length >= 128: high bit is 1, length of length octets is the low 7 bits
  """
  @spec decode_ber_length(binary) :: {:ok, non_neg_integer, binary} | {:error, :wrong_length}
  def decode_ber_length(<<1::integer-1, length_bytes::big-integer-7, rest::binary>>) do
    length_bits = length_bytes * 8

    case rest do
      <<length::unsigned-big-integer-size(length_bits), rest::binary>> ->
        {:ok, length, rest}

      _ ->
        {:error, :wrong_length}
    end
  end

  def decode_ber_length(<<length::unsigned-integer-big-8, rest::binary>>) do
    {:ok, length, rest}
  end

  def decode_ber_length(_) do
    {:error, :wrong_length}
  end

  @spec decode_sequence(binary) :: {:ok, [term]} | {:error, error}
  defp decode_sequence(binary, acc \\ [])

  defp decode_sequence("", acc) do
    {:ok, :lists.reverse(acc)}
  end

  defp decode_sequence(binary, acc) do
    case decode(binary) do
      {:ok, value, rest} ->
        decode_sequence(rest, [value | acc])

      {:error, _} = error ->
        error
    end
  end

  def decode_octet_string(<<0, rest::binary>>) do
    {:ok, "", rest}
  end

  def decode_octet_string(binary) do
    with {:ok, length, binary} <- decode_ber_length(binary),
         <<binary::binary-size(length), rest::binary>> <- binary do
      {:ok, binary, rest}
    else
      <<_::binary>> ->
        {:error, :wrong_length}

      {:error, _} = e ->
        e
    end
  end

  defp decode_object_identifier(binary, acc \\ [], counter \\ 0)

  defp decode_object_identifier("", acc, _) do
    :lists.reverse(acc)
  end

  defp decode_object_identifier(
         <<first_byte::unsigned-integer-8, rest::binary>>,
         [],
         _counter
       ) do
    first = div(first_byte, 40)
    second = rem(first_byte, 40)
    decode_object_identifier(rest, [second, first])
  end

  defp decode_object_identifier(
         <<1::integer-1, value::unsigned-big-integer-7, rest::binary>>,
         acc,
         counter
       ) do
    counter = 128 * (counter + value)

    decode_object_identifier(rest, acc, counter)
  end

  defp decode_object_identifier(
         <<0::integer-1, value::unsigned-big-integer-7, rest::binary>>,
         acc,
         counter
       ) do
    counter = counter + value

    decode_object_identifier(rest, [counter | acc])
  end
end
