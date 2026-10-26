defmodule WardrikChannel.Replies.State do
  @moduledoc """
  The state of one room's replies: the cursor past what's posted, and, for each conversation in
  the room, the run under way, the messages it answers and who asked, and the arguments of its
  calls. The channel, the last status shown in each thread and the follower aren't kept.
  """

  @kept [:workspace, :room, :cursor, :senders, :runs, :calls]

  @enforce_keys [:workspace, :room]
  defstruct [
    :workspace,
    :room,
    :cursor,
    :channel,
    :follower,
    senders: %{},
    runs: %{},
    calls: %{},
    shown: %{}
  ]

  @type run() :: %{id: String.t(), answering: [String.t()], asked_by: String.t() | nil}

  @type t() :: %__MODULE__{
          workspace: String.t(),
          room: String.t(),
          cursor: String.t() | nil,
          channel: WardrikChannel.Channel.t() | nil,
          follower: pid() | nil,
          senders: %{String.t() => String.t()},
          runs: %{String.t() => run()},
          calls: %{String.t() => %{String.t() => term()}},
          shown: %{String.t() => integer()}
        }

  @typedoc """
  What an event asks to be posted in its thread: what a run answered and the messages it answers,
  what the agent is doing, the calls it waits on with who asked, why a run failed, that a run
  stopped before it answered, a line about a decision, or nothing.
  """
  @type post() ::
          {:reply, String.t(), [String.t()]}
          | {:status, String.t()}
          | {:waiting, [String.t()], String.t() | nil}
          | {:failed, String.t()}
          | {:stopped, [String.t()]}
          | {:said, String.t()}
          | :none

  @doc "Returns the state of a room no one has posted in yet."
  @spec new(String.t(), String.t()) :: t()
  def new(workspace, room), do: %__MODULE__{workspace: workspace, room: room}

  @doc "Returns what of `state` is kept between restarts."
  @spec dump(t()) :: map()
  def dump(state), do: Map.take(state, @kept)

  @doc "Returns the state kept as `dumped`."
  @spec load(map()) :: t()
  def load(dumped), do: struct!(__MODULE__, dumped)

  @doc "Returns what `event` of `conversation` asks to be posted, and the state once it is."
  @spec take(t(), String.t(), Wardrik.Event.t()) :: {post(), t()}
  def take(state, conversation, %Wardrik.Event{type: "wardrik." <> type, data: data}),
    do: taken(state, conversation, type, data)

  @doc "Returns the arguments of the call `id` in `conversation`, where they're known."
  @spec arguments(t(), String.t(), String.t() | nil) :: term()
  def arguments(state, conversation, id), do: get_in(state.calls, [conversation, id])

  @doc "Returns who asked for the run under way in `conversation`, where it's known."
  @spec asked_by(t(), String.t()) :: String.t() | nil
  def asked_by(state, conversation), do: get_in(state.runs, [conversation, :asked_by])

  defp taken(state, _conversation, "message.created", %{
         "message" => %{"id" => id},
         "sender" => %{"id" => sender}
       }),
       do: {:none, put_in(state.senders[id], sender)}

  defp taken(state, conversation, "run.started", %{"run" => run}) do
    answering = Map.get(run, "message_ids", [])
    {asked, senders} = Map.split(state.senders, answering)
    run = %{id: run["id"], answering: answering, asked_by: first_sender(asked, answering)}
    state = %{state | senders: senders, runs: Map.put(state.runs, conversation, run)}
    {{:status, "is thinking…"}, state}
  end

  defp taken(state, conversation, "tool_call.started", %{
         "tool" => %{"name" => name, "call" => call}
       }),
       do: {{:status, "is running #{name}…"}, remembered(state, conversation, call)}

  defp taken(state, conversation, "run.completed", %{"messages" => messages}),
    do:
      {{:reply, last_said(messages), answering(state, conversation)}, ended(state, conversation)}

  defp taken(state, conversation, "run.interrupted", %{"interrupts" => interrupts}),
    do: {{:waiting, Enum.map(interrupts, & &1["id"]), asked_by(state, conversation)}, state}

  defp taken(state, conversation, "run.failed", %{"error" => error}),
    do: {{:failed, error["message"]}, ended(state, conversation)}

  defp taken(state, conversation, "run.cancelled", _data),
    do: {{:stopped, answering(state, conversation)}, ended(state, conversation)}

  defp taken(state, _conversation, "interrupt.resolved", data),
    do:
      {{:said,
        decided(data["decision"], decider(data["resolved_by"]), data["note"] || data["reason"])},
       state}

  defp taken(state, _conversation, _type, _data), do: {:none, state}

  defp remembered(state, conversation, %{"id" => id} = call) do
    calls = state.calls |> Map.get(conversation, %{}) |> Map.put(id, call["arguments"])
    %{state | calls: Map.put(state.calls, conversation, calls)}
  end

  defp first_sender(asked, [first | _rest]), do: Map.get(asked, first)
  defp first_sender(_asked, []), do: nil

  defp answering(state, conversation), do: get_in(state.runs, [conversation, :answering]) || []

  defp ended(state, conversation),
    do: %{
      state
      | runs: Map.delete(state.runs, conversation),
        calls: Map.delete(state.calls, conversation)
    }

  defp decider(%{"name" => name}) when is_binary(name), do: name
  defp decider(%{"id" => id}), do: id
  defp decider(nil), do: "someone"

  defp decided("approved", name, nil), do: "Approved by #{name}."
  defp decided("approved", name, note), do: "Approved by #{name}: #{note}"
  defp decided(_rejected, name, nil), do: "Denied by #{name}."
  defp decided(_rejected, name, reason), do: "Denied by #{name}: #{reason}"

  defp last_said(messages) do
    messages
    |> Enum.reverse()
    |> Enum.find_value("", &said/1)
  end

  defp said(%{"role" => "assistant", "parts" => parts}) do
    case text(parts) do
      "" -> nil
      text -> text
    end
  end

  defp said(_message), do: nil

  defp text(parts), do: Enum.map_join(parts, &part_text/1)

  defp part_text(%{"type" => "text", "content" => text}), do: text
  defp part_text(_part), do: ""
end
