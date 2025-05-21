defmodule TCPFilter_dist.Listen do
  require TCPFilter_dist.Model.NetAddress, as: NetAddress

  # create the listen socket, the port that this Erlang node is accessible through
  def listen(name) do
    socket_mod = TCPFilter.get_socket()
    case do_listen(socket_mod, [:binary, {:active, false}, {:packet, 2}, {:reuseaddr, true}]) do
      {:ok, socket} ->
        tcp_address = get_tcp_address({socket_mod, socket})
        {_, port} = NetAddress.net_address(tcp_address, :address)
        erl_epmd = :net_kernel.epmd_module()

        case erl_epmd.register_node(name, port) do
          {:ok, creation} ->
            {:ok, {{socket_mod, socket}, tcp_address, creation}}

          error ->
            error
        end

      error ->
        error
    end
  end

  defp do_listen(socket_mod, options) do
    {first, last} =
      case Application.get_env(:kernel, :inet_dist_listen_min) do
        {:ok, n} when is_integer(n) ->
          case Application.get_env(:kernel, :inet_dist_listen_max) do
            {:ok, m} when is_integer(m) ->
              {n, m}

            _ ->
              {n, n}
          end

        _ ->
          {0, 0}
      end

    do_listen(socket_mod, first, last, listen_options([{:backlog, 128} | options]))
  end

  defp do_listen(_socket_mod, first, last, _) when first > last, do: {:error, :eaddrinuse}

  defp do_listen(socket_mod, first, last, options) do
    case socket_mod.listen(first, options) do
      {:error, :eaddrinuse} ->
        do_listen(socket_mod, first + 1, last, options)

      other ->
        other
    end
  end

  defp listen_options(opts0) do
    opts1 =
      case Application.get_env(:kernel, :inet_dist_use_interface) do
        {:ok, ip} ->
          [{:ip, ip} | opts0]

        _ ->
          opts0
      end

    case Application.get_env(:kernel, :inet_dist_listen_options) do
      {:ok, listen_opts} ->
        listen_opts ++ opts1

      _ ->
        opts1
    end
  end

  defp get_tcp_address({socket_mod, socket}) do
    {:ok, address} = socket_mod.sockname(socket)

    NetAddress.net_address(
      get_tcp_address(socket_mod),
      address: address
    )
  end

  defp get_tcp_address(socket_mod) do
    {:ok, host} = :inet.gethostname()

    NetAddress.net_address(
      host: host,
      family: socket_mod.family(),
      protocol: socket_mod.protocol()
    )
  end
end
