defmodule SelectoComponents.Verification.ActionVisibility do
  @moduledoc """
  Bounded verification of capability-driven action visibility.

  It proves that combining target decisions with host policy always selects the
  more restrictive status, so stricter policy cannot reveal an action.
  """

  alias Selecto.Verification.BoundedModel
  alias SelectoComponents.Actions

  @statuses [:enabled, :disabled, :hidden]

  def verify do
    states =
      for explicit <- @statuses,
          resolver <- @statuses do
        %{
          explicit: explicit,
          resolver: resolver,
          actions:
            Actions.available(contract(),
              decisions: %{"approve" => %{status: explicit}},
              capability_resolver: fn _request -> decision(resolver) end
            )
        }
      end

    BoundedModel.check("selecto_components.action_visibility.v1", states, [
      {"effective_status_is_most_restrictive", &most_restrictive/1},
      {"hidden_actions_never_reappear", &hidden_never_reappears/1}
    ])
  end

  defp most_restrictive(state) do
    expected = Enum.max_by([state.explicit, state.resolver], &rank/1)

    actual =
      case state.actions do
        [] -> :hidden
        [action] -> String.to_existing_atom(action.status)
      end

    if actual == expected,
      do: :ok,
      else: {:error, %{expected: expected, actual: actual}}
  end

  defp hidden_never_reappears(%{explicit: :hidden, actions: []}), do: :ok
  defp hidden_never_reappears(%{resolver: :hidden, actions: []}), do: :ok
  defp hidden_never_reappears(%{explicit: :hidden} = state), do: {:error, state.actions}
  defp hidden_never_reappears(%{resolver: :hidden} = state), do: {:error, state.actions}
  defp hidden_never_reappears(_state), do: :ok

  defp rank(:enabled), do: 0
  defp rank(:disabled), do: 1
  defp rank(:hidden), do: 2

  defp decision(:enabled), do: Selecto.Capabilities.allow(:allowed)
  defp decision(:disabled), do: Selecto.Capabilities.deny(:denied)
  defp decision(:hidden), do: Selecto.Capabilities.hidden(:hidden)

  defp contract do
    %{
      "actions" => [
        %{
          "id" => "approve",
          "label" => "Approve",
          "scope" => "row",
          "capability" => "orders.approve",
          "execution" => %{"operation" => "update"}
        }
      ]
    }
  end
end
