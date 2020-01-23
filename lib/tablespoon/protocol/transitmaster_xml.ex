defmodule Tablespoon.Protocol.TransitmasterXml do
  @moduledoc """
  Parses a Transitmaster TSP XML packet
  """
  @enforce_keys [
    :id,
    :type,
    :event_time,
    :event_id,
    :vehicle_id,
    :vehicle_latitude,
    :vehicle_longitude
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          id: binary,
          type: :checkin | :checkout,
          event_time: non_neg_integer,
          event_id: non_neg_integer,
          vehicle_id: binary,
          vehicle_latitude: float | nil,
          vehicle_longitude: float | nil
        }

  @type error :: :invalid | :too_short

  require Record
  Record.defrecordp(:xmlElement, Record.extract(:xmlElement, from_lib: "xmerl/include/xmerl.hrl"))
  Record.defrecordp(:xmlText, Record.extract(:xmlText, from_lib: "xmerl/include/xmerl.hrl"))

  @header "TMTSPDATAHEADER"

  @spec encode(t) :: iodata
  def encode(%__MODULE__{} = tm) do
    tag =
      case tm.type do
        :checkin -> :TSP_CHECKINMESSAGE
        :checkout -> :TSP_CHECKOUTMESSAGE
      end

    xml_iodata =
      :xmerl.export_simple(
        [
          {tag, [],
           [
             encode_tag(:GUID, tm.id),
             encode_tag(
               :EVENT_TIME,
               tm.event_time |> DateTime.from_unix!(:native) |> DateTime.to_iso8601()
             ),
             encode_tag(:TRAFFIC_SIGNAL_EVENT_ID, Integer.to_charlist(tm.event_id)),
             encode_tag(:VEHICLE_ID, tm.vehicle_id),
             encode_tag(:VEHICLE_LATITUDE, encode_optional_float(tm.vehicle_latitude)),
             encode_tag(:VEHICLE_LONGITUDE, encode_optional_float(tm.vehicle_longitude))
           ]}
        ],
        :xmerl_xml
      )

    length = IO.iodata_length(xml_iodata)
    length_binary = length |> Integer.to_string() |> String.pad_leading(6, "0")
    [@header, length_binary, xml_iodata]
  end

  @spec decode(binary) :: {:ok, t, binary} | {:error, error, binary}
  def decode(binary)

  def decode(<<@header, size_binary::binary-6, rest::binary>> = all) do
    with {size, ""} <- Integer.parse(size_binary),
         <<xml_binary::binary-size(size), rest::binary>> <- rest do
      case decode_xml_binary(xml_binary) do
        {:ok, decoded} ->
          {:ok, decoded, rest}

        {:error, e} ->
          {:error, e, rest}
      end
    else
      {_, _} ->
        {:error, :invalid, ""}

      :error ->
        {:error, :too_short, ""}

      binary when is_binary(binary) ->
        {:error, :too_short, all}
    end
  end

  def decode(bin) when byte_size(bin) < byte_size(@header) + 6 do
    # if the shared prefix of the two packets isn't the header, then there's
    # no way that the packet will match.
    min_size = min(byte_size(bin), byte_size(@header))

    if :binary.part(bin, 0, min_size) == :binary.part(@header, 0, min_size) do
      {:error, :too_short, bin}
    else
      {:error, :invalid, ""}
    end
  end

  def decode(bin) when is_binary(bin) do
    {:error, :invalid, ""}
  end

  defp encode_tag(tag, value) when is_binary(value) do
    encode_tag(tag, :binary.bin_to_list(value))
  end

  defp encode_tag(tag, value) when is_list(value) do
    xmlElement(name: tag, content: [xmlText(value: value)])
  end

  defp encode_optional_float(nil), do: ""
  defp encode_optional_float(float) when is_float(float), do: Float.to_string(float)

  defp decode_xml_binary(binary) do
    case :xmerl_scan.string(:binary.bin_to_list(binary), quiet: true) do
      {xml_term, []} ->
        decode_xml_term(xml_term)

      _ ->
        {:error, :invalid}
    end
  catch
    :exit, _ ->
      {:error, :invalid}
  end

  defp decode_xml_term(xmlElement(name: name, content: content)) do
    with {:ok, type} <- decode_name(name),
         %{} = map <- Enum.reduce_while(content, %{type: type}, &decode_xml_content/2) do
      {:ok, struct!(__MODULE__, map)}
    end
  end

  defp decode_name(:TSP_CHECKOUTMESSAGE), do: {:ok, :checkout}
  defp decode_name(:TSP_CHECKINMESSAGE), do: {:ok, :checkin}
  defp decode_name(_), do: {:error, :invalid}

  defp decode_xml_content(xmlElement(name: :GUID, content: content), acc) do
    id =
      content
      |> content_value
      |> IO.iodata_to_binary()

    {:cont, Map.put(acc, :id, id)}
  end

  defp decode_xml_content(xmlElement(name: :TRAFFIC_SIGNAL_EVENT_ID, content: content), acc) do
    event_id =
      content
      |> content_value
      |> list_to_integer

    {:cont, Map.put(acc, :event_id, event_id)}
  end

  defp decode_xml_content(xmlElement(name: :EVENT_TIME, content: content), acc) do
    case content |> content_value |> IO.iodata_to_binary() |> DateTime.from_iso8601() do
      {:ok, dt, _} ->
        unix = dt |> DateTime.to_unix() |> System.convert_time_unit(:second, :native)
        {:cont, Map.put(acc, :event_time, unix)}

      _ ->
        {:halt, {:error, :invalid}}
    end
  end

  defp decode_xml_content(xmlElement(name: :VEHICLE_ID, content: content), acc) do
    vehicle_id =
      content
      |> content_value
      |> IO.iodata_to_binary()

    {:cont, Map.put(acc, :vehicle_id, vehicle_id)}
  end

  defp decode_xml_content(xmlElement(name: :VEHICLE_LATITUDE, content: content), acc) do
    latitude =
      if content == [] do
        nil
      else
        content |> content_value |> :erlang.list_to_float()
      end

    {:cont, Map.put(acc, :vehicle_latitude, latitude)}
  end

  defp decode_xml_content(xmlElement(name: :VEHICLE_LONGITUDE, content: content), acc) do
    longitude =
      if content == [] do
        nil
      else
        content |> content_value |> :erlang.list_to_float()
      end

    {:cont, Map.put(acc, :vehicle_longitude, longitude)}
  end

  defp decode_xml_content(xmlElement(), acc) do
    {:cont, acc}
  end

  defp decode_xml_content(xmlText(), acc) do
    {:cont, acc}
  end

  defp content_value([xmlText(value: value)]) do
    value
  end

  defp content_value([]) do
    []
  end

  @ascii_to_integer 48
  defp list_to_integer([first | rest])
       when first >= @ascii_to_integer and first < @ascii_to_integer + 10 do
    list_to_integer(rest, first - @ascii_to_integer)
  end

  defp list_to_integer([first | rest], acc)
       when first >= @ascii_to_integer and first < @ascii_to_integer + 10 do
    acc = acc * 10 + first - @ascii_to_integer
    list_to_integer(rest, acc)
  end

  defp list_to_integer([], acc) do
    acc
  end
end
