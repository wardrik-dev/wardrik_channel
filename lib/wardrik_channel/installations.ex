defmodule WardrikChannel.Installations do
  @moduledoc """
  Installations keep the workspaces a channel is added to, each with its token. A token is a
  secret, so keep it as you keep your others.

  A channel takes them as `installations: {module, config}`. Given a `token:` instead, it's added
  to the one workspace that token reaches; see `WardrikChannel.Installations.Token`.
  """

  alias WardrikChannel.Installation

  @doc "Finds the channel's installation in `workspace`, as the chat app names it."
  @callback fetch(config :: term(), channel :: String.t(), workspace :: String.t()) ::
              {:ok, Installation.t()} | :error

  @doc "Keeps `installation`, in place of any of the same channel and workspace."
  @callback put(config :: term(), Installation.t()) :: :ok | {:error, String.t()}

  @doc "Forgets the channel's installation in `workspace`. Forgetting none is `:ok`."
  @callback delete(config :: term(), channel :: String.t(), workspace :: String.t()) :: :ok
end
