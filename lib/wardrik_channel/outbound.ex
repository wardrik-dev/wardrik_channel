defmodule WardrikChannel.Outbound do
  @moduledoc """
  An outbound message is what a channel's adapter is asked to post in a thread of a room, or in the
  room itself where `thread` is `nil`. Its `body` is one of:

    * `{:reply, text, answering}`, what the agent answered, and the ids of the messages it answers
    * `{:status, label}`, what the agent is doing, in a few words, until the next post
    * `{:stopped, answering}`, that a run stopped before it answered those messages
    * `{:waiting, [%WardrikChannel.Waiting{}]}`, the calls the agent waits on a person for
    * `{:failed, reason}`, why a run failed
    * `{:said, text}`, a line about what happened, as who decided a call
    * `{:notice, %Wardrik.Notice{}}`, what an agent did while nobody watched, posted in the room;
      `WardrikChannel.Waiting.from_notice/1` reads a parked turn's calls from it

  `approvers` are whom a waiting call asks, as the channel names people. An adapter that can ask
  each of them directly does, and says in the thread who it waits on.
  """

  @enforce_keys [:installation, :room, :thread, :body]
  defstruct [:installation, :room, :thread, :body, approvers: []]

  @type body() ::
          {:reply, String.t(), [String.t()]}
          | {:status, String.t()}
          | {:stopped, [String.t()]}
          | {:waiting, [WardrikChannel.Waiting.t()]}
          | {:failed, String.t()}
          | {:said, String.t()}
          | {:notice, Wardrik.Notice.t()}

  @type t() :: %__MODULE__{
          installation: Wardrik.Channel.Installation.t(),
          room: String.t(),
          thread: String.t() | nil,
          body: body(),
          approvers: [String.t()] | :anyone
        }
end
