defmodule WardrikChannel.Installations.Stored do
  @moduledoc """
  Installations kept in the Wardrik: each workspace's owner and approvers in its store, and its
  token sealed in its vault, as a secret of the owner's. A channel takes them as
  `installations: :stored`, for one app added to many workspaces, one for each org. The Wardrik
  needs `:keys` to seal tokens with.
  """

  @behaviour WardrikChannel.Installations

  alias WardrikChannel.Installation

  @impl WardrikChannel.Installations
  def fetch(config, channel, workspace) do
    with %{"owner" => owner, "approvers" => approvers} <-
           WardrikStore.get(store(config), key(channel, workspace)),
         {:ok, token} <- Wardrik.fetch_secret(config[:wardrik], owner, secret(channel, workspace)) do
      {:ok,
       %Installation{
         channel: channel,
         workspace: workspace,
         owner: owner,
         token: token,
         approvers: approvers(approvers)
       }}
    else
      _missing -> :error
    end
  end

  @impl WardrikChannel.Installations
  def owned(config, channel, owner) do
    prefix = key(channel, "")
    store = store(config)

    for key <- WardrikStore.keys(store, prefix),
        %{"owner" => ^owner} <- [WardrikStore.get(store, key)],
        {:ok, installation} <- [fetch(config, channel, String.replace_prefix(key, prefix, ""))],
        do: installation
  end

  @impl WardrikChannel.Installations
  def put(
        config,
        %Installation{channel: channel, workspace: workspace, owner: owner} = installation
      ) do
    kept = %{"owner" => owner, "approvers" => kept_approvers(installation.approvers)}

    with :ok <-
           Wardrik.put_secret(
             config[:wardrik],
             owner,
             secret(channel, workspace),
             installation.token
           ),
         {:ok, _vsn} <- WardrikStore.put(store(config), key(channel, workspace), kept) do
      :ok
    else
      {:error, reason} -> {:error, "#{channel} wasn't kept for #{workspace}: #{inspect(reason)}"}
    end
  end

  @impl WardrikChannel.Installations
  def delete(config, channel, workspace) do
    case WardrikStore.get(store(config), key(channel, workspace)) do
      %{"owner" => owner} ->
        :ok = Wardrik.delete_secret(config[:wardrik], owner, secret(channel, workspace))
        WardrikStore.delete(store(config), key(channel, workspace))

      nil ->
        :ok
    end
  end

  defp approvers("anyone"), do: :anyone
  defp approvers(names), do: names

  defp kept_approvers(:anyone), do: "anyone"
  defp kept_approvers(names), do: names

  defp store(config), do: Keyword.fetch!(config, :store)
  defp key(channel, workspace), do: "installations/#{channel}/#{workspace}"
  defp secret(channel, workspace), do: "#{channel}:#{workspace}"
end
