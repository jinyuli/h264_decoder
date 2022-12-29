
defmodule H264.Decoder.BitReader do

  import Bitwise
  require Logger

  @full_mask {0b11111111, 0b01111111, 0b00111111, 0b00011111, 0b00001111, 0b00000111, 0b00000011, 0b00000001}
  @position_mask {0b10000000, 0b01000000, 0b00100000, 0b00010000, 0b00001000, 0b00000100, 0b00000010, 0b00000001}

  ## is_xxx?

  def is_result_value_in?(key, list) do
    fn (result) ->
      v = result[key]
      Enum.any?(list, &(&1 == v))
    end
  end

  def is_result_value_greater_than?(key, expectedValue) do
    &(&1[key] > expectedValue)
  end

  def is_result_value_equal?(key, expectedValue) do
    &(&1[key] == expectedValue)
  end

  def has_more_rbsp_data?(data, bitOffset) do
    Logger.debug("has more rbsp data? #{byte_size(data)}, offset:#{bitOffset}")
    if byte_size(data) > 1 do
      true
    else
      <<out::unsigned-integer-size(8), _rest::binary>> = data
      bitOffset = bitOffset &&& 0x07
      offset = 7 - bitOffset
      # control bit for current bit posision
      ctr_bit = (out >>> offset) &&& 0x01
      if ctr_bit == 0 do
        true
      else
        # last bit is 1
        # ? is this a bug?
        # if offset the last bit, then 0xaaaaaaa1 represent no more data?
        # shouldn't we check next byte?
        if offset == 0 do
          false
        end
        value = out &&& elem(@full_mask, bitOffset+1)
        value > 0
      end
    end
  end

  ## helper funcs
  def align_byte({result, rest, bitOffset}) do
    if bitOffset == 0 do
      {result, rest, bitOffset}
    else
      <<_h, rest::binary>> = rest
      {result, rest, bitOffset}
    end
  end


  ## bit_read_xxx

  @doc """
    keys: should List [:name, ...]
    read_funcs: should be List [read_xxx, ...]
    keys and read_funcs should have the same size
  """
  def bit_repeat_multi_read({result, data, bitOffset}, keys, repeatCount, read_funcs) do
    {valuesList, rest, offset} = bit_repeat_multi_read_list({data, bitOffset}, repeatCount, read_funcs)
    listByKey = valuesList |> Enum.zip_with(&(&1))
    result = Enum.zip_reduce(keys, listByKey, result, fn (x, y, acc) -> Map.put(acc, x, y) end)
    {result, rest, offset}
  end

  defp bit_repeat_multi_read_list({data, bitOffset}, repeatCount, read_funcs) do
    case repeatCount do
      0 ->
        {[], data, bitOffset}
      _ ->
        # value is a list
        {value, rest, offset} = bit_multi_read({data, bitOffset}, read_funcs)
        {nextValue, rest, offset} = bit_repeat_multi_read_list({rest, offset}, repeatCount-1, read_funcs)
        {[value | nextValue], rest, offset}
    end
  end

  defp bit_multi_read({data, bitOffset}, []) do
    {[], data, bitOffset}
  end

  defp bit_multi_read({data, bitOffset}, read_funcs) do
    [head | tail] = read_funcs
    {value, rest, offset} = head.(data, bitOffset)
    {list, rest, offset} = bit_multi_read({rest, offset}, tail)
    {[value | list], rest, offset}
  end

  @doc """
    read_func: should be read_xxx/3
  """
  def bit_repeat_read_3({result, data, bitOffset}, key, len, repeatCount, read_func) do
    {value, rest, offset} = bit_repeat_read_list_3({data, bitOffset}, len, repeatCount, read_func)
    {Map.put(result, key, value), rest, offset}
  end

  defp bit_repeat_read_list_3({data, bitOffset}, len, repeatCount, read_func) do
    case repeatCount do
      0 ->
        {[], data, bitOffset}
      _ ->
        {value, rest, offset} = read_func.(data, bitOffset, len)
        {nextValue, rest, offset} = bit_repeat_read_list_3({rest, offset}, len, repeatCount-1, read_func)
        {[value | nextValue], rest, offset}
    end
  end

  @doc """
    read_func: should be read_xxx/2
  """
  def bit_repeat_read({result, data, bitOffset}, key, repeatCount, read_func) do
    {value, rest, offset} = bit_repeat_read_list({data, bitOffset}, repeatCount, read_func)
    {Map.put(result, key, value), rest, offset}
  end

  defp bit_repeat_read_list({data, bitOffset}, repeatCount, read_func) do
    case repeatCount do
      0 ->
        {[], data, bitOffset}
      _ ->
        {value, rest, offset} = read_func.(data, bitOffset)
        {nextValue, rest, offset} = bit_repeat_read_list({rest, offset}, repeatCount-1, read_func)
        {[value | nextValue], rest, offset}
    end
  end

  def bit_cond_read({result, data, bitOffset}, condFunc, read_func) do
    if condFunc.(result) do
      read_func.({result, data, bitOffset})
    else
      {result, data, bitOffset}
    end
  end

  def bit_func_read({result, data, bitOffset}, read_func) do
    read_func.({result, data, bitOffset})
  end

  def bit_read_u({result, data, bitOffset}, key, len) do
    read_with_args({result, data, bitOffset}, key, len, &read_u/3)
  end

  def bit_read_se_v({result, data, bitOffset}, key) do
    read_with_args({result, data, bitOffset}, key, &read_se_v/2)
  end

  def bit_read_ue_v({result, data, bitOffset}, key) do
    read_with_args({result, data, bitOffset}, key, &read_ue_v/2)
  end

  def read_with_args({result, data, bitOffset}, key, len, read_func) do
    {value, rest, bitOffset} = read_func.(data, bitOffset, len)
    {Map.put(result, key, value), rest, bitOffset}
  end

  def read_with_args({result, data, bitOffset}, key, read_func) do
    {value, rest, bitOffset} = read_func.(data, bitOffset)
    {Map.put(result, key, value), rest, bitOffset}
  end

  @doc """
    基于上下文自适应的二进制算术熵编码
  """
  def read_ae(data, v) do
    <<out::size(v), rest::binary>> = data
    {out, rest}
  end

  @doc """
    读进连续的8个比特
  """
  def read_b8(data) do
    read_b(data, 8)
  end

  @doc """
    读进连续的n个比特
  """
  def read_b(data, v) do
    <<out::size(v), rest::binary>> = data
    {out, rest}
  end

  @doc """
    基于上下文自适应的可变长熵编码
  """
  def read_ce(data, v) do
    <<out::size(v), rest::binary>> = data
    {out, rest}
  end

  @doc """
    读进连续的n个比特
  """
  def read_f(data, n) do
    <<out::size(n), rest::binary>> = data
    {out, rest}
  end

  @doc """
    读进连续的v个比特，并解释为有符号整数
  """
  def read_i(data, v) do
    <<out::integer-size(v), rest::binary>> = data
    {out, rest}
  end

  @doc """
    映射指数golomb熵编码
  """
  def read_me_v(data, bitOffset) do
    read_ue_v(data, bitOffset)
  end

  @doc """
    有符号指数golomb熵编码
  """
  def read_se_v(data, bitOffset) do
    Logger.info("read_se_v, offset: #{bitOffset}")
    {len, rest, bitOffset} = read_golomb_len(data, bitOffset)

    value = get_signed_golomb_value(rest, bitOffset, len)
    Logger.info("read_se_v, value: #{value}")

    byteLen = (bitOffset + len) >>> 0x03
    rest = if byteLen > 0 do
      <<_h::binary-size(byteLen), rest1::binary>> = rest
      rest1
    else
      rest
    end
    Logger.info("read_se_v, offset: #{bitOffset}, #{bitOffset + len}")
    bitOffset = (bitOffset + len) &&& 0x07

    {value, rest, bitOffset}
  end

  @doc """
    截断指数golomb熵编码
  """
  def read_te_v(data, bitOffset) do
    read_ue_v(data, bitOffset)
  end

  @doc """
    读进连续的v个比特，并解释为无符号整数
  """
  def read_u(data, bitOffset, v) do
    # Logger.info("read_u, offset: #{bitOffset}, v: #{v}")
    <<out::unsigned-integer-size(8), rest::binary>> = data
    bitOffset = bitOffset &&& 0x07
    # offset = 7 - bitOffset
    mask = elem(@full_mask, bitOffset)

    cur_byte_len = 8 - bitOffset
    if cur_byte_len >= v do
      bitOffset = (bitOffset + v) &&& 0x07
      value = (out &&& mask) >>> (cur_byte_len - v)
      if (cur_byte_len == v) do
        {value, rest, bitOffset}
      else
        {value, data, bitOffset}
      end
    else
      value = (out &&& mask)
      {nextValue, rest, newBitOffset} = read_u(data, 0, v - (8 - bitOffset))
      value = (value <<< (v - cur_byte_len)) ||| nextValue
      {value, rest, newBitOffset}
    end
  end

  @doc """
    无符号指数golomb熵编码
  """
  def read_ue_v(data, bitOffset) do
    # Logger.info("read_ue_v, offset: #{bitOffset}")
    # len = get_golomb_len(data, bitOffset) + 1
    # Logger.info("read_ue_v, len: #{len}")
    # byteLen = (bitOffset + len - 1) >>> 0x03
    # rest = data
    # bitOffset = (bitOffset + len - 1) &&& 0x07
    # if byteLen > 0 do
    #   <<_h::binary-size(byteLen), rest2::binary>> = rest
    #   ^rest = rest2
    # end
    {len, rest, bitOffset} = read_golomb_len(data, bitOffset)
    read_golomb_value(rest, bitOffset, len)
  end

  defp read_golomb_value(data, bitOffset, len) do
    rest = data
    value = get_golomb_value(rest, bitOffset, len) - 1
    # Logger.info("read_golomb_value, value: #{value}")

    byteLen = (bitOffset + len) >>> 0x03
    rest = if byteLen > 0 do
      <<_h::binary-size(byteLen), rest1::binary>> = rest
      rest1
    else
      rest
    end
    # if byteLen > 0 do
    #   <<_h::binary-size(byteLen), rest1::binary>> = rest
    #   ^rest = rest1
    # end
    # Logger.info("read_golomb_value, offset: #{bitOffset}, #{bitOffset + len}")
    bitOffset = (bitOffset + len) &&& 0x07

    {value, rest, bitOffset}
  end

  defp read_golomb_len(data, bitOffset) do
    # Logger.info("read_golomb_len, offset: #{bitOffset}")
    len = get_golomb_len(data, bitOffset) + 1
    # Logger.info("read_golomb_len, len: #{len}")
    byteLen = (bitOffset + len - 1) >>> 0x03
    rest = data
    bitOffset = (bitOffset + len - 1) &&& 0x07
    rest = if byteLen > 0 do
      <<_h::binary-size(byteLen), rest2::binary>> = rest
       rest2
    else
      rest
    end

    {len, rest, bitOffset}
  end

  @doc """
    make sure bitOffset is in [0..7]
  """
  defp get_golomb_value(data, bitOffset, len) do
    <<out, rest::binary>> = data
    bitOffset = bitOffset &&& 0x07
    offset = 7 - bitOffset
    cur_byte_len = offset + 1
    mask = elem(@full_mask, bitOffset)
    if cur_byte_len >= len do
      n = (out &&& mask) >>> (cur_byte_len - len)
      n
    else
      n = (out &&& mask)
      (n <<< (len - cur_byte_len)) ||| get_golomb_value(rest, 0, len - cur_byte_len)
    end
  end

  defp get_signed_golomb_value(data, bitOffset, len) do
    rest = data
    value = get_golomb_value(rest, bitOffset, len-1) - 1
    byteLen = (bitOffset + len-1) >>> 0x03
    rest = if byteLen > 0 do
      <<_h::binary-size(byteLen), rest1::binary>> = rest
      rest1
    else
      rest
    end
    bitOffset = (bitOffset + len) >>> 0x03
    <<out, _rest::binary>> = rest
    if test_binary_bit_0?(out, bitOffset) do
      value
    else
      value * -1
    end
  end

  defp get_signed_golomb_value_inner(data, bitOffset, len) do
    <<out, rest::binary>> = data
    bitOffset = bitOffset &&& 0x07
    offset = 7 - bitOffset
    cur_byte_len = offset + 1
    mask = elem(@full_mask, bitOffset)
    if cur_byte_len >= len do
      n = (out &&& mask) >>> (cur_byte_len - len)
      n
    else
      n = (out &&& mask)
      (n <<< (len - cur_byte_len)) ||| get_signed_golomb_value_inner(rest, 0, len - cur_byte_len)
    end
  end

  defp get_golomb_len(data, bitOffset) do
    # Logger.info("get_golomb_len, offset: #{bitOffset}")
    <<out, rest::binary>> = data
    # offset = 7 - rem(bitOffset, 8)
    len = count_binary_head_0(out, bitOffset)
    if len == (8 - bitOffset) do
      #read next byte
      len + get_golomb_len(rest, 0)
    else
      len
    end
  end

  defp count_binary_head_0(b, offset) do
    # Logger.info("count_binary_head_0, b: #{b} offset: #{offset}")
    if test_binary_bit_0?(b, offset) do
      if offset == 0x07 do
        1
      else
        1 + count_binary_head_0(b, offset+1)
      end
    else
      0
    end
  end

  defp test_binary_bit_0?(b, offset) do
    ((b >>> (7 - offset)) &&& 0x01) == 0
  end
end
