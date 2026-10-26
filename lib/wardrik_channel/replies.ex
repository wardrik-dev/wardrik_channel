defmodule WardrikChannel.Replies do
  @moduledoc """
  Replies post what agents answer in each room's threads, from the agents' logs, so nothing they
  answer is lost to a restart.

  Each room is one process in the cluster, a `WardrikChannel.Replies.Server`, kept in the
  Wardrik's store. It posts what a run answered, what the agent is doing while it works, the calls
  it waits on, who decided them, why a run failed, and that a run stopped.
  """

  alias WardrikChannel.Channel
  alias WardrikChannel.Replies.Server
  alias WardrikChannel.Replies.State
  alias WardrikChannel.Workspace

  @doc "Returns the supervisor the channel's rooms run under."
  @spec child_spec(Channel.t()) :: Supervisor.child_spec()
  def child_spec(%Channel{} = channel) do
    [
      name: supervisor(channel),
      prefix: "#{channel.name}/replies/",
      backend: {WardrikStore.Durable, store: channel.store},
      init_info: %{channel: channel}
    ]
    |> DurableServer.Supervisor.child_spec()
    |> Map.put(:id, __MODULE__)
  end

  @doc "Starts posting in `room`'s threads, unless it's posting already."
  @spec follow(Workspace.t(), String.t()) :: :ok
  def follow(%Workspace{channel: channel, installation: installation} = workspace, room) do
    child =
      {Server, key: key(workspace, room), initial_state: State.new(installation.workspace, room)}

    {:ok, _started} = DurableServer.Supervisor.ensure_started_child(supervisor(channel), child)
    :ok
  end

  @doc "Posts again the calls `conversation` waits on, in its thread of `room`."
  @spec remind(Workspace.t(), String.t(), String.t()) :: :ok
  def remind(%Workspace{channel: channel} = workspace, room, conversation) do
    case DurableServer.Supervisor.lookup(supervisor(channel), key(workspace, room)) do
      {pid, _meta} -> GenServer.cast(pid, {:remind, conversation})
      nil -> :ok
    end
  end

  @doc "Stops posting in `room`, and forgets where it was."
  @spec forget(Workspace.t(), String.t()) :: :ok
  def forget(%Workspace{channel: channel} = workspace, room) do
    _deleted =
      DurableServer.Supervisor.terminate_and_delete_child(
        supervisor(channel),
        key(workspace, room)
      )

    :ok
  end

  defp supervisor(%Channel{wardrik: wardrik, name: name}),
    do: Module.concat([wardrik, "Channels", name, "Replies"])

  defp key(%Workspace{installation: installation}, room),
    do: installation.workspace <> "/" <> room
end
