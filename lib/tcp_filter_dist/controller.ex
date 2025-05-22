# Distribution controller processes
defmodule TCPFilter_dist.Controller do
  require TCPFilter_dist.Model.NetAddress, as: NetAddress

  # gen_tcp socket - connection to other node
  # output handler - routes traffic from the VM to gen_tcp
  # input handler - routes traffic from gen_tcp to the VM
  # tick handler - sends async tick requests to gen_tcp
  # dist_util channel supervisor - monitors traffic, issues tick requests, kills connections

  # filtering happens in `input_loop/3`

  @common_spawn_opts [
    {:message_queue_data, :off_heap},
    {:fullsweep_after, 0}
  ]

  # number of pending inputs allowed
  @active_input 10

  def spawn(socket) do
    Process.spawn(
      __MODULE__,
      :setup,
      [socket],
      [{:priority, :max}] ++ @common_spawn_opts
    )
  end

  def setup(socket) do
    tick_handler =
      Process.spawn(
        __MODULE__,
        :tick_handler,
        [socket],
        [:link, {:priority, :max}] ++ @common_spawn_opts
      )

    setup_loop(socket, tick_handler, :undefined)
  end

  def tick_handler(socket) do
    receive do
      :tick ->
        sock_send(socket, "")

      _ ->
        :ok
    end

    tick_handler(socket)
  end

  defp setup_loop({socket_mod, socket} = socket_tuple, tick_handler, supervisor) do
    receive do
      {:tcp_closed, ^socket} ->
        exit(:connection_closed)

      {ref, from, {:supervisor, pid}} ->
        res = Process.link(pid)
        send(from, {ref, res})
        setup_loop(socket_tuple, tick_handler, pid)

      {ref, from, :tick_handler} ->
        send(from, {ref, tick_handler})
        setup_loop(socket_tuple, tick_handler, supervisor)

      {ref, from, :socket} ->
        send(from, {ref, socket_tuple})
        setup_loop(socket_tuple, tick_handler, supervisor)

      {ref, from, {:send, packet}} ->
        res = socket_mod.send(socket, packet)
        send(from, {ref, res})
        setup_loop(socket_tuple, tick_handler, supervisor)

      {ref, from, {:recv, length, timeout}} ->
        res = socket_mod.recv(socket, length, timeout)
        send(from, {ref, res})
        setup_loop(socket_tuple, tick_handler, supervisor)

      {ref, from, :getll} ->
        send(from, {ref, {:ok, self()}})
        setup_loop(socket_tuple, tick_handler, supervisor)

      {ref, from, {:address, node}} ->
        res =
          case socket_mod.peername(socket) do
            {:ok, address} ->
              case TCPFilter_dist.split_node(Atom.to_charlist(node), ?@, []) do
                [_, host] ->
                  NetAddress.net_address(
                    address: address,
                    host: host,
                    family: socket_mod.family(),
                    protocol: socket_mod.protocol()
                  )

                _ ->
                  {:error, :no_node}
              end
          end

        send(from, {ref, res})
        setup_loop(socket_tuple, tick_handler, supervisor)

      {ref, from, :pre_nodeup} ->
        res =
          socket_mod.setopts(
            socket,
            [{:active, false}, {:packet, 4}, nodelay()]
          )

        send(from, {ref, res})
        setup_loop(socket_tuple, tick_handler, supervisor)

      {ref, from, :post_nodeup} ->
        res =
          socket_mod.setopts(
            socket,
            [{:active, false}, {:packet, 4}, nodelay()]
          )

        send(from, {ref, res})
        setup_loop(socket_tuple, tick_handler, supervisor)

      {ref, from, {:handshake_complete, _node, d_handle}} ->
        send(from, {ref, :ok})

        input_handler =
          Process.spawn(
            __MODULE__,
            :input_setup,
            [d_handle, socket_tuple, supervisor],
            [:link] ++ @common_spawn_opts
          )

        TCPFilter_dist.flush_controller(input_handler, socket_tuple)
        socket_mod.controlling_process(socket, input_handler)
        TCPFilter_dist.flush_controller(input_handler, socket_tuple)

        :ok = :erlang.dist_ctrl_input_handler(d_handle, input_handler)

        send(input_handler, d_handle)

        Process.flag(:priority, :normal)
        :erlang.dist_ctrl_get_data_notification(d_handle)

        output_loop(d_handle, socket_tuple)
    end
  end

  defp output_loop(d_handle, socket) do
    receive do
      :dist_data ->
        # outgoing data from this node
        try do
          send_data(d_handle, socket)
        catch
          _, _ -> death_row()
        end

        output_loop(d_handle, socket)

      {:send, from, ref, data} ->
        # testing only
        sock_send(socket, data)
        send(from, {ref, :ok})
        output_loop(d_handle, socket)

      _ ->
        # drop garbage
        output_loop(d_handle, socket)
    end
  end

  def input_setup(d_handle, socket, supervisor) do
    Process.link(supervisor)

    receive do
      ^d_handle ->
        input_loop(d_handle, socket, 0)
    end
  end

  defp input_loop(d_handle, {socket_mod, socket} = socket_tuple, n) when n <= @active_input / 2 do
    socket_mod.setopts(socket, [{:active, @active_input - n}])
    input_loop(d_handle, socket_tuple, @active_input)
  end

  defp input_loop(d_handle, {socket_mod, socket} = socket_tuple, n) do
    receive do
      msg ->
        case socket_mod.handle_input(socket, msg) do
          {:error, :closed} ->
            exit(:connection_closed)
          {:data, data} ->
            # incoming data from remote node
            case TCPFilter.decode(data) do
              {:ok, safe_message} ->
                filter_res = TCPFilter.filter(safe_message)
                case filter_res do
                  :ok ->
                    try do
                      :erlang.dist_ctrl_put_data(d_handle, data)
                    catch
                      _, _ -> death_row()
                    end

                  :ignore ->
                    case safe_message do
                      {control_message, nil} ->
                        :error_logger.warning_msg(~c"** Ignored message ~p **~n", [control_message])

                      {control_message, message} ->
                        :error_logger.warning_msg(~c"** Ignored message ~p: ~p **~n", [
                          control_message,
                          message
                        ])
                    end

                  {:error, reason} ->
                    :error_logger.error_msg(~c"** Ignored message **~n** Reason: ~p **~n", [reason])

                  {:rewrite, rewritten} ->
                    <<131, encoded_data::binary>> = :erlang.term_to_binary(rewritten)
                    :erlang.dist_ctrl_put_data(d_handle, <<131, 68, 0>> <> encoded_data)
                end
              {:error, reason} ->
                :error_logger.error_msg(~c"** Ignored message **~n** Reason: ~p **~n", [reason])
            end

            input_loop(d_handle, socket_tuple, n - 1)
          _ ->
            # ignore
            input_loop(d_handle, socket_tuple, n)
        end
    end
  end

  defp send_data(d_handle, socket) do
    case :erlang.dist_ctrl_get_data(d_handle) do
      :none ->
        :erlang.dist_ctrl_get_data_notification(d_handle)

      data ->
        sock_send(socket, data)
        send_data(d_handle, socket)
    end
  end

  defp sock_send({socket_mod, socket}, data) do
    try do
      socket_mod.send(socket, data)
    catch
      type, reason -> death_row({:send_error, {type, reason}})
    else
      :ok -> :ok
      {:error, reason} -> death_row({:send_error, reason})
    end
  end

  defp death_row(), do: death_row(:connection_closed)
  defp death_row(:normal), do: death_row()

  defp death_row(reason) do
    receive do
    after
      5000 -> exit(reason)
    end
  end

  defp nodelay() do
    case Application.get_env(:kernel, :dist_nodelay) do
      :undefined ->
        {:nodelay, true}

      {:ok, true} ->
        {:nodelay, true}

      {:ok, false} ->
        {:nodelay, false}

      _ ->
        {:nodelay, true}
    end
  end

  def call(controller, message) do
    ref = :erlang.monitor(:process, controller)
    send(controller, {ref, self(), message})

    receive do
      {^ref, res} ->
        :erlang.demonitor(ref, [:flush])
        res

      {:DOWN, ^ref, :process, ^controller, reason} ->
        exit({:dist_controller_exit, reason})
    end
  end
end
