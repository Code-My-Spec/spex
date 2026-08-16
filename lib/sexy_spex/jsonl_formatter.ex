defmodule SexySpex.JsonlFormatter do
  @moduledoc """
  Makes the `--jsonl` failure list complete.

  `SexySpex.Reporter` writes a JSONL line from the `rescue` inside the `spex`
  macro, which means it only ever sees failures that unwind through the test
  process as exceptions. Two common failures never get there:

    * **The test process is taken down by an exit signal.** A linked process —
      typically a LiveView or a GenServer the spex is driving — crashes, and the
      test process dies from the signal without unwinding. `rescue` does not run
      (and neither would `catch`: an exit signal from a linked process is not a
      throw). No line is written.

    * **A `setup` or `setup_all` callback raises.** The test body never starts,
      so `Reporter.start_spex/2` is never called and there is nothing to report
      against.

  ExUnit knows about both. This formatter accumulates every failure ExUnit
  reports, and at `:suite_finished` appends a line for each one the Reporter did
  not already write.

  ## Why a silently short list is worse than a noisy one

  A consumer reads the JSONL as *the* failure list. When a spex dies by exit
  signal it vanishes from that list while still failing the run, so the only
  evidence left is the nonzero exit code. Worse, whatever global state that spex
  had staged in a `try/after` is never restored — the `after` does not run
  either — so later spex fail for its reasons while it is invisible. The
  failures those later spex report are genuinely theirs and correctly named; the
  cause is simply nowhere in the file. Chasing that costs a day.

  ## What a backstop line claims

  Only what ExUnit vouches for: the spex name from the test name, the file and
  line from the test's own tags, and the failure ExUnit recorded. `scenario` is
  `nil` and `steps` is empty, because a spex that died in `setup` or by signal
  has no scenario that can be named — and naming the wrong one is worse than
  naming none.
  """

  use GenServer

  alias SexySpex.Reporter

  @test_name_prefix "test Spex: "

  @impl true
  def init(_opts) do
    {:ok, %{failures: []}}
  end

  @impl true
  def handle_cast({:test_finished, %ExUnit.Test{state: {:failed, _}} = test}, state) do
    {:noreply, %{state | failures: [test | state.failures]}}
  end

  # `:invalid` is how ExUnit marks every test in a module whose `setup_all`
  # raised. The reason hangs off the module, not the test.
  def handle_cast({:test_finished, %ExUnit.Test{state: {:invalid, _}} = test}, state) do
    {:noreply, %{state | failures: [test | state.failures]}}
  end

  def handle_cast({:suite_finished, _}, state) do
    if enabled?(), do: write_missing(state.failures)
    {:noreply, state}
  end

  def handle_cast(_event, state), do: {:noreply, state}

  defp enabled? do
    Application.get_env(:sexy_spex, :jsonl_enabled, false)
  end

  defp path do
    Application.get_env(:sexy_spex, :jsonl_path, "spex_failures.jsonl")
  end

  # A formatter that raises takes the suite's reporting down with it, so a
  # backstop failing to write must not also lose the results that did write.
  defp write_missing(failures) do
    already = written_counts(path())

    failures
    |> Enum.reverse()
    |> Enum.reduce(already, fn test, counts ->
      name = spex_name(test)

      case Map.get(counts, name, 0) do
        0 ->
          Reporter.write_jsonl_line(backstop_failure(test, name))
          counts

        n ->
          Map.put(counts, name, n - 1)
      end
    end)

    :ok
  rescue
    error ->
      IO.warn("SexySpex.JsonlFormatter could not write missing failures: #{inspect(error)}")
      :ok
  end

  # Counted, not a set: one module can hold several spex, and two of them
  # failing under the same name must consume two written lines.
  defp written_counts(path) do
    case File.read(path) do
      {:ok, content} ->
        content
        |> String.split("\n", trim: true)
        |> Enum.reduce(%{}, fn line, acc ->
          case Jason.decode(line) do
            {:ok, %{"spex" => name}} when is_binary(name) -> Map.update(acc, name, 1, &(&1 + 1))
            _ -> acc
          end
        end)

      {:error, _} ->
        %{}
    end
  end

  defp spex_name(%ExUnit.Test{name: name}) do
    case Atom.to_string(name) do
      @test_name_prefix <> rest -> rest
      other -> other
    end
  end

  defp backstop_failure(test, name) do
    %{
      type: "failure",
      spex: name,
      scenario: nil,
      steps: [],
      error: %{
        message: message(test.state),
        file: test.tags[:file],
        line: test.tags[:line],
        stacktrace: Reporter.format_stacktrace(stacktrace(test.state))
      }
    }
  end

  defp message({:failed, failed}) when is_list(failed) do
    failed |> Enum.map_join("\n\n", &format_failure/1)
  end

  defp message({:invalid, %ExUnit.TestModule{state: {:failed, failed}}}) when is_list(failed) do
    "setup_all failed:\n\n" <> Enum.map_join(failed, "\n\n", &format_failure/1)
  end

  defp message({:invalid, _}), do: "test was not run: its setup_all failed"

  defp message(other), do: inspect(other)

  defp format_failure({:error, %{__exception__: true} = exception, _stack}),
    do: Exception.message(exception)

  # How ExUnit records a test killed by a linked process: the *kind* is
  # `{:EXIT, pid}` — not `:error` or `:exit` — and the reason is the dead
  # process's. Left to `inspect/1` the whole thing comes out as a struct literal
  # with a raw stacktrace list printed inside it, unreadable in exactly the case
  # where reading it matters most.
  defp format_failure({{:EXIT, pid}, reason, _stack}),
    do: "** (EXIT from #{inspect(pid)}) " <> Exception.format_exit(reason)

  defp format_failure({:exit, reason, _stack}), do: "** (EXIT) " <> Exception.format_exit(reason)

  defp format_failure({:error, reason, _stack}), do: inspect(reason)

  defp format_failure({:throw, value, _stack}), do: "** (throw) " <> inspect(value)

  defp format_failure(other), do: inspect(other)

  defp stacktrace({:failed, [failure | _]}), do: failure_stacktrace(failure)

  defp stacktrace({:invalid, %ExUnit.TestModule{state: {:failed, [failure | _]}}}),
    do: failure_stacktrace(failure)

  defp stacktrace(_), do: []

  # The frames of a linked-process death are inside the exit reason, not beside
  # it — the outer stacktrace on that failure is empty.
  defp failure_stacktrace({{:EXIT, _pid}, {_reason, stack}, _outer}) when is_list(stack), do: stack

  defp failure_stacktrace({_kind, _reason, stack}) when is_list(stack), do: stack

  defp failure_stacktrace(_), do: []
end
