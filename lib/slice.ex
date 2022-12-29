
defmodule H264.Decoder.Slice do
  @moduledoc """
    parse Slice
  """
  require Logger
  alias H264.Decoder.BitReader

  def parse_single(data, bitOffset) do
    rest = data
    data_size = byte_size(data)
    ss = if data_size > 25, do: 25, else: data_size
    <<h::binary-size(ss), _rest::binary>> = data
    IO.inspect(h, base: :binary)
    IO.inspect(h)
    # IO.puts(h)
    defaultResult = %{
    }

    {result, rest, bitOffset} = {defaultResult, rest, bitOffset} |> parse_header()
      |> parse_data()

  end

  defp parse_header({result, rest, bitOffset}) do
    {result, rest, bitOffset} = {result, rest, bitOffset} |> BitReader.bit_read_ue_v(:first_mb_in_slice)
      |> BitReader.bit_read_ue_v(:slice_type)

    IO.inspect(result)
    Logger.info("slice header rest data: #{byte_size(rest)}, offset: #{bitOffset}")
    IO.inspect(rest, base: :binary)
    {result, rest, bitOffset}
  end

  defp parse_data({result, rest, bitOffset}) do
     {result, rest, bitOffset} = {result, rest, bitOffset} |> BitReader.align_byte()

    IO.inspect(result)
    Logger.info("slice data rest data: #{byte_size(rest)}, offset: #{bitOffset}")
    IO.inspect(rest, base: :binary)
    {result, rest, bitOffset}
  end
end
