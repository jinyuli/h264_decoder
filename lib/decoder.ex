

defmodule H264.Decoder do
  require Logger
  alias H264.Decoder.Nal

  def read do
    read_head("D:\\Projects\\elixir_projects\\videos\\test_10s.h264")
  end

  def read_head(file_name) do
    case File.read(file_name) do
      {:ok, video} ->
        IO.puts("video size #{byte_size(video)}")
        #<<head::binary-size(50), _ :: binary>> = video
        # IO.puts(head)
        #IO.inspect(head, base: :binary)
        # IO.puts("total is binary? #{is_binary(video)}, is bitstring? #{is_bitstring(video)}")
        # IO.puts("sub is binary? #{is_binary(head)}, is bitstring? #{is_bitstring(head)}")
        # <<first::8-integer, second::8-integer, rest:: binary>> = head
        # IO.inspect(rest, base: :binary)
        # IO.puts("first is binary? #{is_binary(first)}, is bitstring? #{is_bitstring(first)}, is number? #{is_number(first)}")
        # IO.puts("second is binary? #{is_binary(second)}, is bitstring? #{is_bitstring(second)}, is number? #{is_number(second)}")
        # IO.puts("#{first}, #{first==0}")

        # <<firstA::binary-size(1), secondA::binary-size(1), rest:: binary>> = head
        # IO.inspect(rest, base: :binary)
        # IO.puts("firstA is binary? #{is_binary(firstA)}, is bitstring? #{is_bitstring(firstA)}, is number? #{is_number(firstA)}")
        # IO.puts("secondA is binary? #{is_binary(secondA)}, is bitstring? #{is_bitstring(secondA)}, is number? #{is_number(secondA)}")

        Nal.parse(video)
        # IO.puts("nal unit size #{byte_size(nalUnit)}")
        # IO.inspect(nalUnit, base: :binary)
      {:error, reason} ->
        IO.puts("failed to open file with #{reason}")
    end
  end

end
