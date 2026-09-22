defmodule SelectoComponents.TemplateEvent do
  @moduledoc """
  Normalizes browser values against server-owned template event declarations.

  Event names come from trusted render metadata. Client parameters may contain
  exactly one `value`; they cannot choose a type or inject runtime identity.
  """

  @max_value_bytes 16_384
  @min_integer -9_223_372_036_854_775_808
  @max_integer 9_223_372_036_854_775_807

  @spec normalize(map(), binary(), map()) :: {:ok, map()} | {:error, map()}
  def normalize(%{"events" => events}, event_name, %{"value" => value} = params)
      when is_list(events) and is_binary(event_name) and map_size(params) == 1 do
    case Enum.find(events, &event_named?(&1, event_name)) do
      nil ->
        {:error, diagnostic("unknown_event", "template event is not declared")}

      %{"payload" => %{"value" => type}} when type in ["string", "integer", "boolean"] ->
        with {:ok, normalized} <- normalize_value(type, value) do
          {:ok, %{"value" => normalized}}
        end

      _declaration ->
        {:error, diagnostic("invalid_event_declaration", "template event declaration is invalid")}
    end
  end

  def normalize(%{"events" => events}, event_name, params)
      when is_list(events) and is_binary(event_name) and is_map(params) do
    if Enum.any?(events, &event_named?(&1, event_name)) do
      {:error, diagnostic("invalid_event_params", "template event parameters are invalid")}
    else
      {:error, diagnostic("unknown_event", "template event is not declared")}
    end
  end

  def normalize(_manifest, _event_name, _params),
    do: {:error, diagnostic("invalid_event_params", "template event parameters are invalid")}

  @spec max_value_bytes() :: pos_integer()
  def max_value_bytes, do: @max_value_bytes

  defp normalize_value("string", value) when is_binary(value) do
    cond do
      not String.valid?(value) ->
        {:error, diagnostic("invalid_event_value", "template event value is invalid")}

      byte_size(value) > @max_value_bytes ->
        {:error, diagnostic("event_value_too_large", "template event value is too large")}

      true ->
        {:ok, value}
    end
  end

  defp normalize_value("integer", value)
       when is_integer(value) and value >= @min_integer and value <= @max_integer,
       do: {:ok, value}

  defp normalize_value("integer", value) when is_binary(value) do
    with true <- byte_size(value) <= 20,
         true <- Regex.match?(~r/^(?:0|-[1-9][0-9]*|[1-9][0-9]*)$/, value),
         {integer, ""} <- Integer.parse(value),
         true <- integer >= @min_integer and integer <= @max_integer do
      {:ok, integer}
    else
      _other -> {:error, diagnostic("invalid_event_value", "template event value is invalid")}
    end
  end

  defp normalize_value("boolean", value) when is_boolean(value), do: {:ok, value}
  defp normalize_value("boolean", "true"), do: {:ok, true}
  defp normalize_value("boolean", "false"), do: {:ok, false}

  defp normalize_value(_type, _value),
    do: {:error, diagnostic("invalid_event_value", "template event value is invalid")}

  defp event_named?(%{"name" => name}, expected), do: name == expected
  defp event_named?(_declaration, _expected), do: false

  defp diagnostic(code, message) do
    %{
      "schema" => "selecto.template.diagnostic.v1",
      "severity" => "error",
      "code" => code,
      "message" => message,
      "path" => []
    }
  end
end
