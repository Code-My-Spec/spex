defmodule SexySpex.Fixtures.OrdinaryFailureSpex do
  @moduledoc """
  Control. Fails the way the Reporter already handles: an assertion raises
  inside a scenario, unwinds through the `spex` macro's rescue, and gets a JSONL
  line with its scenario and steps attached.

  Its job in the test is to prove the backstop does not double-write.
  """

  use SexySpex

  spex "an ordinary assertion failure" do
    scenario "the assertion is false" do
      given_ "a value", context do
        {:ok, Map.put(context, :value, 1)}
      end

      then_ "it is not what we said", context do
        assert context.value == 2, "ordinary failure inside a scenario"
        {:ok, context}
      end
    end
  end
end
