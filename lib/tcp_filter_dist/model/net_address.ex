defmodule TCPFilter_dist.Model.NetAddress do
  require Record

  Record.defrecord(
    :net_address,
    Record.extract(:net_address, from_lib: "kernel/include/net_address.hrl")
  )
end
