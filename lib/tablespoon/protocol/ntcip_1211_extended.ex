defmodule Tablespoon.Protocol.NTCIP1211Extended do
  @moduledoc """
  Implementation of the NTCIP 1211 protocol, with the extended prgPriorityRequest message.

  The protocol is generally documented here:
  https://www.ntcip.org/wp-content/uploads/2018/11/NTCIP1211-v0224j.pdf

  It's built on top of SNMP version 1, documented in RFC 1157:
  https://tools.ietf.org/html/rfc1157

  The extension we use is an additional 2 bytes at the end of the
  prgPriorityRequest message, for the intersection ID. The cancel message
  does not also use this extension.
  """
  alias Tablespoon.Protocol.ASN1
  @enforce_keys [:group, :pdu_type, :request_id, :message]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          group: binary,
          pdu_type: :set | :response,
          request_id: integer,
          message: __MODULE__.PriorityRequest.t() | __MODULE__.PriorityCancel.t()
        }
  @type error :: :invalid

  defmodule PriorityRequest do
    @moduledoc """
    An OER encoded string of reference parameters to initiate a new priority request.

    - priorityRequestID                         INTEGER (1..255)
    - priorityRequestVehicleID                  OCTET STRING (SIZE 17)
    - priorityRequestVehicleClassType           INTEGER (1..10)
    - priorityRequestVehicleClassLevel          INTEGER (1..10)
    - priorityRequestServiceStrategyNumber      INTEGER (1..255)
    - priorityRequestTimeOfServiceDesired       INTEGER (1..65535)
    - priorityRequestTimeOfEstimatedDeparture   INTEGER (1..65535)
    - priorityRequestIntersectionID             INTEGER (1..65535)
    """
    @enforce_keys [
      :id,
      :vehicle_id,
      :vehicle_class,
      :vehicle_class_level,
      :strategy,
      :time_of_service_desired,
      :time_of_estimated_departure,
      :intersection_id
    ]
    defstruct @enforce_keys

    # The spec says that vehicle_class_level, time_of_service_desired, and
    # time_of_estimated_departure can't have 0 as a valid value, but that's
    # what we sent to BTD.
    @type t :: %__MODULE__{
            id: 1..255,
            vehicle_id: binary,
            vehicle_class: 1..10,
            vehicle_class_level: 0..10,
            strategy: 1..255,
            time_of_service_desired: 0..65_535,
            time_of_estimated_departure: 0..65_535,
            intersection_id: 1..65_535
          }

    def asn1_type, do: [1, 3, 6, 1, 4, 1, 1206, 4, 2, 11, 2, 1, 0]

    def encode_for_varbind(%__MODULE__{} = message) do
      vehicle_id = String.pad_leading(message.vehicle_id, 17, " ")

      <<message.id::unsigned-integer-8, vehicle_id::binary-17,
        message.vehicle_class::unsigned-integer-8,
        message.vehicle_class_level::unsigned-integer-8, message.strategy::unsigned-integer-8,
        message.time_of_service_desired::unsigned-integer-16,
        message.time_of_estimated_departure::unsigned-integer-16,
        message.intersection_id::unsigned-integer-16>>
    end

    def decode_from_varbind(binary) do
      <<id::unsigned-integer-8, vehicle_id::binary-17, vehicle_class::unsigned-integer-8,
        vehicle_class_level::unsigned-integer-8, strategy::unsigned-integer-8,
        time_of_service_desired::unsigned-integer-16,
        time_of_estimated_departure::unsigned-integer-16,
        intersection_id::unsigned-integer-16>> = binary

      vehicle_id = String.trim_leading(vehicle_id, " ")

      %__MODULE__{
        id: id,
        vehicle_id: vehicle_id,
        vehicle_class: vehicle_class,
        vehicle_class_level: vehicle_class_level,
        strategy: strategy,
        time_of_service_desired: time_of_service_desired,
        time_of_estimated_departure: time_of_estimated_departure,
        intersection_id: intersection_id
      }
    end
  end

  defmodule PriorityCancel do
    @moduledoc """
    An OER encoded string of reference parameters to cancel a priority request.

    - priorityRequestID                         INTEGER (1..255)
    - priorityRequestVehicleID                  OCTET STRING (SIZE 17)
    - priorityRequestVehicleClassType           INTEGER (1..10)
    - priorityRequestVehicleClassLevel          INTEGER (1..10)
    - priorityRequestServiceStrategyNumber      INTEGER (1..255)
    """
    @enforce_keys [:id, :vehicle_id, :vehicle_class, :vehicle_class_level, :strategy]
    defstruct @enforce_keys

    # The spec says that vehicle_class_level can't have 0 as a valid value,
    # but that's what we sent to BTD.
    @type t :: %__MODULE__{
            id: 1..255,
            vehicle_id: binary,
            vehicle_class: 1..10,
            vehicle_class_level: 0..10,
            strategy: 1..255
          }

    def asn1_type, do: [1, 3, 6, 1, 4, 1, 1206, 4, 2, 11, 2, 5, 0]

    def encode_for_varbind(%__MODULE__{} = message) do
      vehicle_id = String.pad_leading(message.vehicle_id, 17, " ")

      <<message.id::unsigned-integer-8, vehicle_id::binary-17,
        message.vehicle_class::unsigned-integer-8,
        message.vehicle_class_level::unsigned-integer-8, message.strategy::unsigned-integer-8>>
    end

    def decode_from_varbind(binary) do
      <<id::unsigned-integer-8, vehicle_id::binary-17, vehicle_class::unsigned-integer-8,
        vehicle_class_level::unsigned-integer-8, strategy::unsigned-integer-8>> = binary

      vehicle_id = String.trim_leading(vehicle_id, " ")

      %__MODULE__{
        id: id,
        vehicle_id: vehicle_id,
        vehicle_class: vehicle_class,
        vehicle_class_level: vehicle_class_level,
        strategy: strategy
      }
    end
  end

  @doc """
  Encode a NTCIP 1211 message into iodata.
  """
  @spec encode(t) :: iodata
  def encode(%__MODULE__{} = message) do
    message
    |> as_snmp_pdu_message()
    |> :snmp_pdus.enc_message()
  end

  @doc """
  Decode a binary into an NTCIP 1211 message.
  """
  @spec decode(binary) :: {:ok, t()} | {:error, error}
  def decode(<<48, _::binary>> = binary) do
    with {:ok, [0, group, pdu], ""} <- ASN1.decode(binary),
         {:ok, pdu_type, request_id, struct, varbind} <- decode_pdu(pdu) do
      {:ok,
       %__MODULE__{
         group: group,
         pdu_type: pdu_type,
         request_id: request_id,
         message: struct.decode_from_varbind(varbind)
       }}
    end
  end

  def decode(<<_::binary>>) do
    {:error, :invalid}
  end

  @doc """
  Return the ID of the message, or an error if we're unable to parse.

  Rather than going through `:snmp_pdus`, we re-implement some of the parsing
  ourselves in order to handle packets which do have a request ID, but are
  otherwise too short to be valid.
  """
  @spec decode_id(binary) :: {:ok, term} | {:error, error}
  def decode_id(<<48, binary::binary>>) do
    with {:ok, _, <<2, 1, 0, 4, rest::binary>>} <- ASN1.decode_ber_length(binary),
         {:ok, group_name_length, rest} <- ASN1.decode_ber_length(rest),
         <<_ignored::binary-size(group_name_length), _pdu_tag::binary-1, rest::binary>> <- rest,
         {:ok, _pdu_length, rest} <- ASN1.decode_ber_length(rest),
         {:ok, request_id, rest} when is_integer(request_id) <- ASN1.decode(rest),
         {:ok, _error, rest} <- ASN1.decode(rest),
         {:ok, _error_index, rest} <- ASN1.decode(rest),
         <<48, rest::binary>> <- rest,
         {:ok, _length, rest} <- ASN1.decode_ber_length(rest),
         <<48, rest::binary>> <- rest,
         {:ok, _length, rest} <- ASN1.decode_ber_length(rest),
         <<6, rest::binary>> <- rest,
         {:ok, _, rest} <- ASN1.decode_octet_string(rest),
         <<4, rest::binary>> <- rest,
         {:ok, _length, rest} <- ASN1.decode_ber_length(rest),
         <<inner_id::integer-8, _::binary>> <- rest do
      {:ok, {request_id, inner_id}}
    else
      {:error, _} = e ->
        e

      _ ->
        {:error, :invalid}
    end
  end

  def decode_id(binary) when is_binary(binary) do
    {:error, :invalid}
  end

  @spec decode_pdu(term) :: {:ok, :response | :set, integer, module, binary} | {:error, error}
  defp decode_pdu({:tag, pdu_type, [request_id, 0, 0, pdu]}) do
    with pdu_type when pdu_type in [2, 3] <- pdu_type,
         [[asn1_type, varbind]] <- pdu,
         {:ok, struct} <- struct_from_asn1_type(asn1_type) do
      pdu_type =
        case pdu_type do
          2 -> :response
          3 -> :set
        end

      {:ok, pdu_type, request_id, struct, varbind}
    else
      {:error, _} = e ->
        e

      _ ->
        {:error, :invalid}
    end
  end

  defp decode_pdu({:tag, pdu_type, [request_id, false, false, pdu]}) do
    # we sometimes get these slightly invalid packets, with false values
    # instead of 0 for the errors
    decode_pdu({:tag, pdu_type, [request_id, 0, 0, pdu]})
  end

  defp decode_pdu({:tag, _, [_request_id, error_int, _, _]}) do
    # error codes from https://tools.ietf.org/html/rfc1157#section-4.1.1
    error =
      case error_int do
        1 -> :too_big
        2 -> :no_such_name
        3 -> :bad_value
        4 -> :read_only
        5 -> :generic_error
        e -> {:unknown, e}
      end

    {:error, error}
  end

  defp decode_pdu(_) do
    {:error, :invalid}
  end

  defp as_snmp_pdu_message(message) do
    {:message, :"version-1", :binary.bin_to_list(message.group), as_snmp_pdu(message)}
  end

  defp as_snmp_pdu(message) do
    type =
      case message.pdu_type do
        :set -> :"set-request"
        :response -> :"get-response"
      end

    {:pdu, type, message.request_id, :noError, 0,
     [
       {:varbind, asn1_type(message.message), :"OCTET STRING",
        :binary.bin_to_list(encode_for_varbind(message.message)), 1}
     ]}
  end

  for struct <- [__MODULE__.PriorityRequest, __MODULE__.PriorityCancel] do
    defp asn1_type(%{__struct__: unquote(struct)}), do: unquote(struct.asn1_type())
    defp struct_from_asn1_type(unquote(struct.asn1_type())), do: {:ok, unquote(struct)}
  end

  defp struct_from_asn1_type(unknown), do: {:error, {:unknown, unknown}}

  defp encode_for_varbind(%{__struct__: struct} = message) do
    struct.encode_for_varbind(message)
  end
end
