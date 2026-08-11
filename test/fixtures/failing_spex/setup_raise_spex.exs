defmodule SexySpex.Fixtures.SetupRaiseSpex do
  @moduledoc """
  A `setup` callback raises, so the test body never starts.

  `Reporter.start_spex/2` is the first line of the body, so the Reporter never
  learns this spex exists — there is no state to report against and no rescue to
  report from.
  """

  use SexySpex

  setup do
    raise "boom from setup"
  end

  spex "a setup callback raised" do
    scenario "this never runs" do
      then_ "unreachable", context do
        {:ok, context}
      end
    end
  end
end
