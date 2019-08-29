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

    @type t :: %__MODULE__{
            id: 1..255,
            vehicle_id: binary,
            vehicle_class: 1..10,
            vehicle_class_level: 1..10,
            strategy: 1..255,
            time_of_service_desired: 1..65_535,
            time_of_estimated_departure: 1..65_535,
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

    @type t :: %__MODULE__{
            id: 1..255,
            vehicle_id: binary,
            vehicle_class: 1..10,
            vehicle_class_level: 1..10,
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
  def decode(binary) when is_binary(binary) do
    {:message, :"version-1", group_list, {:pdu, pdu_type, request_id, :noError, 0, pdu}} =
      :snmp_pdus.dec_message(:binary.bin_to_list(binary))

    group = IO.iodata_to_binary(group_list)

    pdu_type =
      case pdu_type do
        :"set-request" -> :set
        :"get-response" -> :response
      end

    [{:varbind, asn1_type, :"OCTET STRING", varbind_list, 1}] = pdu
    struct = struct_from_asn1_type(asn1_type)

    {:ok,
     %__MODULE__{
       group: group,
       pdu_type: pdu_type,
       request_id: request_id,
       message: struct.decode_from_varbind(IO.iodata_to_binary(varbind_list))
     }}
  rescue
    _e in [MatchError, FunctionClauseError] ->
      {:error, :invalid}
  catch
    :exit, _reason ->
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
    defp struct_from_asn1_type(unquote(struct.asn1_type())), do: unquote(struct)
  end

  defp encode_for_varbind(%{__struct__: struct} = message) do
    struct.encode_for_varbind(message)
  end
end
