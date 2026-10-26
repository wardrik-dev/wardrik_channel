defmodule WardrikChannel.Supervisor do
  @moduledoc """
  Runs a channel: the processes that post in its rooms, then what its adapter runs, such as a
  connection to the chat app.
  """

  use Supervisor

  alias WardrikChannel.Channel

  @doc "Starts the channel `adapter` runs, with the options the Wardrik hands it."
  @spec start_link({module(), keyword()}) :: Supervisor.on_start()
  def start_link({adapter, opts}),
    do: Supervisor.start_link(__MODULE__, Channel.new(adapter, opts))

  @impl Supervisor
  def init(%Channel{adapter: adapter} = channel) do
    children = [WardrikChannel.Replies.child_spec(channel) | adapter.children(channel)]
    Supervisor.init(children, strategy: :one_for_one)
  end
end
