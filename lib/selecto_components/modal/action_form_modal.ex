defmodule SelectoComponents.Modal.ActionFormModal do
  @moduledoc """
  Modal component for rendering a domain action as a form shell.

  Host applications still own action preview/apply execution. This component
  renders the action metadata, target row, request template, inputs, and
  confirmation affordance so Selecto result rows can open action forms through
  the existing detail-action modal path.
  """

  use Phoenix.LiveComponent
  alias SelectoComponents.Actions

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       action: %{},
       target: %{},
       record: %{},
       form_inputs: %{},
       confirmed: false,
       submitting: nil,
       last_request: nil,
       last_result: nil,
       last_error: nil
     )}
  end

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def render(assigns) do
    action = normalize_action(Map.get(assigns, :action, %{}))
    target = normalize_target(assigns)
    form_inputs = Map.get(assigns, :form_inputs, %{})

    base_request_inputs = merge_default_inputs(form_inputs, action)
    {inputs, _active_variant} = Actions.effective_inputs(action, base_request_inputs)

    request_inputs =
      base_request_inputs
      |> merge_input_defaults(inputs)
      |> normalize_inputs(inputs)

    {inputs, active_variant} = Actions.effective_inputs(action, request_inputs)

    request_template =
      Actions.request_template(action,
        target: target,
        inputs: request_inputs,
        confirmed: truthy?(Map.get(assigns, :confirmed))
      )

    applied? = applied_result?(Map.get(assigns, :last_result))
    disabled? = disabled_action?(action)
    controls_disabled? = disabled? || applied?

    assigns =
      assigns
      |> assign(:action, action)
      |> assign(:target, target)
      |> assign(:request_template, request_template)
      |> assign(:inputs, inputs)
      |> assign(:active_variant, active_variant)
      |> assign(:form_inputs, request_inputs)
      |> assign(
        :confirmation,
        Map.get(action, :confirmation, Map.get(action, "confirmation", %{}))
      )
      |> assign(:confirmed, truthy?(Map.get(assigns, :confirmed)))
      |> assign_new(:last_result, fn -> nil end)
      |> assign_new(:last_error, fn -> nil end)
      |> assign_new(:submitting, fn -> nil end)
      |> assign_new(:show_debug_json?, fn -> false end)
      |> assign(:applied?, applied?)
      |> assign(:disabled?, disabled?)
      |> assign(:controls_disabled?, controls_disabled?)
      |> assign(:disabled_reason, disabled_reason(action))
      |> assign(:action_status, action_status(disabled?, applied?))
      |> assign(:form_valid?, required_inputs_valid?(request_inputs, inputs))
      |> assign(:result_summary, result_summary(Map.get(assigns, :last_result)))
      |> assign(:reload_summary, reload_summary(Map.get(assigns, :last_result)))
      |> assign(:error_details, Map.get(assigns, :last_error_details))

    ~H"""
    <div
      data-selecto-action-form-modal
      data-action-id={Map.get(@action, :id) || Map.get(@action, "id")}
      data-action-capability={Map.get(@action, :capability) || Map.get(@action, "capability")}
      data-action-operation={Map.get(@action, :operation) || Map.get(@action, "operation")}
      data-action-scope={Map.get(@action, :scope) || Map.get(@action, "scope")}
      data-action-status={@action_status}
      data-action-submitting={@submitting}
      aria-busy={not is_nil(@submitting)}
      class="space-y-4"
    >
      <div
        :if={@disabled?}
        data-selecto-action-form-unavailable
        role="alert"
        class="rounded border border-amber-300 bg-amber-50 p-3 text-sm text-amber-900"
      >
        <div class="font-semibold">This action is unavailable for your current access.</div>
        <p class="mt-1">{@disabled_reason || "This action is not available for the selected target."}</p>
        <p class="mt-1 text-xs text-amber-800">The form is read-only until the action becomes available.</p>
      </div>

      <div class="rounded border border-slate-200 bg-slate-50 p-3 text-sm">
        <div class="flex flex-wrap items-center gap-2">
          <span class="font-semibold text-slate-900">{Map.get(@action, :id) || Map.get(@action, "id")}</span>
          <span :if={Map.get(@action, :operation) || Map.get(@action, "operation")} class="rounded bg-white px-2 py-0.5 text-xs text-slate-600 ring-1 ring-slate-200">
            {Map.get(@action, :operation) || Map.get(@action, "operation")}
          </span>
          <span :if={Map.get(@action, :scope) || Map.get(@action, "scope")} class="rounded bg-white px-2 py-0.5 text-xs text-slate-600 ring-1 ring-slate-200">
            {Map.get(@action, :scope) || Map.get(@action, "scope")}
          </span>
        </div>
        <p :if={Map.get(@action, :capability) || Map.get(@action, "capability")} class="mt-1 font-mono text-xs text-slate-500">
          {Map.get(@action, :capability) || Map.get(@action, "capability")}
        </p>
      </div>

      <div data-selecto-action-form-target class="rounded border border-slate-200 p-3">
        <h4 class="text-sm font-semibold text-slate-900">Target</h4>
        <dl class="mt-2 grid gap-2 text-sm sm:grid-cols-2">
          <div :for={{key, value} <- @target}>
            <dt class="text-xs uppercase text-slate-500">{key}</dt>
            <dd class="font-medium text-slate-800">{inspect(value)}</dd>
          </div>
        </dl>
      </div>

      <form
        id={"#{@id}-form"}
        phx-change="change_action_form"
        phx-submit="submit_action_form"
        phx-target={@myself}
        class="space-y-4"
      >
        <div data-selecto-action-form-inputs class="space-y-3">
          <h4 class="text-sm font-semibold text-slate-900">
            Inputs{if @controls_disabled?, do: " (read-only)", else: ""}
          </h4>
          <p :if={@active_variant} data-selecto-action-form-variant={@active_variant} class="text-xs text-slate-500">
            Variant: <span class="font-medium text-slate-700">{@active_variant}</span>
          </p>
          <p :if={@inputs == []} class="text-sm text-slate-500">This action has no additional inputs.</p>
          <div :for={input <- @inputs} class="block">
            <.collection_input
              :if={collection_input?(input)}
              input={input}
              items={collection_input_items(input, @form_inputs)}
              controls_disabled?={@controls_disabled?}
              myself={@myself}
            />
            <label :if={!collection_input?(input)} class="block">
            <span class="text-sm font-medium text-slate-700">
              {Map.get(input, "label") || humanize(Map.get(input, "id"))}
              <span :if={truthy?(Map.get(input, "required"))} class="text-rose-600">*</span>
            </span>
            <select
              :if={select_input?(input)}
              data-selecto-action-form-input={Map.get(input, "id")}
              name={"inputs[#{Map.get(input, "id")}]"}
              required={required_html_input?(input)}
              aria-required={input_required?(input)}
              disabled={@controls_disabled?}
              class="mt-1 w-full rounded border border-slate-300 px-3 py-2 text-sm"
            >
              <option :for={option <- input_options(input)} value={option_value(option)} selected={option_selected?(option, input, @form_inputs)}>
                {option_label(option)}
              </option>
            </select>
            <textarea
              :if={textarea_input?(input)}
              data-selecto-action-form-input={Map.get(input, "id")}
              name={"inputs[#{Map.get(input, "id")}]"}
              rows={input_rows(input)}
              required={required_html_input?(input)}
              aria-required={input_required?(input)}
              disabled={@controls_disabled?}
              class="mt-1 w-full rounded border border-slate-300 px-3 py-2 text-sm"
            ><%= Map.get(@form_inputs, Map.get(input, "id"), "") %></textarea>
            <input
              :if={!select_input?(input) && !textarea_input?(input)}
              data-selecto-action-form-input={Map.get(input, "id")}
              name={"inputs[#{Map.get(input, "id")}]"}
              value={input_value(input, @form_inputs)}
              type={input_type(input)}
              checked={input_checked?(input, @form_inputs)}
              min={input_attr(input, "min")}
              max={input_attr(input, "max")}
              step={input_attr(input, "step")}
              required={required_html_input?(input)}
              aria-required={input_required?(input)}
              disabled={@controls_disabled?}
              class={input_class(input)}
            />
            </label>
          </div>
        </div>

        <label :if={truthy?(Map.get(@confirmation, "required"))} class="flex items-start gap-2 rounded border border-amber-200 bg-amber-50 p-3 text-sm text-amber-800">
          <input
            type="checkbox"
            name="confirmed"
            value="true"
            checked={@confirmed}
            disabled={@controls_disabled?}
            class="mt-0.5"
          />
          <span>{Map.get(@confirmation, "message") || "Confirm this action before applying."}</span>
        </label>

        <details :if={@show_debug_json?} class="text-xs text-slate-600">
          <summary class="cursor-pointer font-medium text-slate-700">Request template</summary>
          <pre class="mt-2 max-h-48 overflow-auto rounded bg-slate-950 p-3 text-slate-100"><%= Jason.encode!(@request_template, pretty: true) %></pre>
        </details>

        <div :if={@last_error} data-selecto-action-form-error class="rounded border border-rose-200 bg-rose-50 p-3 text-sm text-rose-800">
          <div class="font-medium">{@last_error}</div>
          <dl :if={@error_details} data-selecto-action-form-error-details class="mt-2 grid gap-2 text-xs sm:grid-cols-2">
            <div :for={item <- error_summary(@error_details)} data-selecto-action-form-error-detail={item.key} class="rounded bg-white/70 p-2 ring-1 ring-rose-100">
              <dt class="font-semibold uppercase text-rose-700">{item.label}</dt>
              <dd class="mt-1 font-mono text-rose-950">{item.value}</dd>
            </div>
          </dl>
        </div>

        <div :if={@last_result} data-selecto-action-form-result class="rounded border border-emerald-200 bg-emerald-50 p-3 text-xs text-emerald-900">
          <div class="mb-1 font-semibold">{result_title(@last_result)}</div>
          <dl :if={@result_summary != []} data-selecto-action-form-result-summary class="mb-3 grid gap-2 text-sm sm:grid-cols-2">
            <div :for={item <- @result_summary} data-selecto-action-form-result-summary-item={item.key} class="rounded bg-white/70 p-2 ring-1 ring-emerald-100">
              <dt class="text-[11px] font-semibold uppercase text-emerald-700">{item.label}</dt>
              <dd class="mt-1 font-mono text-xs text-emerald-950">{item.value}</dd>
            </div>
          </dl>
          <div
            :if={@reload_summary}
            data-selecto-action-form-reload={@reload_summary.status}
            class="mb-3 rounded border border-emerald-200 bg-white/70 p-2 text-sm text-emerald-900"
          >
            <span class="font-medium">{@reload_summary.label}</span>
            <span :if={@reload_summary.detail} class="ml-1 text-emerald-700">{@reload_summary.detail}</span>
          </div>
          <details :if={@show_debug_json?} data-selecto-action-form-result-details class="mt-2">
            <summary class="cursor-pointer font-medium text-emerald-800">Response details</summary>
            <pre class="mt-2 max-h-56 overflow-auto rounded bg-white/70 p-2 text-emerald-950 ring-1 ring-emerald-100"><%= Jason.encode!(@last_result, pretty: true) %></pre>
          </details>
        </div>

        <div :if={@applied?} data-selecto-action-form-applied class="rounded border border-slate-200 bg-slate-50 p-3 text-sm text-slate-700">
          This action has been applied. Reopen the row to run another action request.
        </div>

        <div class="flex justify-end gap-2">
          <button
            :if={(@last_result || @last_error) && !@applied?}
            type="button"
            phx-click="reset_action_form"
            phx-target={@myself}
            data-selecto-action-form-reset
            class="rounded border border-slate-300 bg-white px-3 py-2 text-sm font-medium text-slate-700 hover:bg-slate-50"
          >
            Clear result
          </button>
          <button
            type="submit"
            name="intent"
            value="preview"
            data-selecto-action-form-submit="preview"
            class={action_submit_class(:preview, @disabled? || @applied? || @submitting == "preview")}
            disabled={@disabled? || @applied? || @submitting == "preview"}
          >
            Preview
          </button>
          <button
            type="submit"
            name="intent"
            value="apply"
            data-selecto-action-form-submit="apply"
            class={action_submit_class(:apply, apply_disabled?(@confirmation, @confirmed, @submitting, @applied?, @disabled?, @form_valid?))}
            disabled={apply_disabled?(@confirmation, @confirmed, @submitting, @applied?, @disabled?, @form_valid?)}
          >
            Apply
          </button>
        </div>
      </form>
    </div>
    """
  end

  defp collection_input(assigns) do
    assigns =
      assigns
      |> assign(:input_id, Map.get(assigns.input, "id"))
      |> assign(:item_inputs, collection_item_inputs(assigns.input))
      |> assign(:min_items, collection_min_items(assigns.input))

    ~H"""
    <fieldset
      data-selecto-action-form-collection={@input_id}
      class="space-y-3 rounded-lg border border-slate-200 bg-slate-50 p-3"
      disabled={@controls_disabled?}
    >
      <div class="flex flex-wrap items-start justify-between gap-2">
        <div>
          <legend class="text-sm font-medium text-slate-700">
            {Map.get(@input, "label") || humanize(@input_id)}
            <span :if={input_required?(@input)} class="text-rose-600">*</span>
          </legend>
          <p class="text-xs text-slate-500">
            {collection_help_text(@input, @min_items)}
          </p>
        </div>
        <button
          type="button"
          phx-click="add_action_collection_item"
          phx-target={@myself}
          phx-value-input-id={@input_id}
          data-selecto-action-form-collection-add={@input_id}
          class="rounded border border-slate-300 bg-white px-2 py-1 text-xs font-medium text-slate-700 hover:bg-slate-100"
        >
          Add item
        </button>
      </div>

      <p :if={@items == []} class="rounded border border-dashed border-slate-300 bg-white p-3 text-sm text-slate-500">
        No items added.
      </p>

      <div
        :for={{item, index} <- Enum.with_index(@items)}
        data-selecto-action-form-collection-item={index}
        class="space-y-3 rounded border border-slate-200 bg-white p-3"
      >
        <input type="hidden" name={collection_item_name(@input_id, index, "op")} value={Map.get(item, "op", "add")} />
        <input type="hidden" name={collection_item_name(@input_id, index, "client_id")} value={Map.get(item, "client_id")} />
        <input type="hidden" name={collection_item_name(@input_id, index, collection_order_field(@input))} value={index + 1} />

        <div class="flex items-center justify-between gap-2">
          <span class="text-xs font-semibold uppercase tracking-wide text-slate-500">Item {index + 1}</span>
          <div class="flex gap-1">
            <button
              type="button"
              phx-click="move_action_collection_item"
              phx-target={@myself}
              phx-value-input-id={@input_id}
              phx-value-index={index}
              phx-value-direction="up"
              disabled={index == 0}
              class="rounded border border-slate-300 px-2 py-1 text-xs disabled:opacity-40"
            >
              Up
            </button>
            <button
              type="button"
              phx-click="move_action_collection_item"
              phx-target={@myself}
              phx-value-input-id={@input_id}
              phx-value-index={index}
              phx-value-direction="down"
              disabled={index == length(@items) - 1}
              class="rounded border border-slate-300 px-2 py-1 text-xs disabled:opacity-40"
            >
              Down
            </button>
            <button
              type="button"
              phx-click="remove_action_collection_item"
              phx-target={@myself}
              phx-value-input-id={@input_id}
              phx-value-index={index}
              class="rounded border border-rose-200 px-2 py-1 text-xs text-rose-700 hover:bg-rose-50"
            >
              Remove
            </button>
          </div>
        </div>

        <label :for={item_input <- @item_inputs} class="block">
          <span class="text-sm font-medium text-slate-700">
            {Map.get(item_input, "label") || humanize(Map.get(item_input, "id"))}
            <span :if={input_required?(item_input)} class="text-rose-600">*</span>
          </span>
          <select
            :if={select_input?(item_input)}
            name={collection_item_name(@input_id, index, Map.get(item_input, "id"))}
            required={required_html_input?(item_input)}
            class="mt-1 w-full rounded border border-slate-300 px-3 py-2 text-sm"
          >
            <option
              :for={option <- input_options(item_input)}
              value={option_value(option)}
              selected={option_value(option) == to_string(collection_item_value(item, item_input))}
            >
              {option_label(option)}
            </option>
          </select>
          <textarea
            :if={textarea_input?(item_input)}
            name={collection_item_name(@input_id, index, Map.get(item_input, "id"))}
            rows={input_rows(item_input)}
            required={required_html_input?(item_input)}
            class="mt-1 w-full rounded border border-slate-300 px-3 py-2 text-sm"
          ><%= collection_item_value(item, item_input) %></textarea>
          <span :if={!select_input?(item_input) && !textarea_input?(item_input) && input_type(item_input) == "checkbox"}>
            <input type="hidden" name={collection_item_name(@input_id, index, Map.get(item_input, "id"))} value="false" />
            <input
              type="checkbox"
              name={collection_item_name(@input_id, index, Map.get(item_input, "id"))}
              value="true"
              checked={truthy?(collection_item_value(item, item_input))}
              class={input_class(item_input)}
            />
          </span>
          <input
            :if={!select_input?(item_input) && !textarea_input?(item_input) && input_type(item_input) != "checkbox"}
            type={input_type(item_input)}
            name={collection_item_name(@input_id, index, Map.get(item_input, "id"))}
            value={collection_item_value(item, item_input)}
            required={required_html_input?(item_input)}
            class={input_class(item_input)}
          />
        </label>
      </div>
    </fieldset>
    """
  end

  @impl true
  def handle_event("change_action_form", params, socket) do
    input_defs = all_action_input_defs(socket)

    form_inputs =
      socket.assigns
      |> Map.get(:form_inputs, %{})
      |> merge_changed_inputs(
        Map.get(params, "inputs", %{}),
        input_defs,
        Map.get(params, "_target", [])
      )

    {:noreply,
     assign(socket,
       form_inputs: form_inputs,
       confirmed: truthy?(Map.get(params, "confirmed")),
       last_error: nil
     )}
  end

  def handle_event("add_action_collection_item", %{"input-id" => input_id}, socket) do
    {:noreply,
     update_collection_items(socket, input_id, &(&1 ++ [new_collection_item(socket, input_id)]))}
  end

  def handle_event(
        "remove_action_collection_item",
        %{"input-id" => input_id, "index" => index},
        socket
      ) do
    {:noreply, update_collection_items(socket, input_id, &List.delete_at(&1, parse_index(index)))}
  end

  def handle_event(
        "move_action_collection_item",
        %{"input-id" => input_id, "index" => index, "direction" => direction},
        socket
      ) do
    index = parse_index(index)
    destination = if direction == "up", do: index - 1, else: index + 1

    {:noreply,
     update_collection_items(socket, input_id, &move_collection_item(&1, index, destination))}
  end

  def handle_event("reset_action_form", _params, socket) do
    if applied_result?(Map.get(socket.assigns, :last_result)) do
      {:noreply, socket}
    else
      {:noreply,
       assign(socket,
         submitting: nil,
         last_request: nil,
         last_result: nil,
         last_error: nil
       )}
    end
  end

  def handle_event("submit_action_form", params, socket) do
    intent = normalize_intent(Map.get(params, "intent"))
    action = normalize_action(socket.assigns.action)
    target = normalize_target(socket.assigns)
    all_input_defs = all_action_input_defs(socket, action)

    normalized_inputs =
      socket.assigns
      |> Map.get(:form_inputs, %{})
      |> merge_submit_inputs(Map.get(params, "inputs", %{}))
      |> normalize_inputs(all_input_defs)

    {input_defs, _active_variant} = Actions.effective_inputs(action, normalized_inputs)
    inputs = only_active_inputs(normalized_inputs, input_defs, all_input_defs)

    confirmed = truthy?(Map.get(params, "confirmed"))

    case validate_submission(action, intent, confirmed, inputs, input_defs) do
      :ok ->
        submit_action_request(socket, action, target, intent, inputs, confirmed)

      {:error, message} ->
        {:noreply,
         assign(socket,
           form_inputs: inputs,
           confirmed: confirmed,
           submitting: nil,
           last_error: message
         )}
    end
  end

  defp validate_submission(action, "apply", false, inputs, input_defs) do
    if truthy?(get_in(action, ["confirmation", "required"])) do
      {:error, "Confirm this action before applying."}
    else
      validate_required_inputs(inputs, input_defs)
    end
  end

  defp validate_submission(_action, _intent, _confirmed, inputs, input_defs) do
    validate_required_inputs(inputs, input_defs)
  end

  defp submit_action_request(socket, action, target, intent, inputs, confirmed) do
    request =
      Actions.request_template(action,
        target: target,
        inputs: inputs,
        dry_run: intent == "preview",
        confirmed: confirmed
      )

    payload = action_submit_payload(action, target, intent, inputs, request)

    send(self(), {:selecto_action_form_submit, payload})

    {:noreply,
     assign(socket,
       form_inputs: inputs,
       confirmed: confirmed,
       submitting: intent,
       last_request: request,
       last_error: nil
     )}
  end

  defp action_submit_payload(action, target, intent, inputs, request) do
    %{
      intent: intent,
      action_id: Map.get(action, "id"),
      action: action,
      action_label: Map.get(action, "label"),
      action_scope: Map.get(action, "scope"),
      action_operation: Map.get(action, "operation"),
      capability: Map.get(action, "capability"),
      endpoints: map_or_empty(Map.get(action, "endpoints")),
      links: map_or_empty(Map.get(action, "links")),
      target: target,
      inputs: inputs,
      confirmation_required?: truthy?(get_in(action, ["confirmation", "required"])),
      request: request
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == %{} end)
    |> Map.new()
  end

  defp normalize_action(action) when is_map(action),
    do: SelectoComponents.QueryContract.json_safe(action)

  defp normalize_action(_action), do: %{}

  defp action_input_defs(socket, action) do
    case Map.get(socket.assigns, :inputs) do
      inputs when is_list(inputs) and inputs != [] ->
        SelectoComponents.QueryContract.json_safe(inputs)

      _inputs ->
        Map.get(action, "inputs", [])
    end
  end

  defp all_action_input_defs(socket, action \\ nil) do
    action = action || normalize_action(Map.get(socket.assigns, :action, %{}))

    base_inputs = action_input_defs(socket, action)

    variant_inputs =
      action
      |> Map.get("variants", [])
      |> List.wrap()
      |> Enum.flat_map(&(Map.get(&1, "inputs", []) |> List.wrap()))

    merge_input_definitions(base_inputs, variant_inputs)
  end

  defp merge_input_definitions(base_inputs, extra_inputs) do
    (List.wrap(base_inputs) ++ List.wrap(extra_inputs))
    |> Enum.reduce([], fn input, accumulated ->
      id = Map.get(input, "id")

      accumulated
      |> Enum.reject(&(Map.get(&1, "id") == id))
      |> Kernel.++([input])
    end)
  end

  defp merge_input_defaults(inputs, input_defs) do
    Enum.reduce(List.wrap(input_defs), map_or_empty(inputs), fn input, accumulated ->
      id = Map.get(input, "id")

      cond do
        is_nil(id) or Map.has_key?(accumulated, id) ->
          accumulated

        Map.has_key?(input, "default") ->
          Map.put(accumulated, id, Map.get(input, "default"))

        collection_input?(input) ->
          Map.put(accumulated, id, [])

        Map.get(input, "type") == "boolean" ->
          Map.put(accumulated, id, false)

        true ->
          accumulated
      end
    end)
  end

  defp only_active_inputs(inputs, active_input_defs, _all_input_defs) do
    active_ids = active_input_defs |> List.wrap() |> Enum.map(&Map.get(&1, "id")) |> MapSet.new()

    inputs
    |> map_or_empty()
    |> Enum.filter(fn {id, _value} -> MapSet.member?(active_ids, id) end)
    |> Map.new()
  end

  defp normalize_intent("apply"), do: "apply"
  defp normalize_intent(_intent), do: "preview"

  defp normalize_target(assigns) do
    explicit = Map.get(assigns, :target, %{})
    record = Map.get(assigns, :record, %{})

    (explicit || %{})
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
    |> Map.put_new("id", Map.get(record, "id", Map.get(record, :id)))
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp merge_default_inputs(inputs, action) when is_map(inputs) do
    action
    |> Actions.request_template()
    |> Map.get("inputs", %{})
    |> Map.merge(inputs)
  end

  defp merge_default_inputs(_inputs, action) do
    action
    |> Actions.request_template()
    |> Map.get("inputs", %{})
  end

  defp normalize_inputs(inputs, input_defs) when is_map(inputs) do
    input_defs = List.wrap(input_defs)

    normalized_defined =
      input_defs
      |> Enum.map(fn input ->
        id = Map.get(input, "id")
        {id, normalize_input_value(Map.get(inputs, id), input)}
      end)
      |> Enum.reject(fn {_id, value} -> value == :__selecto_omit_input__ end)
      |> Map.new()

    normalized_defined
    |> Enum.reject(fn {key, _value} -> is_nil(key) end)
    |> Map.new()
  end

  defp normalize_inputs(_inputs, _input_defs), do: %{}

  defp merge_changed_inputs(existing_inputs, changed_inputs, input_defs, target_path) do
    changed_inputs =
      changed_inputs
      |> Map.new()
      |> reject_unused_inputs()
      |> reject_empty_non_target_inputs(existing_inputs, target_path)
      |> maybe_put_unchecked_boolean(input_defs, target_path)

    existing_inputs
    |> map_or_empty()
    |> Map.merge(changed_inputs)
  end

  defp reject_unused_inputs(inputs) do
    inputs
    |> Enum.reject(fn {key, _value} -> String.starts_with?(to_string(key), "_unused_") end)
    |> Map.new()
  end

  defp reject_empty_non_target_inputs(inputs, existing_inputs, ["inputs", target_id]) do
    existing_inputs = map_or_empty(existing_inputs)

    inputs
    |> Enum.reject(fn {key, value} ->
      key != target_id and value in [nil, ""] and
        present_input_value?(Map.get(existing_inputs, key))
    end)
    |> Map.new()
  end

  defp reject_empty_non_target_inputs(inputs, _existing_inputs, _target_path), do: inputs

  defp maybe_put_unchecked_boolean(inputs, input_defs, ["inputs", input_id]) do
    if boolean_input?(input_defs, input_id) and not Map.has_key?(inputs, input_id) do
      Map.put(inputs, input_id, false)
    else
      inputs
    end
  end

  defp maybe_put_unchecked_boolean(inputs, _input_defs, _target_path), do: inputs

  defp merge_submit_inputs(existing_inputs, submitted_inputs) do
    existing_inputs = map_or_empty(existing_inputs)

    submitted_inputs =
      submitted_inputs
      |> map_or_empty()
      |> reject_unused_inputs()
      |> Enum.reject(fn {key, value} ->
        value in [nil, ""] and present_input_value?(Map.get(existing_inputs, key))
      end)
      |> Map.new()

    Map.merge(existing_inputs, submitted_inputs)
  end

  defp boolean_input?(input_defs, input_id) do
    input_defs
    |> List.wrap()
    |> Enum.any?(fn input ->
      Map.get(input, "id") == input_id and Map.get(input, "type") == "boolean"
    end)
  end

  defp map_or_empty(value) when is_map(value), do: value
  defp map_or_empty(_value), do: %{}

  defp collection_input?(input), do: Map.get(input, "type") == "collection"

  defp collection_item_inputs(input) do
    input
    |> Map.get("item", get_in(input, ["raw", "item"]) || [])
    |> case do
      inputs when is_list(inputs) ->
        inputs

      inputs when is_map(inputs) ->
        Enum.map(inputs, fn {id, definition} ->
          definition
          |> map_or_empty()
          |> SelectoComponents.QueryContract.json_safe()
          |> Map.put_new("id", to_string(id))
        end)

      _other ->
        []
    end
  end

  defp collection_min_items(input) do
    Map.get(input, "min_items") || get_in(input, ["raw", "min_items"]) ||
      if(input_required?(input), do: 1, else: 0)
  end

  defp collection_help_text(input, min_items) do
    Map.get(input, "help") || Map.get(input, "description") ||
      case min_items do
        count when is_integer(count) and count > 0 ->
          "Add at least #{count} #{if count == 1, do: "item", else: "items"}."

        _count ->
          "Add, remove, or reorder items for this action."
      end
  end

  defp collection_order_field(input) do
    get_in(input, ["order", "field"]) || get_in(input, ["raw", "order", "field"]) ||
      "position"
  end

  defp collection_item_name(collection_id, index, field),
    do: "inputs[#{collection_id}][#{index}][#{field}]"

  defp collection_item_value(item, input) do
    id = Map.get(input, "id")

    cond do
      Map.has_key?(item, id) -> Map.get(item, id)
      Map.has_key?(input, "default") -> Map.get(input, "default")
      Map.get(input, "type") == "boolean" -> false
      true -> ""
    end
  end

  defp collection_input_items(input, form_inputs) do
    form_inputs
    |> map_or_empty()
    |> Map.get(Map.get(input, "id"), [])
    |> normalize_collection_items(input)
  end

  defp update_collection_items(socket, input_id, update_fun) do
    input =
      socket
      |> all_action_input_defs()
      |> Enum.find(&(Map.get(&1, "id") == input_id and collection_input?(&1)))

    if input do
      form_inputs = Map.get(socket.assigns, :form_inputs, %{}) |> map_or_empty()
      items = form_inputs |> Map.get(input_id, []) |> normalize_collection_items(input)

      assign(socket,
        form_inputs: Map.put(form_inputs, input_id, update_fun.(items)),
        last_error: nil
      )
    else
      socket
    end
  end

  defp new_collection_item(socket, input_id) do
    input =
      socket
      |> all_action_input_defs()
      |> Enum.find(&(Map.get(&1, "id") == input_id and collection_input?(&1)))

    defaults =
      input
      |> collection_item_inputs()
      |> Enum.reduce(%{}, fn item_input, item ->
        id = Map.get(item_input, "id")

        value =
          cond do
            Map.has_key?(item_input, "default") ->
              Map.get(item_input, "default")

            select_input?(item_input) ->
              item_input |> input_options() |> List.first() |> option_value()

            Map.get(item_input, "type") == "boolean" ->
              false

            true ->
              ""
          end

        Map.put(item, id, value)
      end)

    defaults
    |> Map.put("op", "add")
    |> Map.put("client_id", "selecto-item-#{System.unique_integer([:positive, :monotonic])}")
  end

  defp move_collection_item(items, from, destination)
       when is_integer(from) and is_integer(destination) do
    if items != [] and from >= 0 and from < length(items) and destination >= 0 and
         destination < length(items) do
      item = Enum.at(items, from)

      items
      |> List.delete_at(from)
      |> List.insert_at(destination, item)
    else
      items
    end
  end

  defp move_collection_item(items, _from, _destination), do: items

  defp parse_index(index) when is_integer(index), do: index

  defp parse_index(index) do
    case Integer.parse(to_string(index)) do
      {value, ""} -> value
      _other -> 1_000_000
    end
  end

  defp normalize_input_value(value, %{"type" => "collection"} = input),
    do: normalize_collection_items(value, input)

  defp normalize_input_value(value, %{"type" => "boolean"}) when is_list(value),
    do: value |> List.last() |> truthy?()

  defp normalize_input_value(nil, %{"type" => "boolean"}), do: false
  defp normalize_input_value("true", %{"type" => "boolean"}), do: true
  defp normalize_input_value("false", %{"type" => "boolean"}), do: false
  defp normalize_input_value(value, %{"type" => "boolean"}), do: truthy?(value)
  defp normalize_input_value("", input), do: default_or_omit_input(input)
  defp normalize_input_value(nil, input), do: default_or_omit_input(input)

  defp normalize_input_value(value, %{"type" => type}) when type in ["utc_datetime", "datetime"],
    do: normalize_utc_datetime(value)

  defp normalize_input_value(value, _input), do: value

  defp normalize_collection_items(nil, _input), do: []

  defp normalize_collection_items(items, input) when is_map(items) do
    items
    |> Enum.reject(fn {key, _value} -> String.starts_with?(to_string(key), "_unused_") end)
    |> Enum.sort_by(fn {key, _value} -> parse_index(key) end)
    |> Enum.map(&elem(&1, 1))
    |> normalize_collection_items(input)
  end

  defp normalize_collection_items(items, input) when is_list(items) do
    item_inputs = collection_item_inputs(input)
    item_ids = item_inputs |> Enum.map(&Map.get(&1, "id")) |> MapSet.new()

    Enum.map(items, fn item ->
      item = item |> map_or_empty() |> SelectoComponents.QueryContract.json_safe()

      normalized_fields =
        Enum.reduce(item_inputs, %{}, fn item_input, normalized ->
          id = Map.get(item_input, "id")
          value = normalize_input_value(Map.get(item, id), item_input)

          if value == :__selecto_omit_input__ do
            normalized
          else
            Map.put(normalized, id, value)
          end
        end)

      item
      |> Enum.reject(fn {key, _value} ->
        String.starts_with?(to_string(key), "_unused_") or MapSet.member?(item_ids, key)
      end)
      |> Map.new()
      |> Map.merge(normalized_fields)
    end)
  end

  defp normalize_collection_items(_items, _input), do: []

  defp default_or_omit_input(input) do
    cond do
      Map.has_key?(input, "default") ->
        Map.get(input, "default")

      input_required?(input) ->
        ""

      true ->
        :__selecto_omit_input__
    end
  end

  defp input_type(%{"type" => "boolean"}), do: "checkbox"

  defp input_type(%{"type" => type}) when type in ["integer", "number", "float", "decimal"],
    do: "number"

  defp input_type(%{"type" => type}) when type in ["email", "url", "date", "time"],
    do: type

  defp input_type(%{"type" => type})
       when type in ["datetime", "datetime-local", "utc_datetime", "naive_datetime"],
       do: "datetime-local"

  defp input_type(_input), do: "text"

  defp normalize_utc_datetime(value) when value in [nil, ""], do: value

  defp normalize_utc_datetime(value) when is_binary(value) do
    cond do
      String.match?(value, ~r/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/) ->
        value <> ":00Z"

      String.match?(value, ~r/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$/) ->
        value <> "Z"

      true ->
        value
    end
  end

  defp normalize_utc_datetime(value), do: value

  defp input_class(%{"type" => "boolean"}),
    do: "mt-1 rounded border border-slate-300 text-sm"

  defp input_class(_input),
    do: "mt-1 w-full rounded border border-slate-300 px-3 py-2 text-sm"

  defp input_attr(input, key), do: Map.get(input, key) || get_in(input, ["raw", key])

  defp required_html_input?(input), do: input_required?(input) and input_type(input) != "checkbox"

  defp input_required?(input), do: truthy?(Map.get(input, "required"))

  defp present_input_value?(value) when value in [nil, ""], do: false
  defp present_input_value?(_value), do: true

  defp select_input?(input), do: input_options(input) != []

  defp textarea_input?(input) do
    input
    |> Map.get("type")
    |> to_string()
    |> Kernel.in(["text", "textarea", "long_text"])
  end

  defp input_options(input) do
    input
    |> input_option_source()
    |> List.wrap()
    |> Enum.reject(&is_nil/1)
  end

  defp input_option_source(input) do
    Map.get(input, "options") ||
      Map.get(input, "choices") ||
      Map.get(input, "values") ||
      input
      |> Map.get("raw", %{})
      |> then(fn raw ->
        Map.get(raw, "options") || Map.get(raw, "choices") || Map.get(raw, "values") || []
      end)
  end

  defp input_rows(input) do
    Map.get(input, "rows") || get_in(input, ["raw", "rows"]) || 4
  end

  defp option_selected?(option, input, form_inputs) do
    current_value =
      form_inputs
      |> Map.get(Map.get(input, "id"), Map.get(input, "default", ""))
      |> to_string()

    option_value(option) == current_value
  end

  defp option_value(%{"value" => value}), do: to_string(value)
  defp option_value(%{value: value}), do: to_string(value)
  defp option_value(%{"id" => value}), do: to_string(value)
  defp option_value(%{id: value}), do: to_string(value)
  defp option_value({value, _label}), do: to_string(value)
  defp option_value(value), do: to_string(value)

  defp option_label(%{"label" => label}), do: label
  defp option_label(%{label: label}), do: label
  defp option_label(%{"name" => label}), do: label
  defp option_label(%{name: label}), do: label
  defp option_label({_value, label}), do: label
  defp option_label(value), do: humanize(value)

  defp input_checked?(%{"type" => "boolean"} = input, form_inputs) do
    form_inputs
    |> Map.get(Map.get(input, "id"))
    |> truthy?()
  end

  defp input_checked?(_input, _form_inputs), do: false

  defp input_value(%{"type" => "boolean"}, _form_inputs), do: "true"

  defp input_value(input, form_inputs) do
    form_inputs
    |> Map.get(Map.get(input, "id"), "")
    |> scalar_input_value(input)
  end

  defp scalar_input_value(value, %{"type" => type})
       when is_binary(value) and type in ["utc_datetime", "datetime", "datetime-local"] do
    browser_datetime_value(value)
  end

  defp scalar_input_value(value, _input) when is_binary(value) or is_number(value), do: value
  defp scalar_input_value(true, _input), do: "true"
  defp scalar_input_value(false, _input), do: "false"
  defp scalar_input_value(_value, _input), do: ""

  defp browser_datetime_value(value) do
    cond do
      String.match?(value, ~r/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/) ->
        String.trim_trailing(value, "Z")

      String.match?(value, ~r/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}Z$/) ->
        String.trim_trailing(value, "Z")

      true ->
        value
    end
  end

  defp validate_required_inputs(inputs, input_defs) do
    missing_inputs =
      input_defs
      |> List.wrap()
      |> Enum.filter(&input_required?/1)
      |> Enum.reject(&collection_input?/1)
      |> Enum.filter(fn input ->
        inputs
        |> Map.get(Map.get(input, "id"))
        |> blank_input_value?()
      end)
      |> Enum.map(&input_label/1)

    collection_errors =
      input_defs
      |> List.wrap()
      |> Enum.filter(&collection_input?/1)
      |> Enum.flat_map(&validate_collection_input(inputs, &1))

    case missing_inputs ++ collection_errors do
      [] -> :ok
      labels -> {:error, "Required inputs missing: #{Enum.join(labels, ", ")}."}
    end
  end

  defp validate_collection_input(inputs, input) do
    items = collection_input_items(input, inputs)
    min_items = collection_min_items(input)

    minimum_error =
      if is_integer(min_items) and length(items) < min_items do
        ["#{input_label(input)} (at least #{min_items})"]
      else
        []
      end

    item_errors =
      items
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {item, index} ->
        input
        |> collection_item_inputs()
        |> Enum.filter(&input_required?/1)
        |> Enum.filter(fn item_input ->
          item |> Map.get(Map.get(item_input, "id")) |> blank_input_value?()
        end)
        |> Enum.map(fn item_input ->
          "#{input_label(input)} item #{index} #{input_label(item_input)}"
        end)
      end)

    minimum_error ++ item_errors
  end

  defp required_inputs_valid?(inputs, input_defs),
    do: validate_required_inputs(inputs, input_defs) == :ok

  defp blank_input_value?(value) when value in [nil, ""], do: true
  defp blank_input_value?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank_input_value?(value) when is_list(value), do: value == []
  defp blank_input_value?(_value), do: false

  defp input_label(input), do: Map.get(input, "label") || humanize(Map.get(input, "id"))

  defp humanize(nil), do: "Input"

  defp humanize(value) do
    value
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp truthy?(value) when value in [true, "true", "1", "on", 1, :yes], do: true
  defp truthy?(_value), do: false

  defp apply_disabled?(confirmation, confirmed, submitting, applied?, disabled?, form_valid?) do
    disabled? or applied? or not form_valid? or submitting == "apply" or
      (truthy?(Map.get(confirmation, "required")) and not confirmed)
  end

  defp action_submit_class(_intent, true) do
    "rounded border border-slate-300 bg-slate-100 px-3 py-2 text-sm font-medium text-slate-400 opacity-80 cursor-not-allowed"
  end

  defp action_submit_class(:preview, false) do
    "rounded bg-indigo-600 px-3 py-2 text-sm font-medium text-white hover:bg-indigo-700"
  end

  defp action_submit_class(:apply, false) do
    "rounded bg-emerald-600 px-3 py-2 text-sm font-medium text-white hover:bg-emerald-700"
  end

  defp disabled_action?(action) do
    Map.get(action, "disabled?") == true or Map.get(action, "status") == "disabled"
  end

  defp action_status(_disabled?, true), do: "applied"
  defp action_status(true, _applied?), do: "disabled"
  defp action_status(_disabled?, _applied?), do: "enabled"

  defp disabled_reason(action) do
    Map.get(action, "reason") || Map.get(action, "disabled_reason")
  end

  defp applied_result?(%{"intent" => "apply"}), do: true
  defp applied_result?(%{intent: "apply"}), do: true
  defp applied_result?(_result), do: false

  defp result_title(%{"intent" => "apply"}), do: "Apply result"
  defp result_title(%{intent: "apply"}), do: "Apply result"
  defp result_title(_result), do: "Preview result"

  defp result_summary(nil), do: []

  defp result_summary(result) do
    payload = result_payload(result)

    [
      summary_item(
        "action",
        "Action",
        first_present([map_value(payload, "action"), get_in(payload, ["preview", "action"])])
      ),
      target_summary_item(
        first_present([
          map_value(payload, "target"),
          get_in(payload, ["result", "target"]),
          get_in(payload, ["preview", "target"])
        ])
      ),
      affected_summary_item(payload),
      summary_item(
        "mode",
        "Mode",
        first_present([get_in(payload, ["result", "mode"]), map_value(payload, "mode")])
      ),
      summary_item(
        "variant",
        "Variant",
        first_present([get_in(payload, ["result", "variant"]), map_value(payload, "variant")])
      ),
      summary_item(
        "changes",
        "Changes",
        first_present([map_value(payload, "changes"), get_in(payload, ["preview", "changes"])])
      ),
      collection_summary_item(
        first_present([
          get_in(payload, ["result", "collection_results"]),
          map_value(payload, "collection_results")
        ])
      ),
      record_summary_item(
        first_present([get_in(payload, ["result", "record"]), map_value(payload, "record")])
      )
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp collection_summary_item(nil), do: nil

  defp collection_summary_item(collection_results) when is_map(collection_results) do
    operation_count =
      collection_results
      |> Enum.map(fn {_key, result} ->
        result
        |> map_value("operations", [])
        |> List.wrap()
        |> length()
      end)
      |> Enum.sum()

    summary_item("collections", "Collections", "#{operation_count} collection operations")
  end

  defp collection_summary_item(_collection_results), do: nil

  defp target_summary_item(nil), do: nil

  defp target_summary_item(target) when is_map(target) do
    cond do
      ids = map_value(target, "ids") ->
        summary_item("target_ids", "Target IDs", ids)

      id = map_value(target, "id") ->
        summary_item("target_id", "Target ID", id)

      true ->
        nil
    end
  end

  defp target_summary_item(_target), do: nil

  defp affected_summary_item(payload) do
    affected_count =
      first_present([
        get_in(payload, ["result", "affected_count"]),
        map_value(payload, "affected_count"),
        count_records(get_in(payload, ["result", "record"])),
        count_records(map_value(payload, "record")),
        count_records(get_in(payload, ["result", "would_update"])),
        count_records(map_value(payload, "would_update"))
      ])

    summary_item("affected", "Affected", affected_count)
  end

  defp count_records(records) when is_list(records), do: length(records)
  defp count_records(record) when is_map(record), do: 1
  defp count_records(_records), do: nil

  defp reload_summary(result) do
    case map_value(result, "reload") do
      nil ->
        nil

      reload when is_map(reload) ->
        status = reload |> map_value("status", "complete") |> to_string()
        surface = map_value(reload, "surface")
        detail = map_value(reload, "detail") || map_value(reload, "message")

        %{
          status: status,
          label: reload_label(status, surface),
          detail: detail
        }

      reload ->
        %{status: "complete", label: "Results refreshed", detail: to_string(reload)}
    end
  end

  defp reload_label("skipped", surface), do: reload_label_with_surface("Reload skipped", surface)
  defp reload_label("failed", surface), do: reload_label_with_surface("Reload failed", surface)
  defp reload_label(_status, surface), do: reload_label_with_surface("Results refreshed", surface)

  defp reload_label_with_surface(label, nil), do: label
  defp reload_label_with_surface(label, surface), do: "#{label}: #{humanize(surface)}"

  defp error_summary(details) do
    details
    |> error_summary_source()
    |> Enum.map(fn {key, value} ->
      %{key: to_string(key), label: humanize(key), value: summary_value(value)}
    end)
  end

  defp error_summary_source(%{"metadata" => metadata}) when is_map(metadata), do: metadata
  defp error_summary_source(%{metadata: metadata}) when is_map(metadata), do: metadata
  defp error_summary_source(details) when is_map(details), do: details
  defp error_summary_source(details), do: %{"reason" => inspect(details)}

  defp record_summary_item(nil), do: nil

  defp record_summary_item(records) when is_list(records) do
    summary_item("records", "Records", "#{length(records)} records")
  end

  defp record_summary_item(record), do: summary_item("record", "Record", record)

  defp result_payload(result) when is_map(result) do
    map_value(result, "payload", result)
  end

  defp result_payload(_result), do: %{}

  defp summary_item(_key, _label, nil), do: nil

  defp summary_item(key, label, value) do
    %{key: key, label: label, value: summary_value(value)}
  end

  defp summary_value(value) when is_map(value) or is_list(value), do: Jason.encode!(value)
  defp summary_value(value), do: to_string(value)

  defp first_present(values), do: Enum.find(values, &(not is_nil(&1)))

  defp map_value(map, key, default \\ nil)

  defp map_value(map, key, default) when is_map(map) and is_binary(key),
    do: Map.get(map, key, Map.get(map, safe_existing_atom(key), default))

  defp map_value(map, key, default) when is_map(map), do: Map.get(map, key, default)
  defp map_value(_map, _key, default), do: default

  defp safe_existing_atom(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end
end
