
defmodule H264.Decoder.Pps do

  @moduledoc """
    parse picture parameter set
  """

  require Logger
  require Math
  alias H264.Decoder.BitReader
  alias H264.Decoder.Collection

  def parse(data, bitOffset) do
    rest = data
    ss = byte_size(data)
    if ss > 25 do
      ^ss = 25
    end
    <<h::binary-size(ss), _rest::binary>> = data
    IO.inspect(h, base: :binary)
    IO.inspect(h)

    defaultResult = %{
      :scaling_list_4x4 => Collection.new_matrix(12, 16, 0),
      :scaling_list_8x8 => Collection.new_matrix(12, 64, 0),
    }

    {result, rest, bitOffset} = {defaultResult, rest, bitOffset} |> BitReader.bit_read_ue_v(:pic_parameter_set_id)
                                  |> BitReader.bit_read_ue_v(:seq_parameter_set_id)
                                  |> BitReader.bit_read_u(:entropy_coding_mode_flag, 1)
                                  |> BitReader.bit_read_u(:bottom_field_pic_order_in_frame_present_flag, 1)
                                  |> BitReader.bit_read_ue_v(:num_slice_groups_minus1)
                                  |> BitReader.bit_cond_read(BitReader.is_result_value_greater_than?(:num_slice_groups_minus1, 0), fn args ->
                                    args |> BitReader.bit_read_ue_v(:slice_group_map_type)
                                          |> BitReader.bit_cond_read(BitReader.is_result_value_equal?(:slice_group_map_type, 0), fn {result, rest, bitOffset} ->
                                            num_slice_groups_minus1 = result[:num_slice_groups_minus1]
                                            {result, rest, bitOffset} |> BitReader.bit_repeat_read(:run_length_minus1, num_slice_groups_minus1, &BitReader.read_ue_v/2)
                                          end)
                                          |> BitReader.bit_cond_read(BitReader.is_result_value_equal?(:slice_group_map_type, 2), fn {result, rest, bitOffset} ->
                                            num_slice_groups_minus1 = result[:num_slice_groups_minus1]
                                            {result, rest, bitOffset} |> BitReader.bit_repeat_multi_read([:top_left, :bottom_right], num_slice_groups_minus1, [&BitReader.read_ue_v/2,&BitReader.read_ue_v/2])
                                          end)
                                          |> BitReader.bit_cond_read(BitReader.is_result_value_in?(:slice_group_map_type, [3,4,5]), fn args ->
                                            args |> BitReader.bit_read_u(:slice_group_change_direction_flag, 1)
                                                  |> BitReader.bit_read_ue_v(:slice_group_change_rate_minus1)
                                          end)
                                          |> BitReader.bit_cond_read(BitReader.is_result_value_equal?(:slice_group_map_type, 6), fn args ->
                                            {result, rest, bitOffset} = args |> BitReader.bit_read_ue_v(:pic_size_in_map_units_minus1)
                                            num_slice_groups_minus1 = result[:num_slice_groups_minus1]
                                            pic_size_in_map_units_minus1 = result[:pic_size_in_map_units_minus1]
                                            readSize = Float.ceil(Math.log2(num_slice_groups_minus1 + 1))
                                            {result, rest, bitOffset} |> BitReader.bit_repeat_read_3(:slice_group_id, readSize, pic_size_in_map_units_minus1, &BitReader.read_u/3)
                                          end)
                                  end)
                                  |> BitReader.bit_read_ue_v(:num_ref_idx_10_default_active_minus1)
                                  |> BitReader.bit_read_ue_v(:num_ref_idx_11_default_active_minus1)
                                  |> BitReader.bit_read_u(:waited_pre_flag, 1)
                                  |> BitReader.bit_read_u(:waited_bipre_idc, 2)
                                  |> BitReader.bit_read_se_v(:pic_init_qp_minus26)
                                  |> BitReader.bit_read_se_v(:pic_init_qs_minus26)
                                  |> BitReader.bit_read_se_v(:chroma_qp_index_offset)
                                  |> BitReader.bit_read_u(:deblocking_filter_control_present_flag, 1)
                                  |> BitReader.bit_read_u(:constrainted_intra_pred_flag, 1)
                                  |> BitReader.bit_read_u(:redundant_pic_cnt_present_flag, 1)
                                  |> BitReader.bit_func_read(fn {result, rest, bitOffset} ->
                                    if BitReader.has_more_rbsp_data?(rest, bitOffset) do
                                      {result, rest, bitOffset} |> BitReader.bit_read_u(:transform_8x8_mode_flag, 1)
                                        |> BitReader.bit_read_u(:pic_scaling_matrix_present_flag, 1)
                                        |> BitReader.bit_cond_read(BitReader.is_result_value_equal?(:pic_scaling_matrix_present_flag, 1), &read_scaling/1)
                                        |> BitReader.bit_read_se_v(:second_chroma_qp_index_offset)
                                    else
                                      {result, rest, bitOffset}
                                    end
                                  end)

    IO.inspect(result)
    Logger.info("rest data: #{byte_size(rest)}, offset: #{bitOffset}")
    IO.inspect(rest, base: :binary)
  end

  defp read_scaling({result, rest, bitOffset}) do
    chroma_format_idc = result[:chroma_format_idc]
    transform_8x8_mode_flag = result[:transform_8x8_mode_flag]
    list_len = if chroma_format_idc != 3 do
      2
    else
      6
    end
    list_len = list_len * transform_8x8_mode_flag

    scalingList4x4 = result[:scaling_list_4x4]
    scalingList8x8 = result[:scaling_list_8x8]
    {pic_scaling_list_present_flag, rest, bitOffset, scalingList4x4, scalingList8x8} = read_scaling_list_item(rest, bitOffset, 0, list_len, scalingList4x4, scalingList8x8)
    Map.put(result, :pic_scaling_list_present_flag, pic_scaling_list_present_flag)
    Map.put(result, :scaling_list_4x4, scalingList4x4)
    Map.put(result, :scaling_list_8x8, scalingList8x8)
    {result, rest, bitOffset}
  end

  defp read_scaling_list_item(data, bitOffset, index, len, scalingList4x4, scalingList8x8) do
    if index < len do
      {b, rest, bitOffset} = H264.Decoder.BitReader.read_u(data, bitOffset, 1)
      if b == 1 do
        if index < 6 do
          change_scaling_list(data, bitOffset, Enum.at(scalingList4x4, index), 16, 0)
        else
          change_scaling_list(data, bitOffset, Enum.at(scalingList8x8, index-6), 16, 0)
        end
      end
      {list, rest, bitOffset, scalingList4x4, scalingList8x8} = read_scaling_list_item(rest, bitOffset, index+1, len, scalingList4x4, scalingList8x8)
      {[b | list], rest, bitOffset, scalingList4x4, scalingList8x8}
    else
      {[], data, bitOffset, scalingList4x4, scalingList8x8}
    end
  end

  defp change_scaling_list(data, bitOffset, scalingList, sizeOfScalingList, useDefaultScalingMatrixFlag) do
    change_scaling_list_item(data, bitOffset, scalingList, 0, sizeOfScalingList, useDefaultScalingMatrixFlag, 8, 8)
  end

  defp change_scaling_list_item(data, bitOffset, scalingList, index, sizeOfScalingList, useDefaultScalingMatrixFlag, lastScale, nextScale) do
    rest = data
    offset = bitOffset
    if index < sizeOfScalingList do
      if nextScale != 0 do
        {deltaScal, ^rest, ^offset} = BitReader.read_se_v(data, bitOffset)
        ^nextScale = rem((lastScale + deltaScal + 256), 256)
      end
      item = if nextScale == 0 do
        lastScale
      else
        nextScale
      end
      scalingList = List.update_at(scalingList, index, fn _r -> item end)
      lastScale = item
      change_scaling_list_item(data, bitOffset, scalingList, index+1, sizeOfScalingList, useDefaultScalingMatrixFlag, lastScale, nextScale)
    else
      {rest, offset, scalingList}
    end
  end
end
