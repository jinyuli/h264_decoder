defmodule H264.Decoder.Nal do
  import Bitwise
  require Logger

  @nal_type_unuse 0
  @nal_type_single 1
  @nal_type_partition_a 2
  @nal_type_partition_b 3
  @nal_type_partition_c 4
  @nal_type_idr 5
  @nal_type_sei 6
  @nal_type_sps 7
  @nal_type_pps 8
  @nal_type_delimiter 9
  @nal_type_seq_end 10
  @nal_type_stream_end 11
  @nal_type_padding 12
  @nal_type_sps_ext 13
  @nal_type_prefix 14
  @nal_type_sub_sps 15
  @nal_type_dps 16 #depth parameter set

  @moduledoc """
    forbidden_zero_bit: always 0
    nal_ref_idc: 当前nal的优先级
    nal_unit_type: nal类型
  """
  defmodule NalData do
    @enforce_keys [:forbidden_zero_bit, :nal_ref_idc, :nal_unit_type]
    defstruct [:forbidden_zero_bit, :nal_ref_idc, :nal_unit_type]
  end

  def parse(binaries) do
    read_nals(binaries)
  end

  defp read_nals(binaries) when byte_size(binaries) > 0 do
    start = find_start(binaries)
    {raw_nal, rest} = read_content(start)
    nal_data = filter_nal(raw_nal)
    # Logger.debug("nal , filtered? #{byte_size(nal_data) == byte_size(raw_nal)}, raw size #{byte_size(raw_nal)}, size #{byte_size(nal_data)}, rest size #{byte_size(rest)}")
    parse_nal(nal_data)
    # if nal.nal_unit_type != @nal_type_single do
    #   IO.puts("#{nal.forbidden_zero_bit}, #{nal.nal_ref_idc}, #{nal.nal_unit_type}")
    # end
    read_nals(rest)
  end

  defp read_nals(_) do
    IO.puts("no more data")
  end

  defp parse_nal(nal_binary) do
    <<b, rest::binary>> = nal_binary
    forbidden_zero_bit = (b >>> 7) &&& 0x01
    nal_ref_idc = (b >>> 5) &&& 0x03
    nal_unit_type = b &&& 0x1F
    # {forbidden_zero_bit, rest} = BitReader.read_f(rest, 1)
    # {nal_ref_idc, rest} = BitReader.read_u(rest, 2)
    # {nal_unit_type, rest} = BitReader.read_u(rest, 5)

    # IO.puts("#{forbidden_zero_bit}, #{nal_ref_idc}, #{nal_unit_type}, rest size: #{byte_size(rest)}")

    case nal_unit_type do
      @nal_type_sps ->
        Logger.info("parse sps")
        H264.Decoder.Sps.parse(rest, 0)
      @nal_type_pps ->
        Logger.info("parse pps")
        H264.Decoder.Pps.parse(rest, 0)
      @nal_type_single ->
        Logger.info("parse single")
        H264.Decoder.Slice.parse_single(rest, 0)
      # @nal_type_partition_a ->
      #   Logger.info("parse partition a")
      # @nal_type_partition_b ->
      #   Logger.info("parse partition b")
      # @nal_type_partition_c ->
      #   Logger.info("parse partition c")
      _ ->
        1
        #Logger.warn("ignored NAL unit type #{nal_unit_type}")
        #ignore
    end

    %NalData{forbidden_zero_bit: forbidden_zero_bit,
      nal_ref_idc: nal_ref_idc,
      nal_unit_type: nal_unit_type
    }
  end

  defp read_content(binaries) do
    size = read_nal_length(binaries)
    <<nal::binary-size(size), rest::binary>> = binaries
    {nal, rest}
  end

  defp filter_nal(nal) do
    filter_nal_sub(nal, 0)
  end

  defp filter_nal_sub(nal, offset) do
    cond do
      offset < byte_size(nal) ->
        case nal do
          <<pre::binary-size(offset), 0, 0, 3, rest::binary>> ->
            filter_nal_sub(pre <> <<0, 0>> <> rest, offset + 2)
          _ ->
            filter_nal_sub(nal, offset+1)
        end
      true ->
        nal
    end
  end

  defp read_nal_length(binaries) do
    case binaries do
      <<0,0,1, _rest::binary>> ->
        0
      <<0,0,0,1, _rest::binary>> ->
        0
      <<_h::binary-size(1), rest::binary>> ->
        1 + read_nal_length(rest)
      <<>> ->
        0
    end
  end

  defp find_start(<<0,0,0, rest::binary>>) do
    find_start_1(rest)
  end
  defp find_start(<<0,0,1, rest::binary>>) do
    rest
  end
  defp find_start(<<_h, rest::binary>>) do
    find_start(rest)
  end

  defp find_start_1(<<1, rest::binary>>) do
    rest
  end
  defp find_start_1(<<0, rest::binary>>) do
    find_start_1(rest)
  end
  defp find_start_1(binaries) do
    find_start(binaries)
  end
end
