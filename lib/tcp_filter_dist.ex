# https://www.erlang.org/doc/apps/erts/alt_dist.html
defmodule TCPFilter_dist do
  require TCPFilter_dist.Model.HandshakeData, as: HandshakeData

  defmacro shutdown(data),
    do:
      quote(
        do:
          :dist_util.shutdown(unquote(__CALLER__.module), unquote(__CALLER__.line), unquote(data))
      )

  # select this protocol based on the node name
  def select(node) do
    case split_node(Atom.to_charlist(node), ?@, []) do
      [_, host] ->
        case :inet.getaddr(host, :inet) do
          {:ok, _} ->
            true

          _ ->
            false
        end

      _ ->
        false
    end
  end

  defdelegate listen(name), to: TCPFilter_dist.Listen
  defdelegate accept(listen), to: TCPFilter_dist.Accept

  defdelegate accept_connection(accept_pid, dist_controller, my_node, allowed, setup_time),
    to: TCPFilter_dist.Accept

  defdelegate setup(node, type, my_node, long_or_short_names, setup_time),
    to: TCPFilter_dist.Setup

  # close a socket
  def close(socket) do
    TCPFilter.get_socket().close(socket)
  end

  def setopts(socket, opts) do
    TCPFilter.get_socket().setopts(socket, opts)
  end

  def getopts(socket, opts) do
    TCPFilter.get_socket().getopts(socket, opts)
  end

  # helpers

  def flush_controller(pid, socket) do
    receive do
      {:tcp, ^socket, data} ->
        send(pid, {:tcp, socket, data})
        flush_controller(pid, socket)

      {:tcp_closed, socket} ->
        send(pid, {:tcp_closed, socket})
        flush_controller(pid, socket)
    after
      0 ->
        :ok
    end
  end

  def hs_data_common(dist_controller) do
    tick_handler = TCPFilter_dist.Controller.call(dist_controller, :tick_handler)
    socket = TCPFilter_dist.Controller.call(dist_controller, :socket)

    reject_flags =
      case :init.get_argument(:gen_tcp_dist_reject_flags) do
        {:ok, [[flags]]} -> :erlang.list_to_integer(flags)
        _ -> HandshakeData.hs_data(HandshakeData.hs_data(), :reject_flags)
      end

    HandshakeData.hs_data(
      f_send: fn controller, packet ->
        TCPFilter_dist.Controller.call(controller, {:send, packet})
      end,
      f_recv: fn controller, length, timeout ->
        case TCPFilter_dist.Controller.call(controller, {:recv, length, timeout}) do
          {:ok, bin} when is_binary(bin) ->
            {:ok, :erlang.binary_to_list(bin)}

          other ->
            other
        end
      end,
      f_setopts_pre_nodeup: fn controller ->
        TCPFilter_dist.Controller.call(controller, :pre_nodeup)
      end,
      f_setopts_post_nodeup: fn controller ->
        TCPFilter_dist.Controller.call(controller, :post_nodeup)
      end,
      f_getll: fn controller ->
        TCPFilter_dist.Controller.call(controller, :getll)
      end,
      f_handshake_complete: fn controller, node, d_handle ->
        TCPFilter_dist.Controller.call(controller, {:handshake_complete, node, d_handle})
      end,
      f_address: fn controller, node ->
        case TCPFilter_dist.Controller.call(controller, {:address, node}) do
          # No '@' or more than one '@' in node name.
          {:error, :no_node} ->
            shutdown(:no_node)

          res ->
            res
        end
      end,
      mf_setopts: fn controller, opts when controller == dist_controller ->
        setopts(socket, opts)
      end,
      mf_getopts: fn controller, opts when controller == dist_controller ->
        getopts(socket, opts)
      end,
      mf_getstat: fn controller when controller == dist_controller ->
        case TCPFilter.get_socket().getstat(socket, [:recv_cnt, :send_cnt, :send_pend]) do
          {:ok, stat} ->
            split_stat(stat, 0, 0, 0)

          error ->
            error
        end
      end,
      mf_tick: fn controller when controller == dist_controller ->
        send(tick_handler, :tick)
      end,
      # disable atom cache to simplify message decoding logic
      reject_flags:
        if reject_flags == :undefined do
          0x2000
        else
          Bitwise.bor(reject_flags, 0x2000)
        end
    )
  end

  defp split_stat([{:recv_cnt, r} | stat], _, w, p),
    do: split_stat(stat, r, w, p)

  defp split_stat([{:send_cnt, w} | stat], r, _, p),
    do: split_stat(stat, r, w, p)

  defp split_stat([{:send_pend, p} | stat], r, w, _),
    do: split_stat(stat, r, w, p)

  defp split_stat([], r, w, p),
    do: {:ok, r, w, p}

  def split_node(node, long_or_short_names) do
    case split_node(Atom.to_charlist(node), ?@, []) do
      [name | tail] when tail != [] ->
        host = :lists.append(tail)

        case split_node(host, ?., []) do
          [_] when long_or_short_names === :longnames ->
            case :inet.parse_address(host) do
              {:ok, _} ->
                [name, host]

              _ ->
                :error_logger.error_msg(
                  ~c"""
                  ** System running to use fully qualified hostnames **
                  ** Hostname ~ts is illegal **~n
                  """,
                  [host]
                )

                shutdown(node)
            end

          _ when length(host) > 1 and long_or_short_names === :shortnames ->
            :error_logger.error_msg(
              ~c"""
              ** System NOT running to use fully qualified hostnames **
              ** Hostname ~ts is illegal **~n
              """,
              [host]
            )

            shutdown(node)

          _ ->
            [name, host]
        end

      [_] ->
        :error_logger.error_msg(~c"** Nodename ~p illegal, no '@' character **~n", [node])
        shutdown(node)

      _ ->
        :error_logger.error_msg(~c"** Nodename ~p illegal **~n", [node])
        shutdown(node)
    end
  end

  def split_node([chr | t], chr, ack), do: [:lists.reverse(ack) | split_node(t, chr, [])]
  def split_node([h | t], chr, ack), do: split_node(t, chr, [h | ack])
  def split_node([], _, ack), do: [:lists.reverse(ack)]
end
