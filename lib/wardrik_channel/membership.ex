defmodule WardrikChannel.Membership do
  @moduledoc """
  What `c:WardrikChannel.include?/2` decides: whether `member`, in `installation`'s workspace, is
  one of `names`, as the chat app names people, such as `@maria`.

      %WardrikChannel.Membership{installation: installation, names: ["@maria"], member: member}
  """

  alias Wardrik.Channel.Installation
  alias WardrikChannel.Member

  @enforce_keys [:installation, :names, :member]
  defstruct [:installation, :names, :member]

  @type t() :: %__MODULE__{
          installation: Installation.t(),
          names: [String.t()],
          member: Member.t()
        }
end
