# Changelog

## 0.1.0-rc.1 (2026-10-30)

- Channels as adapters: `use WardrikChannel`, with `deliver/2`, `include?/4` and `children/1`.
- Rooms bound to the one agent offered, or one picked, answering mentions or every message, kept
  in Wardrik's store and recorded in its audit.
- Threads as conversations of the room's agent, asked as the person who wrote.
- Replies posted from the agents' logs by one process per room in the cluster, carrying on from
  where they were after a restart, and tried again when the chat app refuses them.
- Waiting calls posted with their arguments, decided by approvers or whoever asked.
- Installations: one from a `token:`, or your own for one app in many workspaces.
