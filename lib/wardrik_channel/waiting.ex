defmodule WardrikChannel.Waiting do
  @moduledoc """
  A call the agent waits on a person to decide.

    * `:conversation` - the conversation it's in.
    * `:interrupt` - the `Wardrik.Interrupt`.
    * `:arguments` - the call's arguments, if known.
    * `:asked_by` - who asked for the turn. They may always decide it.

  Put `conversation`, the interrupt's `id` and `asked_by` on the buttons. Pass them back in a
  `WardrikChannel.Answer` to `WardrikChannel.decide/2` when one is pressed.
  """

  @enforce_keys [:conversation, :interrupt]
  defstruct [:conversation, :interrupt, :arguments, :asked_by]

  @type t() :: %__MODULE__{
          conversation: String.t(),
          interrupt: Wardrik.Interrupt.t(),
          arguments: term(),
          asked_by: String.t() | nil
        }

  @doc "Returns the calls a parked turn's `notice` waits on."
  @spec from_notice(Wardrik.Notice.t()) :: [t()]
  def from_notice(%Wardrik.Notice{agent: agent, calls: calls}),
    do:
      for(
        %{interrupt: interrupt, arguments: arguments} <- calls,
        do: %__MODULE__{conversation: agent, interrupt: interrupt, arguments: arguments}
      )
end
