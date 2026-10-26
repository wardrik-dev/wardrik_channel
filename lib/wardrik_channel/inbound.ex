defmodule WardrikChannel.Inbound do
  @moduledoc """
  An inbound message is one someone posted in a room, as an adapter hands it to
  `WardrikChannel.received/2`.

  `thread` is the thread it replies in, or `nil` where it starts one. `id` is unique in its room,
  and the agent is asked under it, so a message handed over twice is answered once. `text` leaves
  out any mention of the bot, and `mentioned?` says whether there was one.
  """

  @enforce_keys [:room, :id, :sender, :text]
  defstruct [:room, :thread, :id, :sender, :text, mentioned?: false]

  @type t() :: %__MODULE__{
          room: String.t(),
          thread: String.t() | nil,
          id: String.t(),
          sender: WardrikChannel.Member.t(),
          text: String.t(),
          mentioned?: boolean()
        }
end
