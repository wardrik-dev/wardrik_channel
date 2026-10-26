defmodule WardrikChannel.Replies.Follower do
  @moduledoc """
  The listener that follows a room's conversations for its `WardrikChannel.Replies.Server`. It
  hands the server each event, and waits until it's posted, so one is in flight at a time.
  """

  use Wardrik.Listener

  @impl Wardrik.Listener
  def handle(event, listener),
    do: GenServer.call(listener.options[:server], {:event, event, listener.cursor}, :infinity)

  @impl Wardrik.Listener
  def cursor(listener), do: GenServer.call(listener.options[:server], :cursor)
end
