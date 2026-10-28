defmodule WardrikChannel.Channel do
  @moduledoc """
  A channel is one chat app a Wardrik runs, by the name it gives it: its adapter, its options, and
  the installations that say where it's added. The Wardrik hands it the `Wardrik.Server` that runs
  its operations, the events it follows and records changes in, and the vault it seals tokens in.
  """

  alias WardrikChannel.Installation
  alias WardrikChannel.Installations

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
  Builds the channel `adapter` runs from the options the Wardrik hands it. Raises where its name
  isn't lower-case letters, digits and `-`, or where it says nothing of where it's added.
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

  @doc "Finds the channel's installation in `workspace`, as the chat app names it."
  @spec installation(t(), String.t()) :: {:ok, Installation.t()} | :error
  def installation(%__MODULE__{name: name, installations: {module, config}}, workspace),
    do: module.fetch(config, name, workspace)

  @doc """
  Returns the installation nearest the agent `id`'s owner: one of its user, as `acme/@jon`, then
  one of its org, as `acme`. Returns `:error` where the channel is added to neither's workspace.
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

  @doc "Keeps `installation`, in place of any of the same workspace."
  @spec install(t(), Installation.t()) :: :ok | {:error, String.t()}
  def install(%__MODULE__{installations: {module, config}}, installation),
    do: module.put(config, installation)

  @doc "Forgets the channel's installation in `workspace`, as when the app is taken out of it."
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
        {Installations.Token, Keyword.take(opts, [:token, :owner, :approvers])}

      _neither_or_both ->
        raise ArgumentError,
              "Give the channel #{name} a token: and an owner:, or its installations:."
    end
  end

  defp stored(:stored, vault, store), do: {Installations.Stored, vault: vault, store: store}
  defp stored(installations, _vault, _store), do: installations

  defp offering(name),
    do: "An agent answers here once its definition lists #{name} among its channels."

  defp deciding,
    do: "Only the channel's approvers, and whoever asked, may decide what an agent waits on."
end
