defmodule WardrikChannel.StoredTest do
  use ExUnit.Case, async: true

  alias WardrikChannel.Channel
  alias WardrikChannel.Installation

  setup context do
    store = WardrikStore.ETS.new(name: :"store #{context.test}")
    name = :"wardrik #{context.test}"
    chat = [installations: :stored, approvers: ["@maria"], test: self()]

    start_supervised!({WardrikStore, store})

    start_supervised!(
      {Wardrik,
       Wardrik.new(
         name: name,
         store: store,
         keys: [WardrikVault.generate_key()],
         channels: [chat: {WardrikChannel.Test.Chat, chat}]
       )}
    )

    {:ok, channel} = WardrikChannel.fetch(name, "chat")
    %{channel: channel, wardrik: name}
  end

  test "keeps each workspace, with its token sealed", %{channel: channel, wardrik: wardrik} do
    assert channel.approvers == ["@maria"]
    assert Channel.installation(channel, "T1") == :error

    installation = %Installation{
      channel: "chat",
      workspace: "T1",
      owner: "acme",
      token: "xoxb-acme",
      approvers: :anyone
    }

    assert Channel.install(channel, installation) == :ok
    assert Channel.installation(channel, "T1") == {:ok, installation}
    assert Wardrik.fetch_secret(wardrik, "acme", "chat:T1") == {:ok, "xoxb-acme"}

    assert Channel.uninstall(channel, "T1") == :ok
    assert Channel.installation(channel, "T1") == :error
    assert Channel.uninstall(channel, "T1") == :ok
  end

  test "finds no channel by a name the Wardrik doesn't run", %{wardrik: wardrik} do
    assert WardrikChannel.fetch(wardrik, "teams") == :error
  end
end
