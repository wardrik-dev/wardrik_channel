defmodule WardrikChannel.Member do
  @moduledoc """
  A member is someone in a workspace a channel is added to: the id the chat app knows them by, and
  the name it shows. To Wardrik they're the principal `channel:workspace/id`, as
  `slack:T0123/U024BE7LH`.
  """

  @enforce_keys [:id]
  defstruct [:id, :name]

  @type t() :: %__MODULE__{id: String.t(), name: String.t() | nil}
end
