defmodule WardrikChannel.Waiting do
  @moduledoc """
  A waiting call is one a thread's agent waits on a person for: the conversation it's in, the
  `Wardrik.Interrupt`, the call's arguments where they're known, and who asked for the turn, who
  may always decide it. An adapter puts the conversation, the interrupt's id and `asked_by` on its
  buttons, and hands them back to `WardrikChannel.decide/4`.
  """

  @enforce_keys [:conversation, :interrupt]
  defstruct [:conversation, :interrupt, :arguments, :asked_by]

  @type t() :: %__MODULE__{
          conversation: String.t(),
          interrupt: Wardrik.Interrupt.t(),
          arguments: term(),
          asked_by: String.t() | nil
        }
end
