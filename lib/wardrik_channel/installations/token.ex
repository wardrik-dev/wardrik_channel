defmodule WardrikChannel.Installations.Token do
  @moduledoc """
  The single installation a channel's `token:` makes, in the workspace that token reaches.

      slack: {WardrikSlack, token: "xoxb-...", owner: "acme", approvers: ["@maria"]}

  Adding other installations returns an error. Forgetting one does nothing. Found by its owner,
  its workspace is `"*"`.
  """

  @behaviour Wardrik.Channel.Installations

  alias Wardrik.Channel.Installation

  @impl Wardrik.Channel.Installations
  def fetch(config, channel, workspace) do
    {:ok,
     %Installation{
       channel: channel,
       workspace: workspace,
       owner: Keyword.fetch!(config, :owner),
       token: Keyword.fetch!(config, :token),
       approvers: Keyword.get(config, :approvers, [])
     }}
  end

  @impl Wardrik.Channel.Installations
  def owned(config, channel, owner) do
    if Keyword.fetch!(config, :owner) == owner,
      do: [elem(fetch(config, channel, "*"), 1)],
      else: []
  end

  @impl Wardrik.Channel.Installations
  def put(_config, %Installation{channel: channel}),
    do: {:error, "#{channel} is added with its token, and in no other way."}

  @impl Wardrik.Channel.Installations
  def delete(_config, _channel, _workspace), do: :ok
end
