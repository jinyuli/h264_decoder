
defmodule H264.Decoder.Slice do

  @moduledoc """
    parse Slice
  """

  require Logger
  alias H264.Decoder.BitReader

  @slice_type_p 0
  @slice_type_b 1
  @slice_type_i 2
  @slice_type_sp 3
  @slice_type_si 4
  @slice_type_all_p 5
  @slice_type_all_b 6
  @slice_type_all_i 7
  @slice_type_all_sp 8
  @slice_type_all_si 9

  def parse_single(data, bitOffset, context) do
    Logger.info("parse single slice with data size #{byte_size(data)} and offset #{bitOffset}")
    rest = data
    data_size = byte_size(data)
    ss = if data_size > 25, do: 25, else: data_size
    <<h::binary-size(ss), _rest::binary>> = data
    IO.inspect(h, base: :binary)
    IO.inspect(h)
    # IO.puts(h)
    defaultResult = %{
      :field_pic_flag => 0, # ?
    }

    {result, rest, bitOffset} = {defaultResult, rest, bitOffset} |> parse_header(context)
      |> parse_data()

    IO.inspect(result)
    Logger.info("slice single rest data: #{byte_size(rest)}, offset: #{bitOffset}")
    IO.inspect(rest, base: :binary)
    {result, rest, bitOffset}
  end

  defp parse_header({result, rest, bitOffset}, context) do
    %{:nal => nalResult} = context
    nal_unit_type = nalResult[:nal_unit_type]
    nal_ref_idc = nalResult[:nal_ref_idc]
    idrPicFlag = if nal_unit_type == 5, do: 1, else: 0

    {result, rest, bitOffset} = {result, rest, bitOffset} |> BitReader.bit_read_ue_v(:first_mb_in_slice)
      |> BitReader.bit_read_ue_v(:slice_type)
      |> BitReader.bit_read_ue_v(:pic_parameter_set_id)
      |> BitReader.bit_func_read(fn {result, rest, bitOffset} ->
        result = set_global_parameter(result, context)
        {result, rest, bitOffset}
      end)
      |> BitReader.bit_cond_read(BitReader.is_result_value_equal?(:separate_colour_plane_flag, 1), fn args ->
        args |> BitReader.bit_read_u(:colour_plane_id, 2)
      end)
      |> BitReader.bit_func_read(fn args ->
        {result, _r, _b} = args
        log2_max_frame_num_minus4 = result[:log2_max_frame_num_minus4]
        args |> BitReader.bit_read_u(:frame_num, log2_max_frame_num_minus4 + 4)
      end)
      |> BitReader.bit_cond_read(BitReader.is_result_value_equal?(:frame_mbs_only_flag, 0), fn args ->
        args |> BitReader.bit_read_u(:field_pic_flag, 1)
              |> BitReader.bit_cond_read(BitReader.is_result_value_equal?(:field_pic_flag, 1), fn args ->
                args |> BitReader.bit_read_u(:bottom_field_flag, 1)
              end)
      end)
      |> BitReader.bit_cond_read(fn (_r) -> idrPicFlag == 1 end, fn args ->
        args |> BitReader.bit_read_ue_v(:idr_pic_id)
      end)
      |> BitReader.bit_cond_read(BitReader.is_result_value_equal?(:pic_order_cnt_type, 0), fn args ->
        {result, _r, _b} = args
        args |> BitReader.bit_read_u(:pic_order_cnt_lsb, result[:log2_max_pic_order_cnt_lsb_minus4] + 4)
              |> BitReader.bit_func_read(fn {result, rest, bitOffset} ->
                field_pic_flag = result[:field_pic_flag]
                if result[:bottom_field_pic_order_in_frame_present_flag] == 1 and field_pic_flag == 0 do
                  {result, rest, bitOffset} |> BitReader.bit_read_se_v(:delta_pic_order_cnt_bottom)
                else
                  {result, rest, bitOffset}
                end
              end)
      end)
      |> BitReader.bit_cond_read(fn r -> r[:pic_order_cnt_type] == 1 and r[:delta_pic_order_always_zero_flag] == 0 end, fn args ->
        {result, rest, bitOffset} = args |> BitReader.bit_read_se_v(:delta_pic_order_cnt_0)
                                          |> BitReader.bit_func_read(fn {result, rest, bitOffset} ->
                                            field_pic_flag = result[:field_pic_flag]
                                            if ((result[:bottom_field_pic_order_in_frame_present_flag] == 1) and (field_pic_flag == 0)) do
                                              {result, rest, bitOffset} |> BitReader.bit_read_se_v(:delta_pic_order_cnt_1)
                                            else
                                              {result, rest, bitOffset}
                                            end
                                          end)
        delta_pic_order_cnt_0 = result[:delta_pic_order_cnt_0]
        delta_pic_order_cnt_1 = if Map.has_key?(result, :delta_pic_order_cnt_0), do: result[:delta_pic_order_cnt_0], else: 0
        result = Map.put(result, :delta_pic_order_cnt, [delta_pic_order_cnt_0, delta_pic_order_cnt_1])
        {result, rest, bitOffset}
      end)
      |> BitReader.bit_cond_read(BitReader.is_result_value_equal?(:redundant_pic_cnt_present_flag, 1), fn args ->
        args |> BitReader.bit_read_ue_v(:redundant_pic_cnt)
      end)
      |> BitReader.bit_cond_read(BitReader.is_result_value_in?(:slice_type, [@slice_type_all_b, @slice_type_b]), fn args ->
        args |> BitReader.bit_read_u(:direct_spatial_mv_pred_flag, 1)
      end)
      |> BitReader.bit_cond_read(BitReader.is_result_value_in?(:slice_type, [@slice_type_all_p, @slice_type_p, @slice_type_all_sp, @slice_type_sp, @slice_type_all_b, @slice_type_b]), fn args ->
        args |> BitReader.bit_read_u(:num_ref_idx_active_override_flag, 1)
              |> BitReader.bit_cond_read(BitReader.is_result_value_equal?(:num_ref_idx_active_override_flag, 1), fn args ->
                args |> BitReader.bit_read_ue_v(:num_ref_idx_l0_active_minus1)
                      |> BitReader.bit_cond_read(BitReader.is_result_value_in?(:slice_type, [@slice_type_all_b, @slice_type_b]), fn args ->
                        args |> BitReader.bit_read_ue_v(:num_ref_idx_l1_active_minus1)
                      end)
              end)
      end)
      |> BitReader.bit_cond_read(fn _r -> nal_unit_type == 20 or nal_unit_type == 21 end, fn args ->
        Logger.warn("reading unimplemented block, slice head, ref_pic_list_mvc_modification()")
        args
      end, fn args ->
        args |> read_ref_pic_list_modification()
      end)
      |> BitReader.bit_cond_read(fn result ->
        slice_type = result[:slice_type]
        (result[:weighted_pred_flag] == 1
          and (slice_type == @slice_type_all_p
                or slice_type == @slice_type_p
                or slice_type == @slice_type_all_sp
                or slice_type == @slice_type_sp))
        or (result[:weighted_bipred_idc] == 1
          and (slice_type == @slice_type_all_b
                or slice_type == @slice_type_b))
      end, fn args ->
        args |> read_pred_weight_table()
      end)
      |> BitReader.bit_cond_read(fn _r -> nal_ref_idc != 0 end, fn args ->
        args |> read_dec_ref_pic_marking(idrPicFlag)
      end)
      |> BitReader.bit_cond_read(fn result ->
        slice_type = result[:slice_type]
        (result[:entropy_coding_mode_flag] == 1
          and slice_type != @slice_type_all_i
          and slice_type != @slice_type_i
          and slice_type != @slice_type_all_si
          and slice_type != @slice_type_si)
      end, fn args ->
        args |> BitReader.bit_read_ue_v(:cabac_init_idc)
      end)
      |> BitReader.bit_read_se_v(:slice_qp_delta)
      |> BitReader.bit_cond_read(BitReader.is_result_value_in?(:slice_type, [@slice_type_all_sp, @slice_type_sp, @slice_type_all_si, @slice_type_si]), fn args ->
        args |> BitReader.bit_cond_read(BitReader.is_result_value_in?(:slice_type, [@slice_type_all_sp, @slice_type_sp]), fn args ->
          args |> BitReader.bit_read_u(:sp_for_switch_flag, 1)
        end)
        |> BitReader.bit_read_se_v(:slice_qs_delta)
      end)
      |> BitReader.bit_cond_read(fn r -> r[:deblocking_filter_control_present_flag] == 1 end, fn args ->
        args |> BitReader.bit_read_ue_v(:disable_deblocking_filter_idc)
              |> BitReader.bit_cond_read(BitReader.is_result_value_not_equal?(:disable_deblocking_filter_idc, 1), fn args ->
                args |> BitReader.bit_read_se_v(:slice_alpha_c0_offset_div2)
                      |> BitReader.bit_read_se_v(:slice_beta_offset_div2)
              end)
      end)
      |> BitReader.bit_cond_read(fn r ->
        num_slice_groups_minus1 = r[:num_slice_groups_minus1]
        slice_group_map_type = r[:slice_group_map_type]
        (num_slice_groups_minus1 > 0) and (slice_group_map_type >= 3) and (slice_group_map_type <= 5)
      end, fn args ->
        {result, _r, _b} = args
        args |> BitReader.bit_read_u(:slice_group_change_cycle, Float.ceil(Math.log2(result[:picSizeInMapUnits] / result[:sliceGroupChangeRate] + 1)))
      end)

    IO.inspect(result)
    Logger.info("slice header rest data: #{byte_size(rest)}, offset: #{bitOffset}")
    # IO.inspect(rest, base: :binary)
    {result, rest, bitOffset}
  end

  defp parse_data({result, rest, bitOffset}) do
     {result, rest, bitOffset} = {result, rest, bitOffset} |> BitReader.bit_cond_read(fn r -> r[:entropy_coding_mode_flag] == 1 end, &BitReader.align_byte/1)

    IO.inspect(result)
    Logger.info("slice data rest data: #{byte_size(rest)}, offset: #{bitOffset}")
    # IO.inspect(rest, base: :binary)
    {result, rest, bitOffset}
  end

  ## header part

  defp set_global_parameter(result, context) do
    %{:sps => spsMap, :pps => ppsMap} = context
    pic_parameter_set_id = result[:pic_parameter_set_id]
    ppsResult = ppsMap[pic_parameter_set_id]
    seq_parameter_set_id = ppsResult[:seq_parameter_set_id]
    spsResult = spsMap[seq_parameter_set_id]
    Logger.info("set_global_parameter pps:#{pic_parameter_set_id}, sps:#{seq_parameter_set_id}")
    result = result |> Map.put(:cur_pps, ppsResult) |> Map.put(:cur_sps, spsResult)

    separate_colour_plane_flag = spsResult[:separate_colour_plane_flag]
    frame_mbs_only_flag = spsResult[:frame_mbs_only_flag]
    # chroma_format_idc = spsResult[:chroma_format_idc]
    log2_max_frame_num_minus4 = spsResult[:log2_max_frame_num_minus4]
    log2_max_pic_order_cnt_lsb_minus4 = spsResult[:log2_max_pic_order_cnt_lsb_minus4]
    pic_order_cnt_type = spsResult[:pic_order_cnt_type]
    delta_pic_order_always_zero_flag = spsResult[:delta_pic_order_always_zero_flag]
    chromaArrayType = spsResult[:chromaArrayType]

    result = result |> Map.put(:separate_colour_plane_flag, separate_colour_plane_flag)
              |> Map.put(:frame_mbs_only_flag, frame_mbs_only_flag)
              |> Map.put(:log2_max_frame_num_minus4, log2_max_frame_num_minus4)
              |> Map.put(:log2_max_pic_order_cnt_lsb_minus4, log2_max_pic_order_cnt_lsb_minus4)
              |> Map.put(:pic_order_cnt_type, pic_order_cnt_type)
              |> Map.put(:delta_pic_order_always_zero_flag, delta_pic_order_always_zero_flag)
              |> Map.put(:chromaArrayType, chromaArrayType)


    bottom_field_pic_order_in_frame_present_flag = ppsResult[:bottom_field_pic_order_in_frame_present_flag]
    redundant_pic_cnt_present_flag = ppsResult[:redundant_pic_cnt_present_flag]
    weighted_pred_flag = ppsResult[:weighted_pred_flag]
    weighted_bipred_idc = ppsResult[:weighted_bipred_idc]
    entropy_coding_mode_flag = ppsResult[:entropy_coding_mode_flag]
    deblocking_filter_control_present_flag = ppsResult[:deblocking_filter_control_present_flag]
    num_slice_groups_minus1 = ppsResult[:num_slice_groups_minus1]
    slice_group_map_type = ppsResult[:slice_group_map_type]
    slice_group_change_rate_minus1 = ppsResult[:slice_group_change_rate_minus1]
    pic_size_in_map_units_minus1 = ppsResult[:pic_size_in_map_units_minus1]
    picSizeInMapUnits = pic_size_in_map_units_minus1 + 1
    sliceGroupChangeRate = slice_group_change_rate_minus1 + 1

    result = result |> Map.put(:bottom_field_pic_order_in_frame_present_flag, bottom_field_pic_order_in_frame_present_flag)
              |> Map.put(:redundant_pic_cnt_present_flag, redundant_pic_cnt_present_flag)
              |> Map.put(:weighted_pred_flag, weighted_pred_flag)
              |> Map.put(:weighted_bipred_idc, weighted_bipred_idc)
              |> Map.put(:entropy_coding_mode_flag, entropy_coding_mode_flag)
              |> Map.put(:deblocking_filter_control_present_flag, deblocking_filter_control_present_flag)
              |> Map.put(:num_slice_groups_minus1, num_slice_groups_minus1)
              |> Map.put(:slice_group_map_type, slice_group_map_type)
              |> Map.put(:slice_group_change_rate_minus1, slice_group_change_rate_minus1)
              |> Map.put(:pic_size_in_map_units_minus1, pic_size_in_map_units_minus1)
              |> Map.put(:picSizeInMapUnits, picSizeInMapUnits)
              |> Map.put(:sliceGroupChangeRate, sliceGroupChangeRate)
              |> Map.put(:num_ref_idx_l0_active_minus1, ppsResult[:num_ref_idx_l0_default_active_minus1])
              |> Map.put(:num_ref_idx_l1_active_minus1, ppsResult[:num_ref_idx_l1_default_active_minus1])

    result
  end

  defp read_ref_pic_list_modification({result, rest, bitOffset}) do
    slice_type = result[:slice_type]
    rem_slice_type = rem(slice_type, 5)
    {result, rest, bitOffset} = BitReader.bit_cond_read({result, rest, bitOffset},
      fn _r -> (rem_slice_type != 2) and (rem_slice_type != 4) end,
      fn args ->
        args |> read_ref_pic_list_modification_flag(:ref_pic_list_modification_flag_l0)
    end)
    |> BitReader.bit_cond_read(fn _r -> rem_slice_type == 1 end, fn args ->
      args |> read_ref_pic_list_modification_flag(:ref_pic_list_modification_flag_l1)
    end)
    {result, rest, bitOffset}
  end

  defp read_ref_pic_list_modification_flag(args, key) do
    args |> BitReader.bit_read_u(key, 1)
          |> BitReader.bit_cond_read(BitReader.is_result_value_equal?(key, 1), fn args ->
            args |> BitReader.bit_read_do_while(fn result -> result[:modification_of_pic_nums_idc] != 3 end, fn args ->
              args |> BitReader.bit_read_ue_v(:modification_of_pic_nums_idc)
                    |> BitReader.bit_func_read(fn args ->
                      {result, _r, _b} = args
                      modification_of_pic_nums_idc = result[:modification_of_pic_nums_idc]
                      cond do
                        (modification_of_pic_nums_idc == 0) or (modification_of_pic_nums_idc == 1) ->
                          args |> BitReader.bit_read_ue_v(:abs_diff_pic_num_minus1)
                        modification_of_pic_nums_idc == 2 ->
                          args |> BitReader.bit_read_ue_v(:long_term_pic_num)
                        true ->
                          args
                      end
                    end)
            end)
          end)
  end

  defp read_pred_weight_table(args) do
    {result, _r, _b} = args
    chromaArrayType = result[:chromaArrayType]
    slice_type = result[:slice_type]
    num_ref_idx_l0_active_minus1 = result[:num_ref_idx_l0_active_minus1]
    num_ref_idx_l1_active_minus1 = result[:num_ref_idx_l1_active_minus1]

    args |> BitReader.bit_read_ue_v(:luma_log2_weight_denom)
          |> BitReader.bit_cond_read(fn _r -> chromaArrayType != 0 end, fn args ->
            args |> BitReader.bit_read_ue_v(:chroma_log2_weight_denom)
          end)
          |> BitReader.bit_func_read(fn args ->
            {values, rest, bitOffset} = read_num_ref_idx(args, 0, num_ref_idx_l0_active_minus1, chromaArrayType)
            {result, _r, _b} = args
            keys = [:luma_weight_l0, :luma_offset_l0, :chroma_weight_l0, :chroma_weight_l0]
            result = Enum.zip_reduce(keys, values, result, fn (x, y, acc) -> Map.put(acc, x, y) end)
            {result, rest, bitOffset}
          end)
          |> BitReader.bit_cond_read(fn _r -> rem(slice_type, 5) == 1 end, fn args ->
            args |> BitReader.bit_func_read(fn args ->
              {values, rest, bitOffset} = read_num_ref_idx(args, 0, num_ref_idx_l1_active_minus1, chromaArrayType)
              {result, _r, _b} = args
              keys = [:luma_weight_l1, :luma_offset_l1, :chroma_weight_l1, :chroma_weight_l1]
              result = Enum.zip_reduce(keys, values, result, fn (x, y, acc) -> Map.put(acc, x, y) end)
              {result, rest, bitOffset}
            end)
          end)
  end

  defp read_num_ref_idx({result, rest, bitOffset}, index, repeatCount, chromaArrayType) do
    cond do
      index <= repeatCount ->
        {luma_weight_l0_flag, rest, bitOffset} = BitReader.read_u(rest, bitOffset, 1)
        {luma_weight, luma_offset, rest, bitOffset} = if luma_weight_l0_flag == 1 do
          {weight, rest, bitOffset} = BitReader.read_se_v(rest, bitOffset)
          {offset, rest, bitOffset} = BitReader.read_se_v(rest, bitOffset)
          {weight, offset, rest, bitOffset}
        else
          {0, 0, rest, bitOffset}
        end

        {chroma_weight, chroma_offset, rest, bitOffset} = if chromaArrayType != 0 do
          {chroma_weight_l0_flag, rest, bitOffset} = BitReader.read_u(rest, bitOffset, 1)
          {chroma_weight, chroma_offset, rest, bitOffset} = if chroma_weight_l0_flag == 1 do
            {weight1, rest, bitOffset} = BitReader.read_se_v(rest, bitOffset)
            {offset1, rest, bitOffset} = BitReader.read_se_v(rest, bitOffset)
            {weight2, rest, bitOffset} = BitReader.read_se_v(rest, bitOffset)
            {offset2, rest, bitOffset} = BitReader.read_se_v(rest, bitOffset)
            {[weight1, weight2], [offset1, offset2], rest, bitOffset}
          else
            {[0, 0], [0, 0], rest, bitOffset}
          end
          {chroma_weight, chroma_offset, rest, bitOffset}
        else
          {[0, 0], [0, 0], rest, bitOffset}
        end
        {value, rest, bitOffset} = read_num_ref_idx({result, rest, bitOffset}, index+1, repeatCount, chromaArrayType)
        new_row = [luma_weight, luma_offset, chroma_weight, chroma_offset]
        value = Enum.zip_with([new_row, value], fn [x, y] -> [x | y] end)
        {value, rest, bitOffset}
      true ->
        {[[], [], [], []], rest, bitOffset}
    end
  end

  defp read_dec_ref_pic_marking({result, rest, bitOffset}, idrPicFlag) do
    {result, rest, bitOffset} |> BitReader.bit_cond_read(fn _r -> idrPicFlag == 1 end, fn args ->
      args |> BitReader.bit_read_u(:no_output_of_prior_pics_flag, 1)
            |> BitReader.bit_read_u(:long_term_reference_flag, 1)
    end, fn args ->
      args |> BitReader.bit_read_u(:adaptive_ref_pic_marking_mode_flag, 1)
            |> BitReader.bit_cond_read(BitReader.is_result_value_equal?(:adaptive_ref_pic_marking_mode_flag, 1), fn args ->
              args |> BitReader.bit_read_do_while(fn r -> r[:memory_management_control_operation] != 0 end, fn args ->
                args |> BitReader.bit_read_ue_v(:memory_management_control_operation)
                      |> BitReader.bit_func_read(fn args ->
                        {result, _r, _b} = args
                        operation = result[:memory_management_control_operation]
                        cond do
                          operation == 1 or operation == 3 ->
                            args |> BitReader.bit_read_ue_v(:difference_of_pic_nums_minus1)
                          operation == 2 ->
                            args |> BitReader.bit_read_ue_v(:long_term_pic_num)
                          operation == 3 or operation == 6 ->
                            args |> BitReader.bit_read_ue_v(:long_term_frame_idx)
                          operation == 4 ->
                            args |> BitReader.bit_read_ue_v(:max_long_term_frame_idx_plus1)
                          true ->
                            args
                        end
                      end)
              end)
            end)
    end)
  end
end
