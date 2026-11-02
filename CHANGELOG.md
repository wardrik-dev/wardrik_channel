# Changelog

## 0.1.0-rc.2 (2026-10-31)

- A channel's nearest installation is found along `Wardrik.Owners.chain/1`: the agent's owner,
  then their org.
- Options are validated with NimbleOptions, and documented from the schema. An adapter reads the
  ones left over from `:options`.

### Breaking

- `WardrikChannel` callbacks take what they act on, then the `WardrikChannel.Channel`:
  `deliver/2` the outbound, `include?/2` a `WardrikChannel.Membership`, `install_url/2` and
  `installed/2` a `WardrikChannel.Install`, and `uninstall/2` the workspace. The installation
  stores implement `Wardrik.Channel.Installations` rc.2.
- An install's token is sealed as a `:token`, and read only as one.
- `WardrikChannel.Channel.new/2` raises `NimbleOptions.ValidationError` on an invalid option.

## 0.1.0-rc.1 (2026-10-30)

- Channels as adapters: `use WardrikChannel`, with `deliver/2`, `include?/4` and `children/1`.
- Rooms bound to the one agent offered, or one picked, answering mentions or every message, kept
  in Wardrik's store and recorded in its audit.
- Threads as conversations of the room's agent, asked as the person who wrote.
- Replies posted from the agents' logs by one process per room in the cluster, carrying on from
  where they were after a restart, and tried again when the chat app refuses them.
- Waiting calls posted with their arguments, decided by approvers or whoever asked.
- Installations: one from a `token:`, or your own for one app in many workspaces.
