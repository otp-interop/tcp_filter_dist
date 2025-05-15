defmodule TCPFilter_dist.Listen do
  require TCPFilter_dist.Model.NetAddress, as: NetAddress

  # create the listen socket, the port that this Erlang node is accessible through
  def listen(name) do
    case do_listen([:binary, {:active, false}, {:packet, 2}, {:reuseaddr, true}]) do
      {:ok, socket} ->
        tcp_address = get_tcp_address(socket)
        {_, port} = NetAddress.net_address(tcp_address, :address)
        erl_epmd = :net_kernel.epmd_module()

        case erl_epmd.register_node(name, port) do
          {:ok, creation} ->
            {:ok, {socket, tcp_address, creation}}

          error ->
            error
        end

      error ->
        error
    end
  end

  defp do_listen(options) do
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

    do_listen(first, last, listen_options([{:backlog, 128} | options]))
  end

  defp do_listen(first, last, _) when first > last, do: {:error, :eaddrinuse}

  defp do_listen(first, last, options) do
    case :gen_tcp.listen(first, options) do
      {:error, :eaddrinuse} ->
        do_listen(first + 1, last, options)

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

  defp get_tcp_address(socket) do
    {:ok, address} = :inet.sockname(socket)

    NetAddress.net_address(
      get_tcp_address(),
      address: address
    )
  end

  defp get_tcp_address() do
    {:ok, host} = :inet.gethostname()

    NetAddress.net_address(
      host: host,
      protocol: :tcp,
      family: :inet
    )
  end
end
