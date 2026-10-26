defmodule WardrikChannel.Offer do
  @moduledoc "An offer is an agent a channel may have answer in its rooms, with what it's for."

  @enforce_keys [:agent]
  defstruct [:agent, :name, :description]

  @type t() :: %__MODULE__{
          agent: String.t(),
          name: String.t() | nil,
          description: String.t() | nil
        }
end
