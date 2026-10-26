defmodule WardrikChannel.Installations.Token do
  @moduledoc """
  The one installation a channel's `token:` makes, in whichever workspace that token reaches. It
  takes `:token`, `:owner`, whose agents answer there, and `:approvers`. Adding or forgetting
  others is refused.
  """

  @behaviour WardrikChannel.Installations

  alias WardrikChannel.Installation

  @impl WardrikChannel.Installations
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

  @impl WardrikChannel.Installations
  def put(_config, %Installation{channel: channel}),
    do: {:error, "#{channel} is added with its token, and in no other way."}

  @impl WardrikChannel.Installations
  def delete(_config, _channel, _workspace), do: :ok
end
