defmodule WardrikChannel.Answer do
  @moduledoc """
  A member's answer to a call the agent waits on. Adapters pass it to `WardrikChannel.decide/2`
  when a button is pressed.

      %WardrikChannel.Answer{
        member: member,
        conversation: "acme/triage/slack.T0123.C024BE91L.1696.1234",
        interrupt: "int_1",
        decision: {:approve, "Looks fine."}
      }

    * `:member` - the `WardrikChannel.Member` who answered.
    * `:conversation` - the conversation's ID, from the `WardrikChannel.Waiting` on the button.
    * `:interrupt` - the interrupt's ID.
    * `:asked_by` - who asked for the turn. Optional.
    * `:decision` - `{:approve, note}` or `{:deny, reason}`. Either may be `nil`.
  """

  @enforce_keys [:member, :conversation, :interrupt, :decision]
  defstruct [:member, :conversation, :interrupt, :asked_by, :decision]

  @type t() :: %__MODULE__{
          member: WardrikChannel.Member.t(),
          conversation: String.t(),
          interrupt: String.t(),
          asked_by: String.t() | nil,
          decision: {:approve | :deny, String.t() | nil}
        }
end
