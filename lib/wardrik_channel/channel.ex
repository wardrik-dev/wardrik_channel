defmodule WardrikChannel.Channel do
  @moduledoc """
  A channel is one chat app a Wardrik runs, by the name it gives it: its adapter, its options, and
  the installations that say where it's added.
  """

  alias WardrikChannel.Installations

  @own [
    :wardrik,
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
    :wardrik,
    :adapter,
    :store,
    :installations,
    :offering,
    :deciding,
    :options
  ]
  defstruct @enforce_keys

  @type t() :: %__MODULE__{
          name: String.t(),
          wardrik: atom(),
          adapter: module(),
          store: WardrikStore.t(),
          installations: {module(), term()},
          offering: String.t(),
          deciding: String.t(),
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

    %__MODULE__{
      name: name,
      wardrik: Keyword.fetch!(opts, :wardrik),
      adapter: adapter,
      store: WardrikStore.scope(Keyword.fetch!(opts, :store), "wardrik_channel"),
      installations: installations,
      offering: Keyword.get(opts, :offering, offering(name)),
      deciding: Keyword.get(opts, :deciding, deciding()),
      options: Keyword.drop(opts, @own)
    }
  end

  @doc "Finds the channel's installation in `workspace`, as the chat app names it."
  @spec installation(t(), String.t()) :: {:ok, WardrikChannel.Installation.t()} | :error
  def installation(%__MODULE__{name: name, installations: {module, config}}, workspace),
    do: module.fetch(config, name, workspace)

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
      [installations: {module, _config} = installations] when is_atom(module) ->
        installations

      [token: _token] ->
        {Installations.Token, Keyword.take(opts, [:token, :owner, :approvers])}

      _neither_or_both ->
        raise ArgumentError,
              "Give the channel #{name} a token: and an owner:, or its installations:."
    end
  end

  defp offering(name),
    do: "An agent answers here once its definition lists #{name} among its channels."

  defp deciding,
    do: "Only the channel's approvers, and whoever asked, may decide what an agent waits on."
end
