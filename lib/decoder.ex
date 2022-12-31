

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
        Nal.parse(video)
      {:error, reason} ->
        IO.puts("failed to open file with #{reason}")
    end
  end

end
