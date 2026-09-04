defmodule SelectoComponents.Views.Aggregate.GridSelection do
  @moduledoc false
  alias SelectoComponents.Form.{DrillDownFilters, ParamsState}
  @salt "selecto-grid-selection-v1"

  def token(endpoint, execution, axis, attributes) do
    params =
      Map.new(attributes, fn {key, value} ->
        {String.replace_prefix(key, "phx-value-", ""), value}
      end)

    Phoenix.Token.sign(endpoint, @salt, %{execution: execution, axis: axis, params: params})
  end

  def verify(endpoint, execution, alternatives)
      when is_list(alternatives) and length(alternatives) in 1..50 do
    Enum.reduce_while(alternatives, {:ok, []}, fn tokens, {:ok, acc} ->
      case verify_alternative(endpoint, execution, tokens) do
        {:ok, params} -> {:cont, {:ok, [params | acc]}}
        _ -> {:halt, {:error, :invalid_grid_selection}}
      end
    end)
    |> case do
      {:ok, params} -> {:ok, Enum.reverse(params)}
      error -> error
    end
  end

  def verify(_, _, _), do: {:error, :invalid_grid_selection}

  defp verify_alternative(endpoint, execution, tokens)
       when is_list(tokens) and length(tokens) in 1..2 do
    decoded =
      Enum.map(tokens, fn token ->
        if is_binary(token) and byte_size(token) <= 16_384,
          do: Phoenix.Token.verify(endpoint, @salt, token, max_age: 3_600),
          else: {:error, :invalid}
      end)

    payloads =
      Enum.flat_map(decoded, fn
        {:ok, %{execution: ^execution, axis: axis, params: params} = payload}
        when axis in [:row, :column] and is_map(params) ->
          [payload]

        _ ->
          []
      end)

    if length(payloads) == length(tokens) and
         length(Enum.uniq_by(payloads, & &1.axis)) == length(tokens),
       do: {:ok, Enum.reduce(payloads, %{}, &Map.merge(&2, &1.params))},
       else: {:error, :invalid}
  end

  defp verify_alternative(_, _, _), do: {:error, :invalid}

  def build_filters(existing, alternatives, socket) do
    union = UUID.uuid4()
    # Build each pair in its own AND section; never merge independent IN lists.
    empty = %{socket | assigns: put_in(socket.assigns, [:view_config, :filters], [])}

    branches =
      Enum.flat_map(alternatives, fn params ->
        branch = UUID.uuid4()

        children =
          Enum.map(DrillDownFilters.build_filter_tuples(params, empty), fn {id, _, config} ->
            {id, branch, Map.put(config, "promote", "false")}
          end)

        [{branch, union, "AND"} | children]
      end)

    existing ++ [{union, "filters", "OR"} | branches]
  end

  def apply(socket, alternatives) do
    execution = get_in(socket.assigns, [:view_meta, :exe_id])

    with true <- is_binary(execution),
         {:ok, params} <- verify(socket.endpoint, execution, alternatives) do
      config = socket.assigns.view_config
      filters = build_filters(config.filters, params, socket)
      config = %{config | filters: filters, view_mode: "detail"}
      view_params = ParamsState.view_config_to_params(config)
      socket = Phoenix.Component.assign(socket, :view_config, config)
      {:ok, ParamsState.view_from_params(view_params, socket), view_params}
    else
      _ -> {:error, :invalid_grid_selection}
    end
  end
end
