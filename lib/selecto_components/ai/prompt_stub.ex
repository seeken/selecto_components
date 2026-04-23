defmodule SelectoComponents.AI.PromptStub do
  @moduledoc """
  Builds a copyable prompt stub for external AI tools.
  """

  @spec build(map()) :: String.t()
  def build(contract) when is_map(contract) do
    domain_id = get_in(contract, ["domain", "id"]) || "unknown_domain"
    view_modes = Enum.join(get_in(contract, ["context", "view_modes"]) || [], ", ")

    """
    You are helping build Selecto intent JSON.

    Use the provided query contract for domain: #{domain_id}
    Allowed view modes: #{view_modes}

    Rules:
    - return JSON only
    - use field IDs from the contract exactly
    - do not invent UUIDs or compact keys like k0/k1
    - prefer the smallest valid payload
    - do not generate SQL
    - if graph mode is requested, put graph settings under the graph object

    Return AI intent JSON matching this shape:
    {
      "intent_version": 1,
      "mode": "replace",
      "view_mode": "detail|aggregate|graph",
      "filters": [],
      "selected": [],
      "order_by": [],
      "group_by": [],
      "aggregate": [],
      "graph": {},
      "options": {},
      "explanation": "...",
      "warnings": []
    }
    """
    |> String.trim()
  end

  def build(_contract), do: ""
end
