defmodule SexySpex.Fixtures.LinkedExitSpex do
  @moduledoc """
  A linked process crashes and takes the test process down with it.

  This is the shape a spex driving a LiveView or a GenServer hits: the crash
  happens in the other process, the test process is linked to it, and an exit
  signal kills it outright. Nothing unwinds — not `rescue`, not `catch`, not any
  `try/after` the test had open.
  """

  use SexySpex

  spex "a linked process crash kills the test" do
    scenario "the crash arrives as a signal, not an exception" do
      given_ "a linked process that raises", context do
        spawn_link(fn -> raise "boom from a linked process" end)

        # Long enough for the signal to arrive; the process is dead before this
        # returns, so nothing after it runs.
        Process.sleep(500)

        {:ok, context}
      end
    end
  end
end
