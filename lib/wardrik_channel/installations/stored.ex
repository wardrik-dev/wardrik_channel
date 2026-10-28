defmodule WardrikChannel.Installations.Stored do
  @moduledoc """
  Installations kept in the Wardrik: each workspace's owner and approvers in its store, and its
  token sealed in its vault, as a secret of the owner's. A channel takes them as
  `installations: :stored`, for one app added to many workspaces, one for each org. The Wardrik
  needs `:keys` to seal tokens with.
  """

  @behaviour WardrikChannel.Installations

  alias WardrikChannel.Installation
  alias WardrikCore.Principal

  @impl WardrikChannel.Installations
  def fetch(config, channel, workspace) do
    with %{"owner" => owner, "approvers" => approvers} <-
           WardrikStore.get(store(config), key(channel, workspace)),
         {:ok, token} <- sealed(config, owner, secret(channel, workspace)) do
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

    with {:ok, _sealed} <- seal(config, owner, secret(channel, workspace), installation.token),
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
        :ok = unseal(config, owner, secret(channel, workspace))
        WardrikStore.delete(store(config), key(channel, workspace))

      nil ->
        :ok
    end
  end

  defp approvers("anyone"), do: :anyone
  defp approvers(names), do: names

  defp kept_approvers(:anyone), do: "anyone"
  defp kept_approvers(names), do: names

  defp sealed(config, owner, name), do: config |> vault() |> sealed_in(owner, name)

  defp sealed_in(nil, _owner, _name), do: {:error, :no_keys}
  defp sealed_in(vault, owner, name), do: WardrikVault.fetch(vault, %Principal{id: owner}, name)

  defp seal(config, owner, name, token), do: config |> vault() |> seal_in(owner, name, token)

  defp seal_in(nil, _owner, _name, _token), do: {:error, :no_keys}

  defp seal_in(vault, owner, name, token),
    do: WardrikVault.put(vault, %Principal{id: owner}, name, token)

  defp unseal(config, owner, name), do: config |> vault() |> unseal_in(owner, name)

  defp unseal_in(nil, _owner, _name), do: :ok
  defp unseal_in(vault, owner, name), do: WardrikVault.delete(vault, %Principal{id: owner}, name)

  defp vault(config), do: Keyword.get(config, :vault)

  defp store(config), do: Keyword.fetch!(config, :store)
  defp key(channel, workspace), do: "installations/#{channel}/#{workspace}"
  defp secret(channel, workspace), do: "#{channel}:#{workspace}"
end
