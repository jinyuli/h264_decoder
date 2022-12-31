# H264 Decoder

## Introduction

This is a H264 decoder. The project is in initial stage.

Now it's able to read the following NAL unit from H264 file:
  * 1: Code slice of a non-IDR picture
  * 7: Seq parameter set
  * 8: Pic parameter set

Now I'm looking for a way to validate the parsed data.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `vod_server` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:vod_server, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/vod_server>.

