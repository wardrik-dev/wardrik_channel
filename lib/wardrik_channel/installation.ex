defmodule WardrikChannel.Installation do
  @moduledoc """
  An installation is a channel added to one workspace, such as a Slack app added to one Slack
  workspace.

      %WardrikChannel.Installation{
        channel: "slack",
        workspace: "T0123",
        owner: "acme",
        token: "xoxb-...",
        approvers: ["@maria"]
      }

  `owner` is whose agents answer there: an org, as `acme`, or a person, as `acme/@jon`.
  `approvers` names who may decide what those agents wait on, as the channel names people, or is
  `:anyone`. With none named, whoever asked for a turn decides it.
  """

  @derive {Inspect, except: [:token]}
  @enforce_keys [:channel, :workspace, :owner, :token]
  defstruct [:channel, :workspace, :owner, :token, approvers: []]

  @type t() :: %__MODULE__{
          channel: String.t(),
          workspace: String.t(),
          owner: String.t(),
          token: String.t(),
          approvers: [String.t()] | :anyone
        }

  @doc "Returns the pattern of the owner's agents' resources, as `acme/agent/*`."
  @spec agents(t()) :: String.t()
  def agents(%__MODULE__{owner: owner}), do: owner <> "/agent/*"

  @doc "Returns whether `agent` is one of the owner's own agents."
  @spec covers?(t(), String.t()) :: boolean()
  def covers?(%__MODULE__{} = installation, agent) do
    case Wardrik.Resource.agent(agent) do
      {:ok, resource} -> WardrikEvents.Pattern.covers?(agents(installation), resource)
      :error -> false
    end
  end
end
