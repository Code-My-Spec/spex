defmodule SexySpex.ErrorCaptureTest do
  use ExUnit.Case, async: false

  require Logger

  alias SexySpex.ErrorCapture

  setup do
    ErrorCapture.start()
    ErrorCapture.clear()
    on_exit(&ErrorCapture.stop/0)
    :ok
  end

  test "an error names the process that logged it" do
    Logger.error("the widget came apart")

    report = ErrorCapture.format_errors()

    assert report =~ "the widget came apart"
    assert report =~ inspect(self())
  end

  # The handler is global, so this is the case that matters: the spex that
  # raises is not necessarily the one that logged.
  test "an error logged by another process names that process, not the test" do
    parent = self()

    {:ok, pid} =
      Task.start(fn ->
        Logger.error("a straggler from somewhere else")
        send(parent, :logged)
      end)

    assert_receive :logged, 1_000

    report = ErrorCapture.format_errors()

    assert report =~ inspect(pid)
    refute report =~ inspect(self())
  end
end
