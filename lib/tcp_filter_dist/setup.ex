defmodule TCPFilter_dist.Setup do
  require TCPFilter_dist.Model.HandshakeData, as: HandshakeData
  import TCPFilter_dist, only: [shutdown: 1, flush_controller: 2, hs_data_common: 1]

  # setup a new connection to another Erlang node
  # performs the handshake with the other side
  def setup(node, type, my_node, long_or_short_names, setup_time) do
    socket_mod = TCPFilter.get_socket()
    Process.spawn(
      __MODULE__,
      :do_setup,
      [socket_mod, self(), node, type, my_node, long_or_short_names, setup_time],
      :dist_util.net_ticker_spawn_options()
    )
  end

  def do_setup(socket_mod, kernel, node, type, my_node, long_or_short_names, setup_time) do
    [name, address] = TCPFilter_dist.split_node(node, long_or_short_names)

    case :inet.getaddr(address, :inet) do
      {:ok, ip} ->
        timer = :dist_util.start_timer(setup_time)
        erl_epmd = :net_kernel.epmd_module()

        case erl_epmd.port_please(name, ip) do
          {:port, tcp_port, version} ->
            :dist_util.reset_timer(timer)

            case socket_mod.connect(
                   ip,
                   tcp_port,
                   connect_options([:binary, {:active, false}, {:packet, 2}])
                 ) do
              {:ok, socket} ->
                dist_controller = TCPFilter_dist.Controller.spawn({socket_mod, socket})
                TCPFilter_dist.Controller.call(dist_controller, {:supervisor, self()})
                flush_controller(dist_controller, {socket_mod, socket})
                socket_mod.controlling_process(socket, dist_controller)
                flush_controller(dist_controller, {socket_mod, socket})

                hs_data =
                  HandshakeData.hs_data(
                    hs_data_common(dist_controller),
                    kernel_pid: kernel,
                    other_node: node,
                    this_node: my_node,
                    socket: dist_controller,
                    timer: timer,
                    this_flags: 0,
                    other_version: version,
                    request_type: type
                  )

                :dist_util.handshake_we_started(hs_data)

              _ ->
                # other node may have closed since port_please
                shutdown(node)
            end

          _ ->
            shutdown(node)
        end

      _other ->
        shutdown(node)
    end
  end

  defp connect_options(opts) do
    case Application.get_env(:kernel, :inet_dist_connect_options) do
      {:ok, connect_opts} ->
        connect_opts ++ opts

      _ ->
        opts
    end
  end
end
