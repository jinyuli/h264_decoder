
defmodule H264.Decoder.Sps do
  import Bitwise
  require Logger
  alias H264.Decoder.BitReader

  @profile_baseline 66
  @profile_main 77
  @profile_extended 88
  @profile_frext_hp 100
  @profile_frext_hi_10_p 110
  @profile_frext_hi_422 122
  @profile_frext_hi_444 244
  @profile_mvc_high 118
  @profile_stereo_high 128

  @chroma_format_idc_y 0
  @chroma_format_idc_420 1
  @chroma_format_idc_422 2
  @chroma_format_idc_444 3

  @special_profiles [@profile_frext_hp, @profile_frext_hi_10_p,
                      @profile_frext_hi_422, @profile_frext_hi_444,
                      @profile_mvc_high, @profile_stereo_high]

  defmodule SpsData do
    defstruct [:profile_idc,
                :constraint_set0_flag, :constraint_set1_flag, :constraint_set2_flag,
                :constraint_set3_flag, :constraint_set4_flag, :constraint_set5_flag,
                :reserved_zero_2bits, :level_idc, :seq_parameter_set_id,
                :log2_max_frame_num_minus4,
                :pic_order_cnt_type,
                :log2_max_pic_order_cnt_lsb_minus4, #pic_order_cnt_type = 0
                #pic_order_cnt_type = 1
                :delta_pic_order_always_zero_flag, :offset_for_non_ref_pic,
                :offset_for_top_to_bottom_field,
                :num_ref_frames_in_pic_order_cnt_cycle, :offset_for_ref_frame,
                #end
                :num_ref_frames,
                :gaps_in_frame_num_value_allowed_flag,
                :pic_width_in_mbs_minus1,
                :pic_height_in_map_units_minus1,
                :frame_mbs_only_flag,
                :mb_adaptive_frame_field_flag, #if (!frame_mbs_only_flag)
                :direct_8x8_inference_flag,
                :frame_cropping_flag,
                #if (frame_cropping_flag)
                :frame_crop_left_offset,
                :frame_crop_right_offset,
                :frame_crop_top_offset,
                :frame_crop_bottom_offset,
                #end
                :vui_parameters_present_flag,
                #if vui_parameters_present_flag
              ]
  end

  def parse(data, byte_offset, bitOffset) do
    rest = data
    ss = byte_size(data)
    if ss > 25 do
      ^ss = 25
    end
    <<h::binary-size(ss), _rest::binary>> = data
    IO.inspect(h, base: :binary)
    IO.inspect(h)
    # IO.puts(h)
    defaultResult = %{
      :chroma_format_idc => 1,
      :separate_colour_plane_flag => 0,
      :frame_crop_left_offset => 0,
      :frame_crop_right_offset => 0,
      :frame_crop_top_offset => 0,
      :frame_crop_bottom_offset => 0,
    }

    {result, restData, lastOffset} = {defaultResult, rest, bitOffset} |> BitReader.bit_read_u(:profile_idc, 8)
                                      |> BitReader.bit_read_u(:constraint_set0_flag, 1)
                                      |> BitReader.bit_read_u(:constraint_set1_flag, 1)
                                      |> BitReader.bit_read_u(:constraint_set2_flag, 1)
                                      |> BitReader.bit_read_u(:constraint_set3_flag, 1)
                                      |> BitReader.bit_read_u(:constraint_set4_flag, 1)
                                      |> BitReader.bit_read_u(:constraint_set5_flag, 1)
                                      |> BitReader.bit_read_u(:reserved_zero_2bits, 2)
                                      |> BitReader.bit_read_u(:level_idc, 8)
                                      |> BitReader.bit_read_ue_v(:seq_parameter_set_id)
                                      |> BitReader.bit_cond_read(&is_special_profile?/1,
                                      fn args ->
                                        args |> BitReader.bit_read_ue_v(:chroma_format_idc)
                                          |> BitReader.bit_cond_read(fn r -> r[:chroma_format_idc] == 3 end,
                                            fn args ->
                                              args |> BitReader.bit_read_u(:separate_colour_plane_flag, 1)
                                            end)
                                          |> BitReader.bit_read_ue_v(:bit_depth_luma_minus8)
                                          |> BitReader.bit_read_ue_v(:bit_depth_chroma_minus8)
                                          |> BitReader.bit_read_u(:qpprime_y_zero_transform_bypass_flag, 1)
                                          |> BitReader.bit_read_u(:seq_scaling_matrix_present_flag, 1)
                                          |> BitReader.bit_func_read(&read_scaling/1)
                                      end)
                                      |> BitReader.bit_read_ue_v(:log2_max_frame_num_minus4)
                                      |> BitReader.bit_read_ue_v(:pic_order_cnt_type)
                                      |> BitReader.bit_func_read(fn {result, rest, bitOffset} ->
                                          pic_order_cnt_type = result[:pic_order_cnt_type]
                                          case pic_order_cnt_type do
                                            0 ->
                                              {result, rest, bitOffset} |> BitReader.bit_read_ue_v(:log2_max_pic_order_cnt_lsb_minus4)
                                            1 ->
                                              {result, rest, bitOffset} |> BitReader.bit_read_u(:delta_pic_order_always_zero, 1)
                                                |> BitReader.bit_read_se_v(:offset_for_non_ref_pic)
                                                |> BitReader.bit_read_se_v(:offset_for_top_to_bottom_pic)
                                                |> BitReader.bit_read_ue_v(:num_ref_frames_in_pic_order_cnt_cycle)
                                                |> BitReader.bit_func_read(fn {result, rest, bitOffset} ->
                                                  num_ref = result[:num_ref_frames_in_pic_order_cnt_cycle]
                                                  BitReader.bit_repeat_read({result, rest, bitOffset}, :offset_for_ref_frame, num_ref, &BitReader.read_se_v/2)
                                                end)
                                            _ ->
                                              {result, rest, bitOffset}
                                          end
                                        end)
                                      |> BitReader.bit_read_ue_v(:max_num_ref_frames)
                                      |> BitReader.bit_read_u(:gaps_in_frame_num_value_allowed_flag, 1)
                                      |> BitReader.bit_read_ue_v(:pic_width_in_mbs_minus1)
                                      |> BitReader.bit_read_ue_v(:pic_height_in_map_units_minus1)
                                      |> BitReader.bit_read_u(:frame_mbs_only_flag, 1)
                                      |> BitReader.bit_func_read(fn {result, rest, offset} ->
                                        frame_mbs_only_flag = result[:frame_mbs_only_flag]
                                        if frame_mbs_only_flag == 0 do
                                          BitReader.bit_read_u({result, rest, offset}, :mb_adaptive_frame_field_flag, 1)
                                        else
                                          {result, rest, offset}
                                        end
                                      end)
                                      |> BitReader.bit_read_u(:direct_8x8_inference_flag, 1)
                                      |> BitReader.bit_read_u(:frame_cropping_flag, 1)
                                      |> BitReader.bit_cond_read(&is_frame_crop_set?/1, fn args ->
                                        args |> BitReader.bit_read_ue_v(:frame_crop_left_offset)
                                            |> BitReader.bit_read_ue_v(:frame_crop_right_offset)
                                            |> BitReader.bit_read_ue_v(:frame_crop_top_offset)
                                            |> BitReader.bit_read_ue_v(:frame_crop_bottom_offset)
                                      end)
                                      |> BitReader.bit_read_u(:vui_parameters_present_flag, 1)
                                      |> read_vui_paramets()
    IO.inspect(result)
    Logger.info("rest data: #{byte_size(restData)}, offset: #{lastOffset}")
    IO.inspect(rest, base: :binary)

    pic_width_in_mbs_minus1 = result[:pic_width_in_mbs_minus1]
    pic_height_in_map_units_minus1 = result[:pic_height_in_map_units_minus1]
    frame_cropping_flag = result[:frame_cropping_flag]
    frame_crop_left_offset = result[:frame_crop_left_offset]
    frame_crop_right_offset = result[:frame_crop_right_offset]
    frame_crop_top_offset = result[:frame_crop_top_offset]
    frame_crop_bottom_offset = result[:frame_crop_bottom_offset]
    frame_mbs_only_flag = result[:frame_mbs_only_flag]
    chroma_format_idc = result[:chroma_format_idc]
    separate_colour_plane_flag = result[:separate_colour_plane_flag]

    chroma_array_type = if separate_colour_plane_flag == 0 do
      chroma_format_idc
    else
      0
    end

    {sub_width_c, sub_height_c} = case chroma_array_type do
      1 ->
        {2, 2}
      2 ->
        {2, 1}
      3 ->
        {1, 1}
      _ ->
        {0, 0}
    end

    {width, height} = if frame_cropping_flag == 1 do
      {crop_unit_x, crop_unit_y} = if chroma_array_type == 0 do
        {1, 2 - frame_mbs_only_flag}
      else
        {sub_width_c, sub_height_c * (2 - frame_mbs_only_flag)}
      end
      {(pic_width_in_mbs_minus1 + 1) * 16 - crop_unit_x * (frame_crop_left_offset + frame_crop_right_offset),
        (2 - frame_mbs_only_flag) * (pic_height_in_map_units_minus1 + 1) * 16 - crop_unit_y * (frame_crop_bottom_offset + frame_crop_top_offset)}
    else
      {(pic_width_in_mbs_minus1 + 1) * 16, (2 - frame_mbs_only_flag) * (pic_height_in_map_units_minus1 + 1) * 16}
    end
    Map.put(result, :video_width, width)
    Map.put(result, :video_height, height)
    Logger.info("video width and height (#{width}, #{height})")
  end

  defp read_vui_paramets({result, rest, bitOffset}) do
    if is_result_value_equal?(result, :vui_parameters_present_flag, 1) do
      {result, rest, bitOffset} |> BitReader.bit_read_u(:aspect_ratio_info_present_flag, 1)
                                |> BitReader.bit_cond_read(is_result_value_equal?(:aspect_ratio_info_present_flag, 1), fn args ->
                                  args |> BitReader.bit_read_u(:aspect_ratio_idc, 8)
                                end)
    else
      {result, rest, bitOffset}
    end
  end

  defp read_scaling({result, rest, bitOffset}) do
    seq_scaling_matrix_present_flag = result[:seq_scaling_matrix_present_flag]
    chroma_format_idc = result[:chroma_format_idc]
    if (seq_scaling_matrix_present_flag == 1) do
      list_len = if chroma_format_idc != @chroma_format_idc_444 do
        8
      else
        12
      end
      # if chroma_format_idc != @chroma_format_idc_444 do
      #   list_len = 8
      # end
      {list_content, rest, bitOffset} = H264.Decoder.BitReader.read_u(rest, bitOffset, list_len)
      seq_scaling_list_present_flag = number_to_bit_list(list_content, list_len)
      Map.put(result, :seq_scaling_list_present_flag, seq_scaling_list_present_flag)
      {result, rest, bitOffset}
    else
      {result, rest, bitOffset}
    end
  end

  defp is_frame_crop_set?(result) do
    is_result_value_equal?(result, :frame_cropping_flag, 1)
  end

  defp is_result_value_equal?(key, expectedValue) do
    &(&1[key] == expectedValue)
  end

  defp is_result_value_equal?(result, key, expectedValue) do
    expectedValue == result[key]
  end

  defp is_special_profile?(result) do
    profile_idc = result[:profile_idc]
    Enum.any?(@special_profiles, fn x -> x == profile_idc end)
  end

  defp number_to_bit_list(num, len) do
    cond do
      len > 0 ->
        b = (num >>> (len-1)) &&& 0x01
        [b | number_to_bit_list(num, len-1)]
      true ->
        []
    end
  end
end
