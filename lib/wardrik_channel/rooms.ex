defmodule WardrikChannel.Rooms do
  @moduledoc """
  Rooms keep which agent answers in each room, and the threads it has answered in.

  An adapter tells `joined/3` when its bot is invited into a room. With one agent offered, it
  answers there from then on, when mentioned. With several, someone picks one with `chose/4`.
  `answers/4` has the agent answer every message, or only mentions again, and `left/3` unbinds the
  room. Each change is recorded in the audit as `wardrik.room.bound` or `wardrik.room.unbound`,
  with who made it, where the adapter knows.
  """

  alias WardrikChannel.Binding
  alias WardrikChannel.Installation
  alias WardrikChannel.Member
  alias WardrikChannel.Offer
  alias WardrikChannel.Replies
  alias WardrikChannel.Workspace

  @typedoc "What a room shows once its bot arrives: its agent, the agents to pick from, or none."
  @type shown() :: {:bound, Binding.t(), Offer.t()} | {:choose, [Offer.t()]} | :none

  @doc """
  Returns what `room` is bound to, where its agent is still the installation owner's. A workspace
  added again for another owner keeps none of its rooms' agents.
  """
  @spec get(Workspace.t(), String.t()) :: Binding.t() | nil
  def get(%Workspace{installation: installation} = workspace, room) do
    with %{"agent" => agent, "answers" => answers} <-
           WardrikStore.get(store(workspace), key(workspace, room)),
         true <- Installation.covers?(installation, agent) do
      %Binding{room: room, agent: agent, answers: answers(answers)}
    else
      _unbound -> nil
    end
  end

  @doc "Binds `room` to the one agent the workspace offers, or returns the agents to pick from."
  @spec joined(Workspace.t(), String.t(), Member.t() | nil) :: shown()
  def joined(workspace, room, by \\ nil) do
    case Workspace.offered(workspace) do
      [offer] -> {:bound, bind(workspace, room, offer.agent, :mentions, by), offer}
      [] -> :none
      offers -> {:choose, offers}
    end
  end

  @doc "Returns the agents someone may switch `room` to, or `:none`."
  @spec choices(Workspace.t()) :: {:choose, [Offer.t()]} | :none
  def choices(workspace) do
    case Workspace.offered(workspace) do
      [] -> :none
      offers -> {:choose, offers}
    end
  end

  @doc "Binds `room` to `agent`, answering when mentioned, where the workspace offers it."
  @spec chose(Workspace.t(), String.t(), String.t(), Member.t() | nil) ::
          {:ok, Binding.t(), Offer.t()} | {:error, :not_offered}
  def chose(workspace, room, agent, by \\ nil) do
    case Enum.find(Workspace.offered(workspace), &(&1.agent == agent)) do
      %Offer{} = offer -> {:ok, bind(workspace, room, agent, :mentions, by), offer}
      nil -> {:error, :not_offered}
    end
  end

  @doc "Changes when the agent bound to `room` answers: when mentioned, or to every message."
  @spec answers(Workspace.t(), String.t(), Binding.answers(), Member.t() | nil) ::
          {:ok, Binding.t()} | {:error, :not_bound}
  def answers(workspace, room, answers, by \\ nil) when answers in [:mentions, :everything] do
    case get(workspace, room) do
      %Binding{agent: agent} -> {:ok, bind(workspace, room, agent, answers, by)}
      nil -> {:error, :not_bound}
    end
  end

  @doc "Unbinds `room`, so no agent answers there, and nothing more is posted in its threads."
  @spec left(Workspace.t(), String.t(), Member.t() | nil) :: :ok
  def left(workspace, room, by \\ nil) do
    case get(workspace, room) do
      %Binding{agent: agent} ->
        :ok = WardrikStore.delete(store(workspace), key(workspace, room))
        :ok = Replies.forget(workspace, room)
        record(workspace, by, "room.unbound", room, %{"agent" => %{"id" => agent}})

      nil ->
        :ok
    end
  end

  @doc "Returns whether the room's agent has answered in `thread`."
  @spec started?(Workspace.t(), String.t(), String.t()) :: boolean()
  def started?(workspace, room, thread),
    do: WardrikStore.get(store(workspace), thread_key(workspace, room, thread)) != nil

  @doc "Notes that the room's agent answers in `thread`."
  @spec start(Workspace.t(), String.t(), String.t()) :: :ok
  def start(workspace, room, thread) do
    {:ok, _vsn} = WardrikStore.put(store(workspace), thread_key(workspace, room, thread), true)
    :ok
  end

  defp bind(workspace, room, agent, answers, by) do
    bound = %{"agent" => agent, "answers" => Atom.to_string(answers)}
    {:ok, _vsn} = WardrikStore.put(store(workspace), key(workspace, room), bound)
    data = %{"agent" => %{"id" => agent}, "answers" => bound["answers"]}
    :ok = record(workspace, by, "room.bound", room, data)
    %Binding{room: room, agent: agent, answers: answers}
  end

  defp answers("mentions"), do: :mentions
  defp answers("everything"), do: :everything

  defp record(%Workspace{channel: channel} = workspace, by, type, room, data) do
    scope = scope(workspace, by)
    data = Map.merge(data, %{"channel" => channel.name, "room" => room})
    subject = "channels/#{channel.name}/rooms/#{room}"
    :ok = WardrikEvents.record(channel.events, {type, subject, data}, actor: scope.principal)
  end

  defp scope(workspace, nil), do: Workspace.scope(workspace)
  defp scope(workspace, %Member{} = member), do: Workspace.member_scope(workspace, member)

  defp store(%Workspace{channel: channel}), do: channel.store

  defp key(workspace, room), do: "rooms/" <> place(workspace, room)

  defp thread_key(workspace, room, thread),
    do: "threads/" <> place(workspace, room) <> "/" <> thread

  defp place(%Workspace{channel: channel, installation: installation}, room),
    do: Enum.join([channel.name, installation.workspace, room], "/")
end
