defmodule SelectoComponents.QueryLibrary do
  @moduledoc """
  Adapts a domain-owned `Selecto.QueryLibrary` to editable component state.

  Named views seed the Detail explorer's columns and ordering. Their named
  segments, plus any additional selected segments, remain active as governed
  query constraints when the visual query is rebuilt.
  """

  @empty_selection %{view: nil, segments: [], parameters: %{}}

  @spec available?(Selecto.t() | map()) :: boolean()
  def available?(selecto_or_domain) do
    library = Selecto.query_library(selecto_or_domain)
    Enum.any?([:segments, :views], &(map_size(Map.get(library, &1, %{})) > 0))
  end

  @spec selection(map()) :: map()
  def selection(view_config) when is_map(view_config) do
    view_config
    |> map_value(:query_library, @empty_selection)
    |> normalize_selection()
  end

  def selection(_view_config), do: @empty_selection

  @spec normalize_selection(term()) :: map()
  def normalize_selection(value) when is_map(value) do
    %{
      view: normalize_optional_id(map_value(value, :view)),
      segments:
        value
        |> map_value(:segments, [])
        |> normalize_ids(),
      parameters:
        value
        |> map_value(:parameters, map_value(value, :params, %{}))
        |> normalize_parameters()
    }
  end

  def normalize_selection(_value), do: @empty_selection

  @spec entries(Selecto.t() | map(), :segments | :views) :: [map()]
  def entries(selecto_or_domain, registry) when registry in [:segments, :views] do
    selecto_or_domain
    |> Selecto.query_library()
    |> Map.get(registry, %{})
    |> Enum.map(fn {id, spec} ->
      %{
        id: to_string(id),
        label: metadata(spec, :label) || humanize(id),
        description: metadata(spec, :description),
        capability: metadata(spec, :capability)
      }
    end)
    |> Enum.sort_by(&{String.downcase(&1.label), &1.id})
  end

  @spec parameter_entries(Selecto.t() | map(), map()) :: [map()]
  def parameter_entries(selecto_or_domain, selection) do
    library = Selecto.query_library(selecto_or_domain)
    selection = normalize_selection(selection)

    segment_ids =
      selection.segments ++
        case fetch_definition(library.views, selection.view) do
          nil -> []
          view -> List.wrap(map_value(view, :segments))
        end

    segment_ids
    |> Enum.reduce(%{}, fn segment_id, acc ->
      collect_segment_parameters(library, segment_id, acc, [])
    end)
    |> Enum.map(fn {id, spec} ->
      %{
        id: id,
        label: metadata(spec, :label) || humanize(id),
        type: spec |> map_value(:type, "string") |> to_string(),
        required: truthy?(map_value(spec, :required, not has_key?(spec, :default))),
        default: map_value(spec, :default),
        description: metadata(spec, :description)
      }
    end)
    |> Enum.sort_by(&{String.downcase(&1.label), &1.id})
  end

  @doc "Normalizes library state and materializes a named view as Detail builder state."
  @spec apply_preset(map(), Selecto.t()) :: map()
  def apply_preset(view_config, selecto) when is_map(view_config) and is_map(selecto) do
    selected = selection(view_config)
    view_config = Map.put(view_config, :query_library, selected)

    case fetch_definition(Selecto.query_library(selecto).views, selected.view) do
      nil ->
        view_config

      view ->
        projection = map_value(view, :projection)
        ordering = map_value(view, :ordering)

        if is_nil(projection) and is_nil(ordering) do
          view_config
        else
          detail =
            view_config
            |> map_value(:views, %{})
            |> map_value(:detail, %{})
            |> maybe_put_selected(selecto, projection)
            |> maybe_put_ordering(selecto, ordering)

          views = view_config |> map_value(:views, %{}) |> Map.put(:detail, detail)

          view_config
          |> Map.put(:views, views)
          |> Map.put(:view_mode, "detail")
        end
    end
  end

  def apply_preset(view_config, _selecto), do: view_config

  @doc "Materializes a named view only when the selected preset changed."
  @spec apply_preset_if_changed(map(), Selecto.t(), map()) :: map()
  def apply_preset_if_changed(view_config, selecto, previous_view_config) do
    if selection(view_config).view == selection(previous_view_config).view do
      view_config
    else
      apply_preset(view_config, selecto)
    end
  end

  @doc "Applies the selected named segments to a rebuilt Selecto query."
  @spec apply_segments(Selecto.t(), map()) :: Selecto.t()
  def apply_segments(selecto, selection) do
    selection = normalize_selection(selection)
    library = Selecto.query_library(selecto)

    view_segments =
      case selection.view do
        nil ->
          []

        view_id ->
          library.views
          |> fetch_definition!(view_id, :view)
          |> map_value(:segments)
          |> List.wrap()
      end

    segment_ids = Enum.uniq_by(view_segments ++ selection.segments, &to_string/1)

    parameter_specs =
      Enum.reduce(segment_ids, %{}, fn id, specs ->
        collect_segment_parameters(library, id, specs, [])
      end)

    unknown_parameters = Map.keys(selection.parameters) -- Map.keys(parameter_specs)

    if unknown_parameters != [] do
      raise ArgumentError,
            "unknown query-library parameters: #{inspect(Enum.sort(unknown_parameters))}"
    end

    Enum.reduce(segment_ids, selecto, fn id, acc ->
      parameter_names =
        library
        |> collect_segment_parameters(id, %{}, [])
        |> Map.keys()

      params = Map.take(selection.parameters, parameter_names)
      Selecto.apply_segment(acc, id, params)
    end)
  end

  @spec input_type(String.t()) :: String.t()
  def input_type(type) when type in ["integer", "float", "decimal"], do: "number"
  def input_type("date"), do: "date"

  def input_type(type) when type in ["datetime", "naive_datetime", "utc_datetime"],
    do: "datetime-local"

  def input_type("boolean"), do: "checkbox"
  def input_type(_type), do: "text"

  defp maybe_put_selected(detail, _selecto, nil), do: detail

  defp maybe_put_selected(detail, selecto, projection_id) do
    fields = projection_fields(Selecto.query_library(selecto), projection_id, [])

    required =
      selecto
      |> Selecto.domain()
      |> map_value(:required_selected, [])
      |> List.wrap()
      |> Enum.map(&to_string/1)

    fields = Enum.uniq(required ++ fields)

    Map.put(
      detail,
      :selected,
      Enum.with_index(fields, fn field, index ->
        {stable_id("projection", index, field), field, %{"alias" => "", "format" => ""}}
      end)
    )
  end

  defp maybe_put_ordering(detail, _selecto, nil), do: detail

  defp maybe_put_ordering(detail, selecto, ordering_id) do
    library = Selecto.query_library(selecto)
    ordering = fetch_definition!(library.orderings, ordering_id, :ordering)

    required =
      selecto
      |> Selecto.domain()
      |> map_value(:required_order_by, [])
      |> List.wrap()

    orders = Enum.uniq(required ++ List.wrap(map_value(ordering, :order_by)))

    Map.put(
      detail,
      :order_by,
      Enum.with_index(orders, fn order, index ->
        {field, direction} = normalize_order!(order)
        {stable_id("ordering", index, field), field, %{"dir" => direction}}
      end)
    )
  end

  defp projection_fields(library, projection_id, stack) do
    id = to_string(projection_id)

    if id in stack do
      raise ArgumentError,
            "query-library projection cycle detected: #{Enum.join(stack ++ [id], " -> ")}"
    end

    projection = fetch_definition!(library.projections, projection_id, :projection)

    included =
      projection
      |> map_value(:projections, [])
      |> List.wrap()
      |> Enum.flat_map(&projection_fields(library, &1, stack ++ [id]))

    fields = projection |> map_value(:fields, []) |> List.wrap() |> Enum.map(&to_string/1)

    associations =
      projection
      |> map_value(:associations, [])
      |> List.wrap()
      |> Enum.flat_map(&association_fields(&1, nil))

    Enum.uniq(included ++ fields ++ associations)
  end

  defp association_fields(association, parent) when is_map(association) do
    name = association |> map_value(:name) |> to_string()
    path = if parent, do: "#{parent}.#{name}", else: name

    fields =
      association
      |> map_value(:fields, [])
      |> List.wrap()
      |> Enum.map(&"#{path}.#{&1}")

    nested =
      association
      |> map_value(:associations, [])
      |> List.wrap()
      |> Enum.flat_map(&association_fields(&1, path))

    fields ++ nested
  end

  defp association_fields(_association, _parent), do: []

  defp collect_segment_parameters(library, segment_id, acc, stack) do
    id = to_string(segment_id)

    if id in stack do
      raise ArgumentError,
            "query-library segment cycle detected: #{Enum.join(stack ++ [id], " -> ")}"
    end

    segment = fetch_definition!(library.segments, segment_id, :segment)

    acc =
      Enum.reduce(map_value(segment, :parameters, %{}), acc, fn {parameter_id, spec}, params ->
        key = to_string(parameter_id)

        case Map.fetch(params, key) do
          :error -> Map.put(params, key, spec)
          {:ok, ^spec} -> params
          {:ok, _other} -> raise ArgumentError, "conflicting query-library parameter #{key}"
        end
      end)

    references =
      List.wrap(map_value(segment, :segments)) ++
        (segment
         |> map_value(:segment_groups, [])
         |> List.wrap()
         |> Enum.flat_map(fn group -> List.wrap(map_value(group, :segments)) end))

    Enum.reduce(references, acc, fn child, params ->
      collect_segment_parameters(library, child, params, stack ++ [id])
    end)
  end

  defp normalize_order!({field, direction}),
    do: {to_string(field), normalize_direction!(direction)}

  defp normalize_order!([field, direction]),
    do: {to_string(field), normalize_direction!(direction)}

  defp normalize_order!(order),
    do: raise(ArgumentError, "invalid query-library ordering entry: #{inspect(order)}")

  defp normalize_direction!(direction) when direction in [:asc, "asc"], do: "asc"
  defp normalize_direction!(direction) when direction in [:desc, "desc"], do: "desc"

  defp normalize_direction!(direction),
    do: raise(ArgumentError, "invalid query-library ordering direction: #{inspect(direction)}")

  defp fetch_definition(_registry, nil), do: nil
  defp fetch_definition(_registry, ""), do: nil

  defp fetch_definition(registry, id) when is_map(registry) do
    target = to_string(id)

    Enum.find_value(registry, fn {candidate, spec} ->
      if to_string(candidate) == target and is_map(spec), do: spec
    end)
  end

  defp fetch_definition(_registry, _id), do: nil

  defp fetch_definition!(registry, id, kind) do
    fetch_definition(registry, id) ||
      raise ArgumentError, "unknown query-library #{kind} #{inspect(id)}"
  end

  defp stable_id(kind, index, field) do
    digest = :crypto.hash(:sha256, "#{kind}:#{index}:#{field}") |> Base.encode16(case: :lower)
    "query-library-#{String.slice(digest, 0, 16)}"
  end

  defp normalize_optional_id(nil), do: nil
  defp normalize_optional_id(""), do: nil
  defp normalize_optional_id(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_optional_id(value) when is_binary(value), do: String.trim(value)
  defp normalize_optional_id(_value), do: nil

  defp normalize_ids(values) when is_list(values) do
    values
    |> Enum.map(&normalize_optional_id/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp normalize_ids(values) when is_map(values) do
    values
    |> Enum.filter(fn {_id, selected?} -> truthy?(selected?) end)
    |> Enum.map(fn {id, _selected?} -> to_string(id) end)
    |> Enum.uniq()
  end

  defp normalize_ids(value) do
    case normalize_optional_id(value) do
      nil -> []
      id -> [id]
    end
  end

  defp normalize_parameters(parameters) when is_map(parameters) do
    Map.new(parameters, fn {id, value} -> {to_string(id), normalize_parameter_value(value)} end)
  end

  defp normalize_parameters(_parameters), do: %{}

  defp normalize_parameter_value(values) when is_list(values), do: List.last(values)
  defp normalize_parameter_value(value), do: value

  defp metadata(spec, key) when is_map(spec) do
    case map_value(spec, key) do
      value when is_binary(value) -> String.trim(value) |> blank_to_nil()
      value when is_atom(value) -> Atom.to_string(value)
      _ -> nil
    end
  end

  defp metadata(_spec, _key), do: nil

  defp humanize(value), do: value |> to_string() |> Phoenix.Naming.humanize()
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
  defp truthy?(value), do: value in [true, 1, "1", "true", "TRUE", "on", "yes"]

  defp has_key?(map, key) when is_map(map),
    do: Map.has_key?(map, key) or Map.has_key?(map, to_string(key))

  defp has_key?(_map, _key), do: false

  defp map_value(map, key, default \\ nil)

  defp map_value(map, key, default) when is_map(map),
    do: Map.get(map, key, Map.get(map, to_string(key), default))

  defp map_value(_map, _key, default), do: default
end
