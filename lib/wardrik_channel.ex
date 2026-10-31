defmodule WardrikChannel do
  @moduledoc """
  Lets people talk to Wardrik's agents from chat apps, such as Slack.

  A *channel* is one chat app Wardrik runs, under a name you choose. A *room* is a place in it,
  such as a Slack channel.

      config :my_app, MyApp.AgentRuntime,
        channels: [
          slack: {WardrikSlack, token: "xoxb-...", signing_secret: "...", owner: "acme", approvers: ["@maria"]}
        ]

  An agent answers in a channel when its definition lists it:

      Wardrik.Agent.define(scope, "acme/triage", model: "anthropic:claude-haiku-4-5", channels: ["slack"])

  Mention the bot in a room to start a thread. Reply in the thread to go on. Each thread is its own
  conversation, as `acme/triage/slack.T0123.C024BE91L.1696.1234`. Calls the agent waits on are
  posted in the thread for someone to decide. See `WardrikChannel.Rooms` and
  `WardrikChannel.Replies`.

  ## Options

  Every channel takes these. Its adapter reads the rest.

  #{NimbleOptions.docs(WardrikChannel.Channel.schema())}

  Raises on start if an option is invalid, if neither or both of `:token` and `:installations`
  are given, or if the channel's name isn't lower-case letters, digits and `-`, starting with a
  letter.

  ## Writing an adapter

  An adapter is a package, such as `wardrik_slack`, that does `use WardrikChannel`. It implements
  `c:deliver/2` and `c:include?/4`, and `c:Wardrik.Channel.request/2` to take what the chat app
  sends:

      defmodule MyChat do
        use WardrikChannel

        @impl Wardrik.Channel
        def request(opts, %{path: "events", body: body}) do
          channel = WardrikChannel.channel(__MODULE__, opts)
          event = JSON.decode!(body)

          with {:ok, workspace} <- WardrikChannel.workspace(channel, event["team"]) do
            WardrikChannel.received(workspace, %WardrikChannel.Inbound{
              room: event["room"],
              id: event["id"],
              sender: %WardrikChannel.Member{id: event["user"]},
              text: event["text"],
              mentioned?: event["mentioned"]
            })
          end

          %{status: 200, headers: %{}, body: ""}
        end

        @impl WardrikChannel
        def deliver(channel, %WardrikChannel.Outbound{} = outbound) do
          # Post outbound.body in outbound.room, in outbound.thread
          :ok
        end

        @impl WardrikChannel
        def include?(_channel, _installation, names, member), do: member.id in names
      end

  Hand each button press to `decide/4`. `use WardrikChannel` defines `child_spec/1`,
  `c:children/1` and `c:Wardrik.Channel.notify/4`. Each can be overridden.
  """

  alias Wardrik.Channel.Installation
  alias Wardrik.Error
  alias WardrikChannel.Binding
  alias WardrikChannel.Channel
  alias WardrikChannel.Inbound
  alias WardrikChannel.Member
  alias WardrikChannel.Outbound
  alias WardrikChannel.Replies
  alias WardrikChannel.Rooms
  alias WardrikChannel.Workspace

  @doc "Posts `outbound` in its thread. Returning an error has it tried again later."
  @callback deliver(Channel.t(), Outbound.t()) :: :ok | {:error, term()}

  @doc "Returns whether `member` is one of `names`, as the chat app names people, such as `@maria`."
  @callback include?(Channel.t(), Installation.t(), names :: [String.t()], Member.t()) ::
              boolean()

  @doc "Returns extra children to run, such as a connection to the chat app. `[]` by default."
  @callback children(Channel.t()) :: [Supervisor.child_spec() | {module(), term()}]

  @doc """
  Returns the URL where someone acting for `owner` adds the chat app to their workspace.

  ## Options

    * `:return_to` - where they're sent once it's added.
  """
  @callback install_url(Channel.t(), owner :: String.t(), keyword()) ::
              {:ok, String.t()} | {:error, String.t()}

  @doc """
  Finishes adding the chat app to a workspace, for `owner`.

  `query` is the query string the chat app redirected back with. Returns the installation and
  where to send the person next.
  """
  @callback installed(Channel.t(), owner :: String.t(), query :: map()) ::
              {:ok, Installation.t(), String.t() | nil} | {:error, String.t()}

  @doc "Removes the chat app from `workspace`, where the chat app allows it, and forgets the workspace."
  @callback uninstall(Channel.t(), workspace :: String.t()) :: :ok | {:error, String.t()}

  @optional_callbacks install_url: 3, installed: 3, uninstall: 2

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
  Posts `notice` in `room`, asking `approvers`. See `c:Wardrik.Channel.notify/4`.

  Posts in the workspace of the agent's owner. That is the owning user's workspace if the channel
  is added to one, else the org's. Returns `{:skip, why}` if it's added to neither.
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

  @doc "Returns `adapter`'s channel, built from the options Wardrik passes it."
  @spec channel(module(), keyword()) :: Channel.t()
  def channel(adapter, opts), do: Channel.new(adapter, opts)

  @doc "Returns the channel in workspace `id`, or `:error` if it isn't added there."
  @spec workspace(Channel.t(), String.t()) :: {:ok, Workspace.t()} | :error
  def workspace(channel, id), do: Workspace.new(channel, id)

  @doc """
  Sends `inbound` to the room's agent, as its sender, and has the reply posted in its thread.

  The agent is asked when:

    * the message mentions the bot
    * the room's agent answers every message
    * the message replies in a thread the agent already answers in

  Returns `{:asked, conversation}`, `:ignored` if no agent answers, or `{:error, message}`.

  If the agent is waiting on calls, the message queues behind them and the calls are posted again.
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
  Approves or denies a call the agent waits on, as `member`.

      waiting = %{conversation: conversation, interrupt: "int_1", asked_by: nil}
      WardrikChannel.decide(workspace, member, waiting, {:approve, "Looks fine."})
      #=> {:ok, %Wardrik.Decision{}}

  `waiting` is what the adapter put on the button, from a `WardrikChannel.Waiting`:

    * `:conversation` - the conversation's ID.
    * `:interrupt` - the interrupt's ID.
    * `:asked_by` - who asked for the turn. Optional.

  `answer` is `{:approve, note}` or `{:deny, reason}`. Either may be `nil`.

  Approvers may decide, and so may whoever asked. Anyone else gets `{:error, deciding}`, the
  channel's `:deciding` message.
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
