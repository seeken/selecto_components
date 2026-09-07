defmodule SelectoComponents.RulePreviewTest do
  use ExUnit.Case, async: true

  alias Selecto.Rule.Contract
  alias SelectoComponents.RulePreview

  test "evaluates verified input rules locally but keeps candidate rules pending" do
    assert {:ok, contract} = Contract.compile(domain())
    projection = Contract.project(contract)

    assert {:ok, %{disposition: :failed, local_eligible: true, server_required: true}} =
             RulePreview.preview(projection, :input, %{"quantity" => 0}, operation: :insert)

    assert {:ok,
            %{
              disposition: :pending,
              local_eligible: false,
              server_required: true,
              obligations: [%{binding_id: "candidate_quantity", code: :server_required}]
            }} =
             RulePreview.preview(projection, :candidate, %{"quantity" => 0}, operation: :insert)
  end

  test "rejects a projection whose fingerprint was replaced" do
    assert {:ok, contract} = Contract.compile(domain())
    projection = Contract.project(contract) |> Map.put("fingerprint", "sha256:forged")

    assert {:error, {:invalid_rule_projection, [%{code: :invalid_rule_projection}]}} =
             RulePreview.preview(projection, :input, %{"quantity" => 1}, operation: :insert)
  end

  defp domain do
    %{
      source: %{
        source_table: "items",
        primary_key: :id,
        fields: [:id, :quantity],
        columns: %{id: %{type: :integer}, quantity: %{type: :integer}},
        associations: %{}
      },
      schemas: %{},
      writes: %{
        operations: %{insert: %{enabled: true}},
        fields: %{quantity: %{insertable: true}}
      },
      rules: %{
        schema: "selecto.data_rules.v1",
        definitions: %{positive: %{version: 1, test: %{op: "number.gt", bound: 0}}},
        normalizers: %{},
        bindings: %{
          input_quantity: %{
            subject: %{scope: :input, path: [:quantity]},
            operations: [:insert],
            rule: %{id: :positive, version: 1}
          },
          candidate_quantity: %{
            subject: %{scope: :candidate, path: [:quantity]},
            operations: [:insert],
            rule: %{id: :positive, version: 1}
          }
        }
      }
    }
  end
end
