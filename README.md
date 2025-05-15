# tcp_filter_dist

Filter messages sent over Erlang distribution.

Use the `-proto_dist` flag to set the module to use for distribution:

```sh
iex --erl "-proto_dist Elixir.TCPFilter" -S mix
```

Then start your node:

```elixir
Node.start(:"server@127.0.0.1")
```

Create a filter module that will intercept data coming into the node:

```elixir
defmodule MyApp.Filter do
  @behaviour TCPFilter.Filter

  # allow genserver calls to `:increment`
  def filter({:reg_send, _sender, _unused, MyApp.MyGenServer}, {:"$gen_call", _, :increment}),
    do: :ok
  
  # block other messages to the genserver
  def filter({:reg_send, _sender, _unused, MyApp.MyGenServer}, _msg),
    do: {:error, :unauthorized}
  
  # ignore other message types
  def filter(_control_message, _message), do: :ignore
  def filter(_control_message), do: :ignore
end
```

Set the filter to use with `TCPFilter.set_filter/2`:

```elixir
TCPFilter.set_filter(MyApp.Filter)
```

You can also set this filter when starting the `TCPFilter` in your supervisor:

```elixir
{TCPFilter, filter: MyApp.Filter, name: TCPFilter}
```

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `tcp_filter_dist` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:tcp_filter_dist, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/tcp_filter_dist>.

