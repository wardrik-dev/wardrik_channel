defmodule WardrikChannel.Binding do
  @moduledoc """
  A binding is the agent that answers in a room, and when: when mentioned, `:mentions`, or to
  every message, `:everything`.
  """

  @enforce_keys [:room, :agent]
  defstruct [:room, :agent, answers: :mentions]

  @type answers() :: :mentions | :everything

  @type t() :: %__MODULE__{room: String.t(), agent: String.t(), answers: answers()}
end
