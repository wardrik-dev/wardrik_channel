# WardrikChannel

Chat apps people reach [Wardrik](https://hexdocs.pm/wardrik)'s agents through, such as Slack:
rooms, threads, replies and approvals. Each chat app is an adapter of its own, such as
[WardrikSlack](https://hexdocs.pm/wardrik_slack). This package is what every adapter shares.

## Install

You install an adapter, which brings this in:

```elixir
def deps do
  [
    {:wardrik_slack, "~> 0.1"}
  ]
end
```

## Wire it up

A channel is one chat app your Wardrik runs, by a name of your own. Give it the token it acts
with, and the owner whose agents answer there:

```elixir
defmodule MyApp.Wardrik do
  use Wardrik, otp_app: :my_app
end

config :my_app, MyApp.Wardrik,
  data_dir: "priv/wardrik",
  channels: [
    slack:
      {WardrikSlack,
       token: System.fetch_env!("SLACK_BOT_TOKEN"),
       signing_secret: System.fetch_env!("SLACK_SIGNING_SECRET"),
       owner: "acme",
       approvers: ["@maria"]}
  ]
```

What the chat app sends reaches your Wardrik at `POST /v1/channels/slack/{path}`, served by
[WardrikHTTP](https://hexdocs.pm/wardrik_http):

```elixir
forward "/", WardrikHTTP, wardrik: MyApp.Wardrik
```

Then list the channel in an agent's definition:

```elixir
scope = MyApp.Wardrik.as("acme/@maria", roles: [:owner], resources: ["acme/*"])

Wardrik.Agent.define(scope, "acme/triage",
  model: "anthropic:claude-haiku-4-5",
  description: "Triages incidents.",
  channels: ["slack"]
)
```

Invite the bot into a room. With one agent offered, it answers there from then on. Mention the
bot, and the agent answers in a thread under your message. Reply in the thread, and it answers
again without a mention.

## Threads

Each thread is a conversation of the agent's own, as `acme/triage/slack.T0123.C024BE91L.1696.1234`.
It runs on the agent's definition, with its own history. Everyone in the workspace may message the
owner's agents, as themselves, such as `slack:T0123/U024BE7LH`.

Replies come from the agents' logs. Each room is one process in your cluster, kept in the
Wardrik's store, so a reply delayed by a restart is still posted.

## Approvals

A call an agent waits on is posted in its thread, with its arguments, for someone to decide.
`approvers` may decide, as the adapter names people, or `:anyone`. Whoever asked for the turn
may always decide it. Anyone else is told who may.

## Many workspaces

`token:` adds the channel to the one workspace it reaches. To add one app to many workspaces,
one for each org, give it `installations: {module, config}`, a `WardrikChannel.Installations`
that keeps each workspace's token, owner and approvers.

## Rooms in the audit

Binding a room, and unbinding it, are recorded in the Wardrik's audit as `wardrik.room.bound` and
`wardrik.room.unbound`, with who did it.
