defmodule WardrikChannel.Workspace do
  @moduledoc """
  A channel in one place it's added to, such as one Slack workspace.

  Adapters get one for each request with `WardrikChannel.workspace/2`.

  People in the workspace act in Wardrik as themselves:

    * Everyone may read and message the installation owner's agents.
    * Approvers may also decide what those agents wait on. The adapter is asked whether someone
      is an approver only when they decide.

  The workspace offers the owner's agents whose definitions list the channel in `channels`.
  """

  alias Wardrik.AgentID
  alias Wardrik.Channel.Installation
  alias Wardrik.Statement
  alias WardrikChannel.Channel
  alias WardrikChannel.Member
  alias WardrikChannel.Offer
  alias WardrikCore.Principal

  @enforce_keys [:channel, :installation]
  defstruct @enforce_keys

  @type t() :: %__MODULE__{channel: Channel.t(), installation: Installation.t()}

  @doc "Returns the channel in workspace `id`, or `:error` if it isn't added there."
  @spec new(Channel.t(), String.t()) :: {:ok, t()} | :error
  def new(%Channel{} = channel, id) do
    with {:ok, installation} <- Channel.installation(channel, id),
         do: {:ok, %__MODULE__{channel: channel, installation: installation}}
  end

  @doc "Returns the channel's own scope. It may read the owner's agents."
  @spec scope(t()) :: Wardrik.Scope.t()
  def scope(%__MODULE__{channel: channel, installation: installation}) do
    principal = %Principal{id: channel.name <> ":" <> installation.workspace}
    grants = [Statement.new(roles: [:reader], resources: [Installation.agents(installation)])]
    Wardrik.Scope.new(channel.server, channel.wardrik, principal, grants)
  end

  @doc "Returns `member`'s scope. They may read and message the owner's agents."
  @spec member_scope(t(), Member.t()) :: Wardrik.Scope.t()
  def member_scope(%__MODULE__{channel: channel, installation: installation} = workspace, member) do
    agents = Installation.agents(installation)
    grants = [Statement.new(roles: [:reader, :messenger], resources: [agents])]
    Wardrik.Scope.new(channel.server, channel.wardrik, principal(workspace, member), grants)
  end

  @doc """
  Returns the scope `member` decides calls in.

    * An approver may decide what any of the owner's agents wait on.
    * Whoever `asked_by` names may decide what `conversation` waits on.
    * Anyone else gets `member_scope/2`, and may decide nothing.
  """
  @spec deciding_scope(t(), Member.t(), String.t(), String.t() | nil) :: Wardrik.Scope.t()
  def deciding_scope(
        %__MODULE__{installation: installation} = workspace,
        member,
        conversation,
        asked_by
      ) do
    scope = member_scope(workspace, member)

    cond do
      approver?(workspace, member) ->
        Wardrik.Scope.grant(scope,
          roles: [:approver],
          resources: [Installation.agents(installation)]
        )

      asked_by == principal(workspace, member).id ->
        {:ok, resource} = Wardrik.Resource.agent(conversation)
        Wardrik.Scope.grant(scope, roles: [:approver], resources: [resource])

      true ->
        scope
    end
  end

  @doc "Returns who `member` is to Wardrik, as `slack:T0123/U024BE7LH`."
  @spec principal(t(), Member.t()) :: Principal.t()
  def principal(%__MODULE__{channel: channel, installation: installation}, %Member{} = member) do
    id = "#{channel.name}:#{installation.workspace}/#{member.id}"
    %Principal{id: id, attributes: %{name: member.name}}
  end

  @doc "Returns whether `member` is one of the installation's approvers."
  @spec approver?(t(), Member.t()) :: boolean()
  def approver?(%__MODULE__{installation: %Installation{approvers: :anyone}}, _member), do: true
  def approver?(%__MODULE__{installation: %Installation{approvers: []}}, _member), do: false

  def approver?(%__MODULE__{channel: channel, installation: installation}, member),
    do: channel.adapter.include?(channel, installation, installation.approvers, member)

  @doc "Returns the agents that may answer in the workspace's rooms, sorted by ID."
  @spec offered(t()) :: [Offer.t()]
  def offered(%__MODULE__{installation: installation} = workspace) do
    scope = scope(workspace)
    {:ok, agents} = Wardrik.Agents.list(scope, resources: [Installation.agents(installation)])

    agents
    |> Enum.map(& &1.id)
    |> Enum.reject(&AgentID.conversation?/1)
    |> Enum.flat_map(&offer(scope, workspace, &1))
  end

  defp offer(scope, %__MODULE__{channel: channel}, id) do
    case Wardrik.Agent.definition(scope, id) do
      {:ok, %Wardrik.Definition{channels: channels} = definition, _missing}
      when is_list(channels) ->
        if channel.name in channels,
          do: [
            %Offer{agent: id, name: definition.display_name, description: definition.description}
          ],
          else: []

      _undefined ->
        []
    end
  end

  @doc """
  Returns the ID of the conversation `agent` holds for `thread` of `room`, as
  `acme/triage/slack.T0123.C024BE91L.1696.1234`.
  """
  @spec conversation(t(), String.t(), String.t(), String.t()) :: String.t()
  def conversation(workspace, agent, room, thread),
    do: agent <> "/" <> prefix(workspace, room) <> thread

  @doc "Returns the thread of `room` that `conversation` holds."
  @spec thread(t(), String.t(), String.t()) :: String.t()
  def thread(workspace, room, conversation) do
    {:ok, %AgentID{conversation: held}} = AgentID.parse(conversation)
    String.replace_prefix(held, prefix(workspace, room), "")
  end

  @doc "Returns a pattern matching the logs of every conversation in `room`, for any agent."
  @spec logs(t(), String.t()) :: String.t()
  def logs(%__MODULE__{installation: installation} = workspace, room),
    do: installation.owner <> "/*/" <> prefix(workspace, room) <> "*"

  defp prefix(%__MODULE__{channel: channel, installation: installation}, room),
    do: Enum.join([channel.name, installation.workspace, room, ""], ".")
end
