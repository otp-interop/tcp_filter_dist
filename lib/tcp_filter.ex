defmodule TCPFilter do
  use GenServer

  def init(state), do: {:ok, state}

  def start_link(opts) do
    GenServer.start_link(
      __MODULE__,
      %{
        filter: Keyword.get(opts, :filter),
        socket: Keyword.get(opts, :socket, TCPFilter.TCPSocket),
      },
      opts
    )
  end

  def handle_call({:set_filter, filter}, _from, %{ filter: old_filter } = state) do
    {:reply, old_filter, Map.put(state, :filter, filter)}
  end

  def handle_call(:get_filter, _from, %{ filter: filter } = state) do
    {:reply, filter, state}
  end

  def handle_call({:set_socket, socket}, _from, %{ socket: old_socket } = state) do
    {:reply, old_socket, Map.put(state, :socket, socket)}
  end

  def handle_call(:get_socket, _from, %{ socket: socket } = state) do
    {:reply, socket, state}
  end

  def set_filter(filter) do
    GenServer.call(__MODULE__, {:set_filter, filter})
  end

  def get_filter, do: GenServer.call(__MODULE__, :get_filter)

  def set_socket(socket) do
    GenServer.call(__MODULE__, {:set_socket, socket})
  end

  def get_socket, do: GenServer.call(__MODULE__, :get_socket)

  def filter(:tick), do: :ok

  def filter({control_message, nil}) do
    case get_filter() do
      nil ->
        :ok
      filter_mod ->
        filter_mod.filter(control_message)
    end
  end

  def filter({control_message, message}) do
    case get_filter() do
      nil ->
        :ok
      filter_mod ->
        filter_mod.filter(control_message, message)
    end
  end

  @version 131
  @distribution_header 68
  def decode(""),
    do: {:ok, :tick}

  # non-fragmented messages with distribution header and a 0 atom cache
  def decode(<<@version, @distribution_header, 0, rest::binary>>) do
    try do
      message = <<@version>> <> rest

      {control_message, used} = :erlang.binary_to_term(message, [:safe, :used])

      control_message =
        :erlang.setelement(1, control_message, control_message_type(elem(control_message, 0)))

      <<_used::binary-size(used), message::binary>> = message

      case message do
        <<>> ->
          {:ok, {control_message, nil}}

        message ->
          {:ok, {control_message, :erlang.binary_to_term(<<@version>> <> message, [:safe])}}
      end
    rescue
      _ ->
        {:error, :unsafe}
    end
  end

  defp control_message_type(1), do: :link
  defp control_message_type(2), do: :send
  defp control_message_type(3), do: :exit
  defp control_message_type(4), do: :unlink
  defp control_message_type(5), do: :node_link
  defp control_message_type(6), do: :reg_send
  defp control_message_type(7), do: :group_leader
  defp control_message_type(8), do: :exit2
  defp control_message_type(12), do: :send_tt
  defp control_message_type(13), do: :exit_tt
  defp control_message_type(16), do: :reg_send_tt
  defp control_message_type(18), do: :exit2_tt
  defp control_message_type(19), do: :monitor_p
  defp control_message_type(20), do: :demonitor_p
  defp control_message_type(21), do: :monitor_p_exit
  defp control_message_type(22), do: :send_sender
  defp control_message_type(23), do: :send_sender_tt
  defp control_message_type(24), do: :payload_exit
  defp control_message_type(25), do: :payload_exit_tt
  defp control_message_type(26), do: :payload_exit2
  defp control_message_type(27), do: :payload_exit2_tt
  defp control_message_type(28), do: :payload_monitor_p_exit
  defp control_message_type(29), do: :spawn_request
  defp control_message_type(30), do: :spawn_request_tt
  defp control_message_type(31), do: :spawn_reply
  defp control_message_type(32), do: :spawn_reply_tt
  defp control_message_type(35), do: :unlink_id
  defp control_message_type(36), do: :unlink_id_ack
  defp control_message_type(33), do: :alias_send
  defp control_message_type(34), do: :alias_send_tt
  defp control_message_type(other), do: other
end
