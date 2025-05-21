defmodule TCPFilter.SSLSocket do
  @behaviour TCPFilter.Socket

  def listen(port, options) do
    :ssl.listen(port, options)
  end

  def accept(socket) do
    case :ssl.transport_accept(socket) do
      {:ok, transport_socket} = res ->
        opts = case :ssl.peername(transport_socket) do
          {:ok, {peer_ip, _port}} ->
            get_ssl_server_options(peer_ip)
          {:error, reason} ->
            exit({:no_peername, reason})
        end
        :ssl.handshake(
          transport_socket,
          [{:active, false}, {:packet, 4} | opts],
          :net_kernel.connecttime()
        )
        res
      other ->
        other
    end
  end

  def connect(ip, port, options) do
    :ssl.connect(ip, port, options ++ get_ssl_client_options())
  end

  def close(socket) do
    :ssl.close(socket)
  end

  def send(socket, data) do
    :ssl.send(socket, data)
  end

  def recv(socket, length, timeout) do
    :ssl.recv(socket, length, timeout)
  end

  def controlling_process(socket, pid) do
    :ssl.controlling_process(socket, pid)
  end

  def sockname(socket) do
    :ssl.sockname(socket)
  end

  def peername(socket) do
    :ssl.peername(socket)
  end

  def getopts(socket, opts) do
    :ssl.getopts(socket, opts)
  end

  def setopts(socket, opts) do
    :ssl.setopts(socket, opts)
  end

  def getstat(socket, opts) do
    :ssl.getstat(socket, opts)
  end

  # helpers
  defp get_ssl_client_options(), do: get_ssl_options(:client)

  defp get_ssl_server_options(peer_ip) when peer_ip != :undefined do
    setup_verify_client(get_ssl_options(:server), peer_ip)
  end

  defp setup_verify_client([opt | opts], peer_ip) do
    case opt do
      {:verify_fun, {verify_fun, _}} ->
        case &:inet_tls_dist.verify_client/3 do
          ^verify_fun ->
            if peer_ip == :undefined do
              setup_verify_client(opts, peer_ip)
            else
              {:ok, allowed} = :net_kernel.allowed()
              [{:verify_fun,
                {verify_fun, {allowed_hosts(allowed), peer_ip}}}
                | setup_verify_client(opts, :undefined)]
            end
          _ ->
            [opt | setup_verify_client(opts, peer_ip)]
        end
      _ ->
        [opt | setup_verify_client(opts, peer_ip)]
    end
  end
  defp setup_verify_client([], _peer_ip), do: []

  defp allowed_hosts(allowed),
    do: :lists.usort(allowed_node_hosts(allowed))

  defp allowed_node_hosts([]), do: []
  defp allowed_node_hosts([node | allowed]) do
    case :dist_util.split_node(node) do
      {:node, _, host} ->
        [host | allowed_node_hosts(allowed)]
      {:host, host} ->
        [host | allowed_node_hosts(allowed)]
      _ ->
        allowed_node_hosts(allowed)
    end
  end

  defp get_ssl_options(type) do
    [
      {:erl_dist, true} |
      case (
        case :init.get_argument(:ssl_dist_opt) do
          {:ok, args} ->
            ssl_options(type, :lists.append(args))
          _ ->
            []
        end
        ++
        try do
          :ets.lookup(:ssl_dist_opts, type)
        rescue
          _ ->
            []
        else
          [{^type, opts0}] ->
            opts0
          _ ->
            []
        end
      ) do
        [] ->
          []
        opts1 ->
          dist_defaults(opts1)
      end
    ]
  end

  defp dist_defaults(opts) do
    case :proplists.get_value(:versions, opts, :undefined) do
      :undefined ->
        [{:versions, [:"tlsv1.2"]} | opts]
      _ ->
        opts
    end
  end

  defp ssl_options(_type, []), do: []
  defp ssl_options(:client, ["client_" <> opt, value | t] = opts),
    do: ssl_options(:client, t, opts, opt, value)
  defp ssl_options(:server, ["server_" <> opt, value | t] = opts),
    do: ssl_options(:server, t, opts, opt, value)
  defp ssl_options(type, [_opt, _value | t]),
    do: ssl_options(type, t)

  defp ssl_options(type, t, opts, opt, value) do
    case ssl_option(type, opt) do
      :error ->
        :erlang.error(:malformed_ssl_dist_opt, [type, opts])
      fun ->
        [{:erlang.list_to_atom(opt), fun.(value)} | ssl_options(type, t)]
    end
  end

  defp ssl_option(:server, opt) do
    case opt do
      "dhfile" -> &listify/1
      "fail_if_no_peer_cert" -> &atomize/1
      _ -> ssl_option(:client, opt)
    end
  end

  defp ssl_option(:client, opt) do
    case opt do
      "certfile" -> &listify/1
        "cacertfile" -> &listify/1
        "keyfile" -> &listify/1
        "password" -> &listify/1
        "verify" -> &atomize/1
        "verify_fun" -> &verify_fun/1
        "crl_check" -> &atomize/1
        "crl_cache" -> &termify/1
        "reuse_sessions" -> &atomize/1
        "secure_renegotiate" -> &atomize/1
        "depth" -> &:erlang.list_to_integer/1
        "hibernate_after" -> &:erlang.list_to_integer/1
        "ciphers" ->
            # Allows just one cipher, for now (could be , separated)
            fn (val) -> [listify(val)] end
        "versions" ->
            # Allows just one version, for now (could be , separated)
            fn (val) -> [atomize(val)] end
        "ktls" -> &atomize/1
        _ -> :error
    end
  end

  defp listify(list) when is_list(list), do: list

  defp atomize(list) when is_list(list), do: :erlang.list_to_atom(list)
  defp atomize(atom) when is_atom(atom), do: atom

  defp termify(string) when is_list(string) do
    {:ok, tokens, _} = :erl_scan.string(string ++ ".")
    {:ok, term} = :erl_parse.parse_term(tokens)
    term
  end

  defp verify_fun(value) do
    case termify(value) do
      {mod, func, state} when is_atom(mod) and is_atom(func) ->
        fun = Function.capture(mod, func, 3)
        {fun, state}
      _ ->
        :erlang.error(:malformed_ssl_dist_opt, [value])
    end
  end
end
