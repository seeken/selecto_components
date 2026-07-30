defmodule SelectoComponents.Verification.ActionVisibilityTest do
  use ExUnit.Case, async: true

  test "proves capability visibility monotonicity" do
    report = SelectoComponents.Verification.ActionVisibility.verify()

    assert report.state_count == 9
    assert report.invariant_count == 2
    assert report.check_count == 18
    assert report.proved?, inspect(report.counterexamples, pretty: true)
  end
end
