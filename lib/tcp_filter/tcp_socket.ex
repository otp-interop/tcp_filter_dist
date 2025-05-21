defmodule TCPFilter.TCPSocket do
  @behaviour TCPFilter.Socket

  def family, do: :inet
  def protocol, do: :tcp

  def handle_input(socket, {:tcp_closed, socket}),
    do: {:error, :closed}
  def handle_input(socket, {:tcp, socket, data}),
    do: {:data, data}
  def handle_input(_socket, other),
    do: other

  def listen(port, options) do
    :gen_tcp.listen(port, options)
  end

  def accept(socket) do
    :gen_tcp.accept(socket)
  end

  def connect(ip, port, options) do
    :gen_tcp.connect(ip, port, options)
  end

  def close(socket) do
    :gen_tcp.close(socket)
  end

  def send(socket, data) do
    :gen_tcp.send(socket, data)
  end

  def recv(socket, length, timeout) do
    :gen_tcp.recv(socket, length, timeout)
  end

  def controlling_process(socket, pid) do
    :gen_tcp.controlling_process(socket, pid)
  end

  def sockname(socket) do
    :inet.sockname(socket)
  end

  def peername(socket) do
    :inet.peername(socket)
  end

  def getopts(socket, opts) do
    :inet.getopts(socket, opts)
  end

  def setopts(socket, opts) do
    :inet.setopts(socket, opts)
  end

  def getstat(socket, opts) do
    :inet.getstat(socket, opts)
  end
end
