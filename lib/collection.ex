
defmodule H264.Decoder.Collection do

  def new_matrix(row, column, value), do: for _r <- 1..row, do: new_list(column, value)

  def new_list(0, _value), do: []
  def new_list(n, value), do: [value] ++ new_list(n-1, value)

end
