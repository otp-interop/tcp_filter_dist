defmodule TCPFilter.Socket do
  @doc """
  Defines socket behaviour
  """

  @type socket :: any()
  @type ip_address :: :inet.socket_address() | :inet.hostname()

  @callback family() :: atom()
  @callback protocol() :: atom()

  @callback handle_input(socket :: socket(), any()) :: {:data, binary() | list()} | {:error, :closed} | any()

  @callback listen(port :: integer(), options :: any()) :: {:ok, socket()} | {:error, any()}
  @callback accept(socket :: socket()) :: {:ok, socket()} | {:error, any()}
  @callback connect(ip :: ip_address(), port :: integer(), options :: any()) :: {:ok, socket()} | {:error, any()}
  @callback close(socket :: socket()) :: :ok
  @callback send(socket :: socket(), data :: iodata()) :: :ok | {:error, reason :: any()}
  @callback recv(socket :: socket(), length :: non_neg_integer(), timeout :: timeout()) :: {:ok, packet :: binary()} | {:error, reason :: any()}
  @callback controlling_process(socket :: socket(), pid :: pid()) :: :ok | {:error, reason :: any()}

  @callback sockname(socket :: socket()) :: {:ok, {ip_address(), integer()}} | {:error, reason :: any()}
  @callback peername(socket :: socket()) :: {:ok, {ip_address(), integer()}} | {:error, reason :: any()}
  @callback getopts(socket :: socket(), options :: [any()]) :: {:ok, [any()]} | {:error, any()}
  @callback setopts(socket :: socket(), options :: [any()]) :: :ok | {:error, any()}
  @callback getstat(socket :: socket(), options :: [any()]) :: {:ok, [{any(), integer()}]} | {:error, any()}
end
