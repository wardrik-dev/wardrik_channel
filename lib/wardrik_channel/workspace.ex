defmodule WardrikChannel.Workspace do
  @moduledoc """
  A workspace is a channel as it acts in one place it's added to, such as one Slack workspace. An
  adapter makes one for each thing it hears, with `WardrikChannel.workspace/2`.

  Its people act through Wardrik as themselves. Each may read and message the agents of the
  installation's owner, and its approvers may decide what those agents wait on. Whether someone is
  an approver is asked of the adapter only as they decide. The agents it
  offers are the owner's whose definitions list the channel among their `channels`.
  """

  alias Wardrik.AgentID
  alias Wardrik.Statement
  alias WardrikChannel.Channel
  alias WardrikChannel.Installation
  alias WardrikChannel.Member
  alias WardrikChannel.Offer
  alias WardrikCore.Principal

  @enforce_keys [:channel, :installation]
  defstruct @enforce_keys

  @type t() :: %__MODULE__{channel: Channel.t(), installation: Installation.t()}

  @doc "Returns the channel in the workspace the chat app names `id`, or `:error` where it isn't added there."
  @spec new(Channel.t(), String.t()) :: {:ok, t()} | :error
  def new(%Channel{} = channel, id) do
    with {:ok, installation} <- Channel.installation(channel, id),
         do: {:ok, %__MODULE__{channel: channel, installation: installation}}
  end

  @doc "Returns the scope the channel itself reads the owner's agents in."
  @spec scope(t()) :: Wardrik.Scope.t()
  def scope(%__MODULE__{channel: channel, installation: installation}) do
    principal = %Principal{id: channel.name <> ":" <> installation.workspace}
    grants = [Statement.new(roles: [:reader], resources: [Installation.agents(installation)])]
    Wardrik.as(channel.wardrik, principal, grants)
  end

  @doc "Returns the scope `member` acts in: they read and message the owner's agents."
  @spec member_scope(t(), Member.t()) :: Wardrik.Scope.t()
  def member_scope(%__MODULE__{channel: channel, installation: installation} = workspace, member) do
    agents = Installation.agents(installation)
    grants = [Statement.new(roles: [:reader, :messenger], resources: [agents])]
    Wardrik.as(channel.wardrik, principal(workspace, member), grants)
  end

  @doc """
  Returns the scope `member` decides in: an approver decides what the owner's agents wait on, and
  anyone else only what `conversation` waits on, where they asked for its turn as `asked_by` says.
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
        Wardrik.grant(scope, roles: [:approver], resources: [Installation.agents(installation)])

      asked_by == principal(workspace, member).id ->
        {:ok, resource} = Wardrik.Resource.agent(conversation)
        Wardrik.grant(scope, roles: [:approver], resources: [resource])

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

  @doc "Returns whether `member` is among the installation's approvers."
  @spec approver?(t(), Member.t()) :: boolean()
  def approver?(%__MODULE__{installation: %Installation{approvers: :anyone}}, _member), do: true
  def approver?(%__MODULE__{installation: %Installation{approvers: []}}, _member), do: false

  def approver?(%__MODULE__{channel: channel, installation: installation}, member),
    do: channel.adapter.include?(channel, installation, installation.approvers, member)

  @doc "Returns the agents the workspace may have answer in its rooms, sorted by ID."
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

  @doc "Returns the pattern of the logs of every conversation in `room`, whichever agent holds it."
  @spec logs(t(), String.t()) :: String.t()
  def logs(%__MODULE__{installation: installation} = workspace, room),
    do: installation.owner <> "/*/" <> prefix(workspace, room) <> "*"

  defp prefix(%__MODULE__{channel: channel, installation: installation}, room),
    do: Enum.join([channel.name, installation.workspace, room, ""], ".")
end
