defmodule TCPFilter_dist.Accept do
  require TCPFilter_dist.Model.HandshakeData, as: HandshakeData
  import TCPFilter_dist, only: [shutdown: 1, flush_controller: 2, hs_data_common: 1]

  # accepts new connections from other Erlang nodes
  def accept(listen) do
    Process.spawn(__MODULE__, :accept_loop, [self(), listen], [:link, {:priority, :max}])
  end

  def accept_loop(kernel, listen) do
    case :gen_tcp.accept(listen) do
      {:ok, socket} ->
        dist_controller = TCPFilter_dist.Controller.spawn(socket)
        flush_controller(dist_controller, socket)
        :gen_tcp.controlling_process(socket, dist_controller)
        flush_controller(dist_controller, socket)
        send(kernel, {:accept, self(), dist_controller, :inet, :tcp})

        receive do
          {^kernel, :controller, pid} ->
            TCPFilter_dist.Controller.call(dist_controller, {:supervisor, pid})
            send(pid, {self(), :controller})

          {^kernel, :unsupported_protocol} ->
            exit(:unsupported_protocol)
        end

        accept_loop(kernel, listen)

      error ->
        exit(error)
    end
  end

  # accepts a new connection attempt from another Erlang node
  # performs the handshake with the other side
  def accept_connection(accept_pid, dist_controller, my_node, allowed, setup_time) do
    Process.spawn(
      __MODULE__,
      :do_accept,
      [self(), accept_pid, dist_controller, my_node, allowed, setup_time],
      :dist_util.net_ticker_spawn_options()
    )
  end

  def do_accept(kernel, accept_pid, dist_controller, my_node, allowed, setup_time) do
    receive do
      {^accept_pid, :controller} ->
        timer = :dist_util.start_timer(setup_time)

        case check_ip(dist_controller) do
          true ->
            hs_data =
              HandshakeData.hs_data(
                hs_data_common(dist_controller),
                kernel_pid: kernel,
                this_node: my_node,
                socket: dist_controller,
                timer: timer,
                this_flags: 0,
                allowed: allowed
              )

            :dist_util.handshake_other_started(hs_data)

          {false, ip} ->
            :error_logger.error_msg(~c"** Connection attempt from disallowed IP ~w ** ~n", [ip])
            shutdown(:nonode)
        end
    end
  end

  defp check_ip(dist_controller) do
    case Application.get_env(Application.get_application(__MODULE__), :check_ip) do
      {:ok, true} ->
        case get_ifs(dist_controller) do
          {:ok, ifs, ip} ->
            check_ip(ifs, ip)

          _ ->
            shutdown(:no_node)
        end

      _ ->
        true
    end
  end

  defp get_ifs(dist_controller) do
    socket = TCPFilter_dist.Controller.call(dist_controller, :socket)

    case :inet.peername(socket) do
      {:ok, {ip, _}} ->
        case :inet.getif(socket) do
          {:ok, ifs} ->
            {:ok, ifs, ip}

          error ->
            error
        end

      error ->
        error
    end
  end

  defp check_ip([{own_ip, _, net_mask} | ifs], peer_ip) do
    case {
      :inet_tcp.mask(net_mask, peer_ip),
      :inet_tcp.mask(net_mask, own_ip)
    } do
      {m, m} -> true
      _ -> check_ip(ifs, peer_ip)
    end
  end

  defp check_ip([], peer_ip),
    do: {false, peer_ip}
end
