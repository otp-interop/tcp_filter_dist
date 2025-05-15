defmodule TCPFilter_dist.Model.HandshakeData do
  require Record
  Record.defrecord(:hs_data, Record.extract(:hs_data, from_lib: "kernel/include/dist_util.hrl"))
end
