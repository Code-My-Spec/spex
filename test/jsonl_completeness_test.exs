defmodule SexySpex.JsonlCompletenessTest do
  @moduledoc """
  The `--jsonl` file must list every failure the run counted.

  Driven through a real `mix spex` subprocess rather than by casting synthetic
  events at the formatter. The whole defect lives in failure shapes the Reporter
  never sees — an exit signal, a raise in `setup` — and a test that hand-builds
  `%ExUnit.Test{}` would only assert my guess at those shapes, which is the one
  thing that must not be guessed here.
  """

  use ExUnit.Case, async: false

  @moduletag timeout: 180_000

  @pattern "test/fixtures/failing_spex/*_spex.exs"

  setup do
    path = Path.join(System.tmp_dir!(), "sexy_spex_completeness_#{System.unique_integer([:positive])}.jsonl")
    on_exit(fn -> File.rm(path) end)
    {:ok, jsonl: path}
  end

  test "every failure the run counts gets a JSONL line", %{jsonl: jsonl} do
    {output, _status} = run_spex(jsonl)

    counted = failure_count(output)
    written = read_lines(jsonl)

    assert counted == 3,
           "fixtures should produce three failures, got #{inspect(counted)}:\n#{output}"

    assert length(written) == counted,
           """
           the JSONL is short: #{length(written)} lines for #{counted} failures.
           wrote: #{inspect(Enum.map(written, & &1["spex"]))}
           """
  end

  test "the failures the Reporter cannot see are named and attributed", %{jsonl: jsonl} do
    {_output, _status} = run_spex(jsonl)

    by_name = Map.new(read_lines(jsonl), &{&1["spex"], &1})

    exit_failure = by_name["a linked process crash kills the test"]
    setup_failure = by_name["a setup callback raised"]

    assert exit_failure, "the linked-exit spex is missing from the JSONL"
    assert setup_failure, "the setup-raise spex is missing from the JSONL"

    # The text of what actually killed it survives the trip through the signal,
    # rendered the way ExUnit renders it rather than inspected as a raw term —
    # an `inspect/1` of the reason buries the message in a struct literal with
    # the stacktrace list printed inline.
    assert exit_failure["error"]["message"] =~ "boom from a linked process"
    assert exit_failure["error"]["message"] =~ "** (EXIT from "
    assert exit_failure["error"]["message"] =~ "** (RuntimeError)"
    refute exit_failure["error"]["message"] =~ "%RuntimeError{"

    # The frames live inside the exit reason, not beside it.
    assert exit_failure["error"]["stacktrace"] != []

    assert setup_failure["error"]["message"] =~ "boom from setup"

    # Filed against its own spec file, from ExUnit's tags — not against whatever
    # the stacktrace happened to start with.
    assert exit_failure["error"]["file"] =~ "linked_exit_spex.exs"
    assert setup_failure["error"]["file"] =~ "setup_raise_spex.exs"

    # Claimed only where there is something to claim. A spex that died in setup
    # or by signal has no scenario, and naming the wrong one is worse than none.
    assert exit_failure["scenario"] == nil
    assert exit_failure["steps"] == []
  end

  test "a failure the Reporter already wrote is not written twice", %{jsonl: jsonl} do
    {_output, _status} = run_spex(jsonl)

    ordinary =
      jsonl
      |> read_lines()
      |> Enum.filter(&(&1["spex"] == "an ordinary assertion failure"))

    assert [line] = ordinary

    # The Reporter's line, not a backstop one: it carries the scenario and the
    # steps, which only the in-process reporter knows.
    assert line["scenario"] == "the assertion is false"
    assert line["steps"] != []
  end

  defp run_spex(jsonl) do
    System.cmd(
      "mix",
      ["spex", "--pattern", @pattern, "--jsonl=#{jsonl}"],
      cd: File.cwd!(),
      stderr_to_stdout: true,
      env: [{"MIX_ENV", "test"}]
    )
  end

  defp read_lines(path) do
    case File.read(path) do
      {:ok, content} ->
        content
        |> String.split("\n", trim: true)
        |> Enum.map(&Jason.decode!/1)

      {:error, _} ->
        []
    end
  end

  defp failure_count(output) do
    case Regex.run(~r/(\d+) tests?, (\d+) failures?/, strip_ansi(output)) do
      [_, _tests, failures] -> String.to_integer(failures)
      nil -> {:no_summary_line, output}
    end
  end

  defp strip_ansi(text), do: String.replace(text, ~r/\e\[[0-9;]*m/, "")
end
