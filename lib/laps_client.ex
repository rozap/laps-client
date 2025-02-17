defmodule LapsClient do
  alias LapsClient.Serial

  def send_frames(from, dbc, laphub_session) do
    receive do
      {:packets, ^from, frames} ->
        IO.inspect({:got_frames, frames})

        decoded_frames =
          Enum.map(frames, fn frame ->
            Canbus.Decode.decode(dbc, frame)
          end)

        # Here is where we will send it off to the channel
        IO.inspect(decoded_frames)
    end

    send_frames(from, dbc, laphub_session)
  end

  def begin(dbc_file, device, laphub_session) do
    {:ok, pid} = Serial.start_link(self(), device)
    {:ok, dbc} = Canbus.Dbc.parse(dbc_file)
    send_frames(pid, dbc, laphub_session)
  end
end
