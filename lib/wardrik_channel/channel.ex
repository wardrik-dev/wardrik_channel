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

  @own [
    :server,
    :wardrik,
    :events,
    :vault,
    :channel,
    :store,
    :token,
    :owner,
    :approvers,
    :installations,
    :offering,
    :deciding
  ]

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
  options.

  Raises `ArgumentError` if the name isn't lower-case letters, digits and `-`, starting with a
  letter, or if the options give neither or both of `:token` and `:installations`.
  """
  @spec new(module(), keyword()) :: t()
  def new(adapter, opts) do
    name = Keyword.fetch!(opts, :channel)
    named!(name)
    installations = installations!(name, opts)
    vault = Keyword.get(opts, :vault)
    store = WardrikStore.scope(Keyword.fetch!(opts, :store), "wardrik_channel")

    %__MODULE__{
      name: name,
      server: Keyword.fetch!(opts, :server),
      wardrik: Keyword.fetch!(opts, :wardrik),
      events: Keyword.fetch!(opts, :events),
      vault: vault,
      adapter: adapter,
      store: store,
      installations: stored(installations, vault, store),
      offering: Keyword.get(opts, :offering, offering(name)),
      deciding: Keyword.get(opts, :deciding, deciding()),
      approvers: Keyword.get(opts, :approvers, []),
      options: Keyword.drop(opts, @own)
    }
  end

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
    [org | _rest] = String.split(owner, "/", parts: 2)

    case Enum.flat_map(Enum.uniq([owner, org]), &module.owned(config, name, &1)) do
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
