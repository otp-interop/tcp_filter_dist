defmodule TCPFilter.Filter do
  @doc """
  Filters messages sent over Erlang distribution.
  """

  @type filter_result() :: :ok | {:error, term} | :ignore

  @callback filter({:link, pid, pid}) :: filter_result
  @callback filter({:exit, pid, pid, term}) :: filter_result
  @callback filter({:unlink, pid, pid}) :: filter_result
  @callback filter({:node_link}) :: filter_result
  @callback filter({:group_leader, pid, pid}) :: filter_result
  @callback filter({:exit2, pid, pid, term}) :: filter_result
  @callback filter({:exit_tt, pid, pid, term, term}) :: filter_result
  @callback filter({:exit2_tt, pid, pid, term, term}) :: filter_result
  @callback filter({:monitor_p, pid, pid | atom, reference}) :: filter_result
  @callback filter({:demonitor_p, pid, pid | atom, reference}) :: filter_result
  @callback filter({:monitor_p_exit, pid | atom, pid, term}) :: filter_result
  @callback filter({:spawn_reply, reference, pid, integer, pid | atom}) :: filter_result
  @callback filter({:spawn_reply_tt, reference, pid, integer, pid | atom, term}) :: filter_result
  @callback filter({:unlink_id, reference, pid, pid}) :: filter_result
  @callback filter({:unlink_id_ack, reference, pid, pid}) :: filter_result

  @callback filter({:send, term, pid}, term) :: filter_result
  @callback filter({:reg_send, pid, term, atom}, term) :: filter_result
  @callback filter({:send_tt, term, pid, term}, term) :: filter_result
  @callback filter({:reg_send_tt, pid, term, atom, term}, term) :: filter_result
  @callback filter({:send_sender, pid, pid}, term) :: filter_result
  @callback filter({:send_sender_tt, pid, pid, term}, term) :: filter_result
  @callback filter({:payload_exit, pid, pid}, term) :: filter_result
  @callback filter({:payload_exit_tt, pid, pid, term}, term) :: filter_result
  @callback filter({:payload_exit2, pid, pid}, term) :: filter_result
  @callback filter({:payload_exit2_tt, pid, pid, term}, term) :: filter_result
  @callback filter({:payload_monitor_p_exit, pid | atom, pid, reference}, term) :: filter_result
  @callback filter({:spawn_request, reference, pid, pid, {atom, atom, integer}, [term]}, [term]) ::
              filter_result
  @callback filter(
              {:spawn_request_tt, reference, pid, pid, {atom, atom, integer}, [term], term},
              [term]
            ) :: filter_result
  @callback filter({:alias_send, pid, term}, term) :: filter_result
  @callback filter({:alias_send_tt, pid, term, term}, term) :: filter_result

  defmacro __using__(_opts) do
    quote do
      @before_compile TCPFilter.Filter
      @behaviour TCPFilter.Filter
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      @impl true
      def filter(_control_message, _message), do: :ignore
      @impl true
      def filter(_control_message), do: :ignore
    end
  end
end
