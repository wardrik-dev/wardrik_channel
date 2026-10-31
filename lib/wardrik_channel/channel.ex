defmodule WardrikChannel.Channel do
  @moduledoc """
  One chat app Wardrik runs, under the name it's given.

  Holds the adapter, the adapter's own options, and the installations that say where it's added.
  Wardrik passes it the rest:

    * `:server` - the `Wardrik.Server` that runs operations.
    * `:wardrik` - the instance.
    * `:events` - where events are followed and recorded.
    * `:store` - Wardrik's store.
    * `:vault` - where tokens are sealed. `nil` without Wardrik's `:keys`.
  """

  alias Wardrik.Channel.Installation
  alias WardrikChannel.Installations.Stored
  alias WardrikChannel.Installations.Token

  @options [
    token: [
      type: {:or, [:string, nil]},
      doc: "The token the channel acts with, in the one workspace it reaches. Needs `:owner`."
    ],
    owner: [type: :string, doc: "Whose agents answer, as `\"acme\"`."],
    installations: [
      type: {:or, [{:in, [:stored]}, {:tuple, [:atom, :any]}]},
      doc: """
      Instead of `:token`, to add one app to many workspaces. `:stored` keeps them in Wardrik,
      which needs Wardrik's `:keys`. `{module, config}` names a
      `Wardrik.Channel.Installations`.
      """
    ],
    approvers: [
      type: {:or, [{:list, :string}, {:in, [:anyone]}]},
      default: [],
      doc: """
      Who may decide what agents wait on, as the chat app names people, or `:anyone`. Whoever
      asked for a turn may always decide it.
      """
    ],
    offering: [type: :string, doc: "What a room with no agent is told."],
    deciding: [type: :string, doc: "What someone who may not decide is told."],
    server: [type: :atom, required: true, doc: false],
    wardrik: [type: :atom, required: true, doc: false],
    events: [type: :atom, required: true, doc: false],
    vault: [type: {:or, [:atom, nil]}, default: nil, doc: false],
    channel: [type: :string, required: true, doc: false],
    store: [type: :any, required: true, doc: false]
  ]

  @schema NimbleOptions.new!(@options)

  @enforce_keys [
    :name,
    :server,
    :wardrik,
    :events,
    :adapter,
    :store,
    :installations,
    :offering,
    :deciding,
    :options
  ]
  defstruct [vault: nil, approvers: []] ++ @enforce_keys

  @type t() :: %__MODULE__{
          name: String.t(),
          server: module(),
          wardrik: atom(),
          events: atom(),
          vault: atom() | nil,
          adapter: module(),
          store: WardrikStore.t(),
          installations: {module(), term()},
          offering: String.t(),
          deciding: String.t(),
          approvers: [String.t()] | :anyone,
          options: keyword()
        }

  @doc """
  Builds `adapter`'s channel from the options Wardrik passes it. See `WardrikChannel` for the
  options. The adapter reads the ones left over, from `:options`.

  Raises `NimbleOptions.ValidationError` on invalid options, or `ArgumentError` if the name isn't
  lower-case letters, digits and `-`, starting with a letter, or the options give neither or both
  of `:token` and `:installations`.
  """
  @spec new(module(), keyword()) :: t()
  def new(adapter, opts) do
    {own, options} = Keyword.split(opts, Keyword.keys(@options))
    own = NimbleOptions.validate!(own, @schema)
    name = Keyword.fetch!(own, :channel)
    named!(name)
    installations = installations!(name, own)
    vault = own[:vault]
    store = WardrikStore.scope(own[:store], "wardrik_channel")

    %__MODULE__{
      name: name,
      server: own[:server],
      wardrik: own[:wardrik],
      events: own[:events],
      vault: vault,
      adapter: adapter,
      store: store,
      installations: stored(installations, vault, store),
      offering: Keyword.get(own, :offering, offering(name)),
      deciding: Keyword.get(own, :deciding, deciding()),
      approvers: own[:approvers],
      options: options
    }
  end

  @doc false
  def schema, do: @schema

  @doc "Returns the channel's installation in `workspace`, as the chat app names it."
  @spec installation(t(), String.t()) :: {:ok, Installation.t()} | :error
  def installation(%__MODULE__{name: name, installations: {module, config}}, workspace),
    do: module.fetch(config, name, workspace)

  @doc """
  Returns the installation nearest the owner of agent `id`.

  Looks first for one owned by the user, as `acme/@jon`, then by the org, as `acme`. Returns
  `:error` if there's neither.
  """
  @spec nearest(t(), String.t()) :: {:ok, Installation.t()} | :error
  def nearest(%__MODULE__{name: name, installations: {module, config}}, id) do
    {:ok, %Wardrik.AgentID{owner: owner}} = Wardrik.AgentID.parse(id)
    owners = List.delete(Wardrik.Owners.chain(owner), Wardrik.Resource.deployment())

    case Enum.flat_map(owners, &module.owned(config, name, &1)) do
      [installation | _rest] -> {:ok, installation}
      [] -> :error
    end
  end

  @doc "Saves `installation`, replacing any for the same workspace."
  @spec install(t(), Installation.t()) :: :ok | {:error, String.t()}
  def install(%__MODULE__{installations: {module, config}}, installation),
    do: module.put(config, installation)

  @doc "Forgets the channel's installation in `workspace`."
  @spec uninstall(t(), String.t()) :: :ok
  def uninstall(%__MODULE__{name: name, installations: {module, config}}, workspace),
    do: module.delete(config, name, workspace)

  defp named!(name) do
    if not Regex.match?(~r/^[a-z][a-z0-9-]*$/, name),
      do:
        raise(
          ArgumentError,
          "A channel's name is lower-case letters, digits and -, starting with a letter. " <>
            "#{inspect(name)} isn't."
        )
  end

  defp installations!(name, opts) do
    case Keyword.take(opts, [:installations, :token]) do
      [installations: :stored] ->
        :stored

      [installations: {module, _config} = installations] when is_atom(module) ->
        installations

      [token: _token] ->
        {Token, Keyword.take(opts, [:token, :owner, :approvers])}

      _neither_or_both ->
        raise ArgumentError,
              "Give the channel #{name} a token: and an owner:, or its installations:."
    end
  end

  defp stored(:stored, vault, store), do: {Stored, vault: vault, store: store}
  defp stored(installations, _vault, _store), do: installations

  defp offering(name),
    do: "An agent answers here once its definition lists #{name} among its channels."

  defp deciding,
    do: "Only the channel's approvers, and whoever asked, may decide what an agent waits on."
end
