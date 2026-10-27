defmodule WardrikChannel do
  @moduledoc """
  Chat apps people reach Wardrik's agents through, such as Slack. A *channel* is one chat app your
  Wardrik runs, by a name of your own. A *room* is a place in it, such as a Slack channel.

      defmodule MyApp.Wardrik do
        use Wardrik, otp_app: :my_app
      end

      config :my_app, MyApp.Wardrik,
        channels: [
          slack: {WardrikSlack, token: "xoxb-...", signing_secret: "...", owner: "acme", approvers: ["@maria"]}
        ]

  An agent answers in a channel when its definition lists it:

      Wardrik.Agent.define(scope, "acme/triage", model: "anthropic:claude-haiku-4-5", channels: ["slack"])

  Invite the bot into a room, and the agent answers there in threads: mention it to start one,
  and reply in the thread to go on. Each thread is a conversation of the agent's own, as
  `acme/triage/slack.T0123.C024BE91L.1696.1234`. A call the agent waits on is posted in the thread
  for an approver, or whoever asked, to decide. See `WardrikChannel.Rooms` and
  `WardrikChannel.Replies`.

  Every channel takes `:token` and `:owner`, whose agents answer there, or its `:installations`,
  for one app added to many workspaces, `:stored` to keep them in the Wardrik; `:approvers`, as the channel names people, or `:anyone`;
  and `:offering` and `:deciding`, what a room with no agent and someone who may not decide are
  told. Its adapter reads the rest.

  ## Adapters

  An adapter is a package of its own, such as `wardrik_slack`, that does `use WardrikChannel`. It
  answers what the chat app sends with `c:Wardrik.Channel.request/2`, finding the workspace with
  `workspace/2`, and hands each message posted to `received/2`, and each button pressed to
  `decide/4`. It implements `c:deliver/2` to post, and `c:include?/4` to find approvers.

  Reach for this when you write an adapter for a chat app.
  """

  alias Wardrik.Error
  alias WardrikChannel.Binding
  alias WardrikChannel.Channel
  alias WardrikChannel.Inbound
  alias WardrikChannel.Installation
  alias WardrikChannel.Member
  alias WardrikChannel.Outbound
  alias WardrikChannel.Replies
  alias WardrikChannel.Rooms
  alias WardrikChannel.Workspace

  @doc "Posts `outbound` in its thread. An error is tried again later."
  @callback deliver(Channel.t(), Outbound.t()) :: :ok | {:error, term()}

  @doc "Returns whether `names`, as the channel names people, such as `@maria`, include `member`."
  @callback include?(Channel.t(), Installation.t(), names :: [String.t()], Member.t()) ::
              boolean()

  @doc "Returns what the channel runs besides its rooms, such as a connection to the chat app."
  @callback children(Channel.t()) :: [Supervisor.child_spec() | {module(), term()}]

  defmacro __using__(_opts) do
    quote do
      @behaviour WardrikChannel
      @behaviour Wardrik.Channel

      @impl Wardrik.Channel
      def child_spec(opts) do
        %{
          id: __MODULE__,
          start: {WardrikChannel.Supervisor, :start_link, [{__MODULE__, opts}]},
          type: :supervisor
        }
      end

      @impl WardrikChannel
      def children(_channel), do: []

      @impl Wardrik.Channel
      def notify(opts, room, notice, approvers),
        do: WardrikChannel.notify(__MODULE__, opts, room, notice, approvers)

      defoverridable child_spec: 1, children: 1, notify: 4
    end
  end

  @doc """
  Posts `notice` in `room`, asking `approvers`, in the workspace nearest the agent's owner: its
  user's, then its org's. Returns `{:skip, why}` where the channel is added to neither's. See
  `c:Wardrik.Channel.notify/4`.
  """
  @spec notify(module(), keyword(), String.t(), Wardrik.Notice.t(), [String.t()]) ::
          :ok | {:skip, String.t()} | {:error, term()}
  def notify(adapter, opts, room, notice, approvers) do
    channel = Channel.new(adapter, opts)

    case Channel.nearest(channel, notice.agent) do
      {:ok, installation} ->
        adapter.deliver(channel, %Outbound{
          installation: installation,
          room: room,
          thread: nil,
          body: {:notice, notice},
          approvers: approvers
        })

      :error ->
        {:skip, "but #{channel.name} isn't added to a workspace of its owner's"}
    end
  end

  @doc "Returns the channel `adapter` runs, from the options the Wardrik hands it."
  @spec channel(module(), keyword()) :: Channel.t()
  def channel(adapter, opts), do: Channel.new(adapter, opts)

  @doc """
  Returns the channel the Wardrik `instance` runs as `name`, for your app's own routes, such as
  where a chat app sends someone back once it's added to their workspace.

      {:ok, channel} = WardrikChannel.fetch(MyApp.Wardrik, "slack")
  """
  @spec fetch(atom(), String.t()) :: {:ok, Channel.t()} | :error
  def fetch(instance, name) do
    with {:ok, {adapter, opts}} <- Wardrik.Channel.fetch(instance, name),
         do: {:ok, Channel.new(adapter, opts)}
  end

  @doc "Returns the channel in the workspace the chat app names `id`, or `:error` where it isn't added there."
  @spec workspace(Channel.t(), String.t()) :: {:ok, Workspace.t()} | :error
  def workspace(channel, id), do: Workspace.new(channel, id)

  @doc """
  Asks the room's agent what `inbound` says, as its sender, in the conversation of its thread, and
  has the thread answered. A message posted in the room starts a thread where it mentions the bot,
  or where the agent answers every message. A reply in a thread reaches the agent where the thread
  is the agent's already. Returns `:ignored` for a message no agent answers, or why it couldn't
  ask.

  A message behind calls the agent waits on waits too, so those calls are posted again.
  """
  @spec received(Workspace.t(), Inbound.t()) ::
          {:asked, String.t()} | :ignored | {:error, String.t()}
  def received(%Workspace{} = workspace, %Inbound{} = inbound) do
    thread = inbound.thread || inbound.id

    with %Binding{} = binding <- Rooms.get(workspace, inbound.room),
         true <- answers?(workspace, binding, inbound, thread) do
      ask(workspace, binding, inbound, thread)
    else
      _unanswered -> :ignored
    end
  end

  defp answers?(_workspace, _binding, %Inbound{mentioned?: true}, _thread), do: true
  defp answers?(_workspace, %Binding{answers: :everything}, _inbound, _thread), do: true
  defp answers?(_workspace, _binding, %Inbound{thread: nil}, _thread), do: false

  defp answers?(workspace, binding, _inbound, thread),
    do: Rooms.started?(workspace, binding.room, thread)

  defp ask(workspace, %Binding{room: room, agent: agent}, inbound, thread) do
    conversation = Workspace.conversation(workspace, agent, room, thread)
    scope = Workspace.member_scope(workspace, inbound.sender)

    with :ok <- Rooms.start(workspace, room, thread),
         :ok <- Replies.follow(workspace, room),
         waiting? = waiting?(workspace, conversation),
         {:ok, _message} <-
           Wardrik.Agent.ask(scope, conversation, content: inbound.text, id: inbound.id) do
      if waiting?, do: Replies.remind(workspace, room, conversation)
      {:asked, conversation}
    else
      {:error, %Error{message: message}} -> {:error, message}
    end
  end

  defp waiting?(workspace, conversation) do
    match?(
      {:ok, %Wardrik.Agent{status: :parked}},
      Wardrik.Agent.read(Workspace.scope(workspace), conversation)
    )
  end

  @doc """
  Decides a call a thread's agent waits on, as `member`. `waiting` holds what the adapter put on
  its button: the `:conversation`, the `:interrupt`'s id, and `:asked_by`, who asked for the turn,
  as `WardrikChannel.Waiting` gave them. `answer` is `{:approve, note}` or `{:deny, reason}`, either
  `nil` where none was given.

  An approver may decide, and so may whoever asked. Anyone else is told who may, with the
  channel's `:deciding`.
  """
  @spec decide(Workspace.t(), Member.t(), map(), {:approve | :deny, String.t() | nil}) ::
          {:ok, Wardrik.Decision.t()} | {:error, String.t()}
  def decide(
        workspace,
        member,
        %{conversation: conversation, interrupt: interrupt} = waiting,
        answer
      ) do
    scope = Workspace.deciding_scope(workspace, member, conversation, Map.get(waiting, :asked_by))

    case answered(scope, conversation, interrupt, answer) do
      {:ok, [decision]} ->
        {:ok, decision}

      {:error, %Error{type: type}} when type in [:forbidden, :not_found] ->
        {:error, workspace.channel.deciding}

      {:error, %Error{message: message}} ->
        {:error, message}
    end
  end

  defp answered(scope, conversation, interrupt, {:approve, note}),
    do: Wardrik.Agent.approve(scope, conversation, interrupt, given(:note, note))

  defp answered(scope, conversation, interrupt, {:deny, reason}),
    do: Wardrik.Agent.deny(scope, conversation, interrupt, given(:reason, reason))

  defp given(_key, nil), do: []
  defp given(key, value), do: [{key, value}]
end
