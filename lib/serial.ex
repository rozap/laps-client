defmodule LapsClient.Serial do
  require Logger

  @doc """
  Takes care of connecting to the actual /dev/tty device
  which will just send this process a bunch of bytes

  This will COBS decode them to turn them into can frames
  and will send the frames to the owner process
  """
  use GenServer

  def start_link(owner, port \\ "/dev/ttyACM0") do
    {:ok, uart_pid} = Circuits.UART.start_link()
    GenServer.start_link(__MODULE__, [uart_pid, port, owner])
  end

  def init([uart_pid, port, owner]) do
    IO.puts("Starting...")

    Circuits.UART.open(
      uart_pid,
      port,
      speed: 57600,
      active: true,
      framing: {Circuits.UART.Framing.None, []}
    )

    # {:ok, response, channel} = PhoenixClient.Channel.join(socket, "telemetry:#{id}")
    # IO.puts("Connected to phx channel: #{inspect(response)}")
    {:ok, {<<>>, owner}}
  end

  def decode(binary) do
    do_decode(<<>>, binary)
  end

  defp do_decode(head, <<>>) do
    {:ok, head}
  end

  defp do_decode(head, <<ohb, tail::binary>>) do
    block_length = ohb - 1

    if block_length > byte_size(tail) do
      {:error, "Offset byte specifies more bytes than available"}
    else
      <<block::binary-size(block_length), remaining::binary>> = tail

      new_head =
        if byte_size(remaining) > 0 do
          head <> block <> <<0>>
        else
          head <> block
        end

      do_decode(new_head, remaining)
    end
  end

  defp emit(<<>>, leftover, to_emit) do
    {to_emit, leftover}
  end

  defp emit(<<0, rest::binary>>, acc, to_emit) do
    emit(rest, <<>>, [acc | to_emit])
  end

  defp emit(<<b::binary-size(1), rest::binary>>, acc, to_emit) do
    emit(rest, acc <> b, to_emit)
  end

  defp emit(stuff), do: emit(stuff, <<>>, [])

  def handle_info({:circuits_uart, _port, message}, {b, owner}) do
    {to_emit, leftover} = emit(b <> message)

    case to_emit do
      [] ->
        :noop

      _ ->
        decoded = Enum.map(to_emit, &decode/1)

        {oks, errs} =
          Enum.split(decoded, fn
            {:ok, _} ->
              true

            _err ->
              false
          end)

        case errs do
          [] ->
            :ok

          _ ->
            Enum.each(errs, fn e ->
              Logger.warning("Failed to cobs decode frame #{inspect(e)}")
            end)
        end

        send(owner, {:packets, self(), oks})
    end

    {:noreply, {leftover, owner}}
  end
end
