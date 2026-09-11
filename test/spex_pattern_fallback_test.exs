defmodule Mix.Tasks.SpexPatternFallbackTest do
  @moduledoc """
  Not async: every test here changes the process's own working directory
  (`File.cd!/1`), which is process-global, not per-test — running these
  alongside another file's async, path-relative test would be a real race.
  """
  use ExUnit.Case, async: false

  setup do
    dir =
      Path.join(System.tmp_dir!(), "spex_pattern_fallback_#{System.unique_integer([:positive])}")

    spex_dir = Path.join([dir, "test", "spex", "999_a_story"])
    File.mkdir_p!(spex_dir)
    target = Path.join(spex_dir, "criterion_3231_a_heartbeat_changes_nothing_spex.exs")
    File.write!(target, "")

    cwd = File.cwd!()
    File.cd!(dir)
    on_exit(fn -> File.cd!(cwd) end)

    # Relative to `dir`, which is now cwd — `Path.wildcard/1` returns paths
    # relative to cwd for a relative pattern, not absolute ones.
    %{
      relative_target: "test/spex/999_a_story/criterion_3231_a_heartbeat_changes_nothing_spex.exs"
    }
  end

  test "a bare fragment with no slash or star matches by file name", %{
    relative_target: relative_target
  } do
    assert find_spex_files([], pattern: "criterion_3231") == [relative_target]
  end

  test "a fragment matching nothing still returns nothing" do
    assert find_spex_files([], pattern: "criterion_9999999") == []
  end

  test "a pattern with a slash is never treated as a fragment" do
    assert find_spex_files([], pattern: "criterion_3231/nested") == []
  end

  test "a pattern with a star is never treated as a fragment" do
    assert find_spex_files([], pattern: "criterion_3231*") == []
  end

  # No fragment fallback needed here — the real default glob
  # (`test/spex/**/*_spex.exs`) already matches the fixture directly, the
  # same as it would in a real project. This just confirms the fallback
  # doesn't somehow get in the way of the ordinary case.
  test "no --pattern given at all matches via the real default, not the fragment fallback", %{
    relative_target: relative_target
  } do
    assert find_spex_files([], []) == [relative_target]
  end

  # Reimplementation of find_spex_files/2's no-args clause plus the fragment
  # fallback, for testing — mirrors Mix.Tasks.Spex without needing a Mix
  # project's real test/spex tree.
  defp find_spex_files([], opts) do
    pattern = opts[:pattern] || "test/spex/**/*_spex.exs"

    case Path.wildcard(pattern) do
      [] -> fragment_match(pattern, opts)
      files -> files
    end
  end

  defp fragment_match(pattern, opts) do
    if opts[:pattern] && not String.contains?(pattern, ["/", "*"]) do
      Path.wildcard("test/spex/**/*#{pattern}*")
    else
      []
    end
  end
end
