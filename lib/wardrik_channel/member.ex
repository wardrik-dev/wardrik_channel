defmodule WardrikChannel.Member do
  @moduledoc """
  Someone in a workspace: the chat app's `id` for them, and the `name` it shows.

  Wardrik sees them as the principal `channel:workspace/id`, as `slack:T0123/U024BE7LH`.
  """

  @enforce_keys [:id]
  defstruct [:id, :name]

  @type t() :: %__MODULE__{id: String.t(), name: String.t() | nil}
end
