defmodule SelectoComponents.RulePreview do
  @moduledoc """
  Evaluates a verified server rule projection for immediate form feedback.

  This module never authorizes a write. Only `input` and `action_input` rules
  are evaluated locally; candidate, transaction, and evidence rules remain
  pending for the authoritative server boundary.
  """

  alias Selecto.Rule.{Contract, Evaluator}

  @local_stages ["input", "action_input"]
  @known_stages @local_stages ++ ["candidate", "transaction", "evidence"]

  @spec preview(map(), atom() | String.t(), map(), keyword()) ::
          {:ok, map()} | {:error, {:invalid_rule_projection, [map()]}}
  def preview(projection, stage, values, opts \\ [])

  def preview(projection, stage, values, opts) when is_map(values) and is_list(opts) do
    stage = to_string(stage)

    with {:ok, contract} <- Contract.compile_projection(projection) do
      if stage in @local_stages do
        result = Evaluator.evaluate(contract, stage, values, opts)

        {:ok,
         %{
           disposition: result.disposition,
           values: result.values,
           outcomes: result.outcomes,
           obligations: result.obligations,
           local_eligible: true,
           server_required: true
         }}
      else
        {:ok, server_required_result(contract, stage, values, opts)}
      end
    else
      {:error, errors} -> {:error, {:invalid_rule_projection, errors}}
    end
  end

  def preview(_projection, _stage, _values, _opts),
    do: {:error, {:invalid_rule_projection, []}}

  defp server_required_result(contract, stage, values, opts) do
    obligations =
      if stage in @known_stages do
        contract.bindings
        |> Enum.sort_by(fn {id, _binding} -> id end)
        |> Enum.flat_map(fn {_id, binding} ->
          if applies?(binding, stage, opts) do
            [
              %{
                binding_id: binding.id,
                stage: binding.stage,
                rule: binding.rule,
                enforcement: binding.enforcement,
                code: :server_required
              }
            ]
          else
            []
          end
        end)
      else
        []
      end

    %{
      disposition: if(required?(obligations), do: :pending, else: :passed),
      values: values,
      outcomes: [],
      obligations: obligations,
      local_eligible: false,
      server_required: obligations != []
    }
  end

  defp applies?(binding, stage, opts) do
    operation = opts |> Keyword.get(:operation) |> maybe_string()
    action = opts |> Keyword.get(:action) |> maybe_string()

    binding.stage == stage and
      (binding.operations == [] or operation in binding.operations) and
      (is_nil(binding.subject[:action]) or binding.subject.action == action)
  end

  defp required?(obligations), do: Enum.any?(obligations, &(&1.enforcement == "required"))
  defp maybe_string(nil), do: nil
  defp maybe_string(value), do: to_string(value)
end
