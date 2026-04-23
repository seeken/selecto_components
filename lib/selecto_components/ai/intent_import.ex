defmodule SelectoComponents.AI.IntentImport do
  @moduledoc """
  Parses, validates, and previews AI intent JSON for import workflows.
  """

  alias SelectoComponents.AI.IntentPreview
  alias SelectoComponents.AI.IntentValidator

  @spec import(String.t(), map(), Phoenix.LiveView.Socket.t()) :: map()
  def import(raw_json, contract, socket) when is_binary(raw_json) and is_map(contract) do
    case Jason.decode(raw_json) do
      {:ok, decoded} when is_map(decoded) ->
        validation = IntentValidator.validate(decoded, contract)

        if validation.ok do
          %{
            ok: true,
            intent: decoded,
            validation: validation,
            preview: IntentPreview.build(decoded, socket)
          }
        else
          %{
            ok: false,
            intent: decoded,
            validation: validation,
            preview: nil
          }
        end

      {:ok, _decoded} ->
        invalid_payload_result()

      {:error, error} ->
        %{
          ok: false,
          intent: nil,
          validation: %{
            ok: false,
            errors: [
              %{
                "code" => "invalid_json",
                "path" => [],
                "message" => Exception.message(error),
                "severity" => "error"
              }
            ],
            warnings: []
          },
          preview: nil
        }
    end
  end

  def import(_raw_json, _contract, _socket), do: invalid_payload_result()

  defp invalid_payload_result do
    %{
      ok: false,
      intent: nil,
      validation: %{
        ok: false,
        errors: [
          %{
            "code" => "invalid_intent_json",
            "path" => [],
            "message" => "Imported AI payload must decode to a JSON object.",
            "severity" => "error"
          }
        ],
        warnings: []
      },
      preview: nil
    }
  end
end
