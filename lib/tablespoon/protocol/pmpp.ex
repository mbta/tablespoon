defmodule Tablespoon.Protocol.PMPP do
  @moduledoc """
  Implementation of the Point-MultiPoint Protocol (PMPP).

  PMPP is a framing protocol used to send packets between servers, or
  optionally to multi-cast to multiple servers.

  The frames look like:

  - Flag - one byte, 0x7E
  - Address - one byte integer, where values > 127 are multi-cast
  - Control - one byte, 0x33 for unnumbered poll, 0x13 for unnumbered information with poll, or 0x03 for information without poll
  - Body - any number of bytes
  - CRC - two bytes
  - Flag - one byte, 0x7E

  Any internal bytes in the body or CRC which are 0x7D48 or 0x7E are replaced:

  - 0x7D -> 0x7D 0x5D
  - 0x7E -> 0x7D 0x5E

  These notes are from reading the NTCIP 9001 documentation: https://www.ntcip.org/wp-content/uploads/2018/11/NTCIP9001v0406r.pdf
  """
  @enforce_keys [:address, :control, :body]
  defstruct @enforce_keys ++ [protocol: :snmp]

  use Bitwise

  @type t :: %__MODULE__{
          address: 0..255,
          control: :poll | :information_poll | :information,
          protocol: :snmp,
          body: iodata
        }
  @type error :: :unknown | :too_short | :crc_failed

  @flag <<0x7E>>
  @escape <<0x7D>>
  @escaped_flag <<0x7D, 0x5E>>
  @escaped_escape <<0x7D, 0x5D>>

  @doc "Encode a PMPP message to iodata"
  @spec encode(t) :: iodata
  def encode(%__MODULE__{} = pmpp) do
    contents_to_crc =
      IO.iodata_to_binary([
        <<pmpp.address::unsigned-integer-8>>,
        control_as_binary(pmpp.control),
        protocol_as_binary(pmpp.protocol),
        pmpp.body
      ])

    crc = checksum(contents_to_crc)
    [@flag, replace_flag(contents_to_crc), replace_flag(crc), @flag]
  end

  @doc "Decode a binary into a PMPP message and any extra data"
  @spec decode(binary) :: {:ok, t, binary} | {:error, error, binary}
  def decode(<<@flag, rest::binary>> = binary) do
    case :binary.split(rest, @flag) do
      [rest, extra] ->
        do_decode(rest, extra)

      [_] ->
        {:error, :too_short, binary}
    end
  end

  def decode(binary) when is_binary(binary) do
    {:error, :unknown, binary}
  end

  # must have at least 3 bytes for the address/control/protocokl identifier, plus two bytes for the CRC
  defp do_decode(rest, extra) when byte_size(rest) >= 5 do
    rest = unreplace_flag(rest)
    rest_size = byte_size(rest) - 2

    <<rest::binary-size(rest_size), crc::binary-2>> = rest

    if checksum(rest) == crc do
      <<address::unsigned-integer-8, control_binary::unsigned-integer-8,
        protocol_binary::unsigned-integer-8, body::binary>> = rest

      message = %__MODULE__{
        address: address,
        control: control_from_binary(control_binary),
        protocol: protocol_from_binary(protocol_binary),
        body: body
      }

      {:ok, message, extra}
    else
      {:error, :crc_failed, extra}
    end
  end

  defp do_decode(_rest, extra) do
    {:error, :invalid, extra}
  end

  for {control, value} <- [poll: 0x33, information_poll: 0x13, information: 0x03] do
    defp control_as_binary(unquote(control)), do: unquote(value)
    defp control_from_binary(unquote(value)), do: unquote(control)
  end

  defp protocol_as_binary(:snmp), do: 0xC1
  defp protocol_from_binary(0xC1), do: :snmp

  defp replace_flag(binary) do
    binary = :binary.replace(binary, @escape, @escaped_escape, [:global])
    :binary.replace(binary, @flag, @escaped_flag, [:global])
  end

  defp unreplace_flag(binary) do
    binary = :binary.replace(binary, @escaped_flag, @flag, [:global])
    :binary.replace(binary, @escaped_escape, @escape, [:global])
  end

  def checksum(bytes, fcs \\ 0xFFFF)

  def checksum("", fcs) do
    fcs = bxor(fcs, 0xFFFF)
    <<fcs::unsigned-little-integer-16>>
  end

  def checksum(<<byte::unsigned-integer-8, rest::binary>>, fcs) do
    index = bxor(fcs, byte) &&& 0xFF
    fcs = bxor(fcs >>> 8, fcstab(index))
    checksum(rest, fcs)
  end

  # for calculating the CRC/FCS, from https://www.ntcip.org/wp-content/uploads/2018/11/NTCIP9001v0406r.pdf
  for {value, index} <-
        Enum.with_index([
          0x0000,
          0x1189,
          0x2312,
          0x329B,
          0x4624,
          0x57AD,
          0x6536,
          0x74BF,
          0x8C48,
          0x9DC1,
          0xAF5A,
          0xBED3,
          0xCA6C,
          0xDBE5,
          0xE97E,
          0xF8F7,
          0x1081,
          0x0108,
          0x3393,
          0x221A,
          0x56A5,
          0x472C,
          0x75B7,
          0x643E,
          0x9CC9,
          0x8D40,
          0xBFDB,
          0xAE52,
          0xDAED,
          0xCB64,
          0xF9FF,
          0xE876,
          0x2102,
          0x308B,
          0x0210,
          0x1399,
          0x6726,
          0x76AF,
          0x4434,
          0x55BD,
          0xAD4A,
          0xBCC3,
          0x8E58,
          0x9FD1,
          0xEB6E,
          0xFAE7,
          0xC87C,
          0xD9F5,
          0x3183,
          0x200A,
          0x1291,
          0x0318,
          0x77A7,
          0x662E,
          0x54B5,
          0x453C,
          0xBDCB,
          0xAC42,
          0x9ED9,
          0x8F50,
          0xFBEF,
          0xEA66,
          0xD8FD,
          0xC974,
          0x4204,
          0x538D,
          0x6116,
          0x709F,
          0x0420,
          0x15A9,
          0x2732,
          0x36BB,
          0xCE4C,
          0xDFC5,
          0xED5E,
          0xFCD7,
          0x8868,
          0x99E1,
          0xAB7A,
          0xBAF3,
          0x5285,
          0x430C,
          0x7197,
          0x601E,
          0x14A1,
          0x0528,
          0x37B3,
          0x263A,
          0xDECD,
          0xCF44,
          0xFDDF,
          0xEC56,
          0x98E9,
          0x8960,
          0xBBFB,
          0xAA72,
          0x6306,
          0x728F,
          0x4014,
          0x519D,
          0x2522,
          0x34AB,
          0x0630,
          0x17B9,
          0xEF4E,
          0xFEC7,
          0xCC5C,
          0xDDD5,
          0xA96A,
          0xB8E3,
          0x8A78,
          0x9BF1,
          0x7387,
          0x620E,
          0x5095,
          0x411C,
          0x35A3,
          0x242A,
          0x16B1,
          0x0738,
          0xFFCF,
          0xEE46,
          0xDCDD,
          0xCD54,
          0xB9EB,
          0xA862,
          0x9AF9,
          0x8B70,
          0x8408,
          0x9581,
          0xA71A,
          0xB693,
          0xC22C,
          0xD3A5,
          0xE13E,
          0xF0B7,
          0x0840,
          0x19C9,
          0x2B52,
          0x3ADB,
          0x4E64,
          0x5FED,
          0x6D76,
          0x7CFF,
          0x9489,
          0x8500,
          0xB79B,
          0xA612,
          0xD2AD,
          0xC324,
          0xF1BF,
          0xE036,
          0x18C1,
          0x0948,
          0x3BD3,
          0x2A5A,
          0x5EE5,
          0x4F6C,
          0x7DF7,
          0x6C7E,
          0xA50A,
          0xB483,
          0x8618,
          0x9791,
          0xE32E,
          0xF2A7,
          0xC03C,
          0xD1B5,
          0x2942,
          0x38CB,
          0x0A50,
          0x1BD9,
          0x6F66,
          0x7EEF,
          0x4C74,
          0x5DFD,
          0xB58B,
          0xA402,
          0x9699,
          0x8710,
          0xF3AF,
          0xE226,
          0xD0BD,
          0xC134,
          0x39C3,
          0x284A,
          0x1AD1,
          0x0B58,
          0x7FE7,
          0x6E6E,
          0x5CF5,
          0x4D7C,
          0xC60C,
          0xD785,
          0xE51E,
          0xF497,
          0x8028,
          0x91A1,
          0xA33A,
          0xB2B3,
          0x4A44,
          0x5BCD,
          0x6956,
          0x78DF,
          0x0C60,
          0x1DE9,
          0x2F72,
          0x3EFB,
          0xD68D,
          0xC704,
          0xF59F,
          0xE416,
          0x90A9,
          0x8120,
          0xB3BB,
          0xA232,
          0x5AC5,
          0x4B4C,
          0x79D7,
          0x685E,
          0x1CE1,
          0x0D68,
          0x3FF3,
          0x2E7A,
          0xE70E,
          0xF687,
          0xC41C,
          0xD595,
          0xA12A,
          0xB0A3,
          0x8238,
          0x93B1,
          0x6B46,
          0x7ACF,
          0x4854,
          0x59DD,
          0x2D62,
          0x3CEB,
          0x0E70,
          0x1FF9,
          0xF78F,
          0xE606,
          0xD49D,
          0xC514,
          0xB1AB,
          0xA022,
          0x92B9,
          0x8330,
          0x7BC7,
          0x6A4E,
          0x58D5,
          0x495C,
          0x3DE3,
          0x2C6A,
          0x1EF1,
          0x0F78
        ]) do
    def fcstab(unquote(index)), do: unquote(value)
  end
end
