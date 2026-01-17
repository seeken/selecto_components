# SelectoComponents Code Review Document

Generated: 2026-01-16

## Summary Statistics
- Total files: 106
- Total modules: 109 (includes nested modules)
- Total public functions: ~751

## File Reference Map

The following modules are most frequently referenced across the codebase:

| Module | Reference Count | Purpose |
|--------|-----------------|---------|
| SelectoComponents.SafeAtom | 15+ files | Atom safety utilities |
| SelectoComponents.Helpers | 10+ files | General helper functions |
| SelectoComponents.Form.ParamsState | 8+ files | URL parameter handling |
| SelectoComponents.Components.Common | 8+ files | Shared UI components |
| SelectoComponents.Helpers.Filters | 6+ files | Filter utilities |
| SelectoComponents.ErrorHandling.* | 6+ files | Error handling subsystem |

---

## Core Files

### lib/selecto_components.ex
**References:** Entry point, imported/used by all consumer applications
**Purpose:** Main module that provides the `use SelectoComponents` macro for Phoenix LiveView integration.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| __using__ | 1 | Macro that imports all SelectoComponents functionality into a LiveView | Main entry point |

**Review Notes:**
- Defines the `__using__` macro pattern
- Imports Phoenix.Component, Phoenix.LiveView, and all core modules
- Sets up aliases for views, forms, and UI components

---

### lib/selecto_components/ui.ex
**References:** 8+ files reference this module
**Purpose:** Core UI components library providing fundamental form controls, buttons, badges, and layout elements.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| button | 1 | Renders various button styles (primary, secondary, danger, ghost, link) | |
| icon_button | 1 | Button with icon only | |
| badge | 1 | Status badge component | |
| pill | 1 | Pill-shaped badge variant | |
| card | 1 | Card container component | |
| card_header | 1 | Card header section | |
| card_body | 1 | Card body section | |
| card_footer | 1 | Card footer section | |
| tabs | 1 | Tab navigation component | |
| tab | 1 | Individual tab item | |
| tab_panel | 1 | Tab content panel | |
| dropdown | 1 | Dropdown menu component | |
| dropdown_item | 1 | Individual dropdown item | |
| modal | 1 | Modal dialog component | |
| toast | 1 | Toast notification component | |
| progress | 1 | Progress bar component | |
| skeleton | 1 | Loading skeleton placeholder | |
| tooltip | 1 | Tooltip component | |
| input | 1 | Form input wrapper | |

**Review Notes:**
- Comprehensive UI kit with consistent Tailwind styling
- All components support customization via assigns
- Good accessibility attributes (aria-*)

---

### lib/selecto_components/helpers.ex
**References:** 10+ files reference this module
**Purpose:** General utility functions used across the codebase.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| format_number | 1 | Formats numbers with thousands separators | |
| format_currency | 2 | Formats currency values | |

**Review Notes:**
- Small but widely used module
- Could be expanded with more utilities

---

### lib/selecto_components/state.ex
**References:** 5+ files reference this module
**Purpose:** State management utilities for LiveView socket assigns.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| init_state | 2 | Initializes SelectoComponents state in socket | |
| update_view_config | 3 | Updates view configuration | |
| apply_filters | 2 | Applies filter changes to state | |
| reset_state | 1 | Resets component state | |
| get_current_view | 1 | Returns current view mode | |
| set_view_mode | 2 | Sets the current view mode | |
| toggle_dev_mode | 1 | Toggles development mode | |

**Review Notes:**
- Central state management for all SelectoComponents
- Uses Phoenix.Component.assign internally

---

### lib/selecto_components/views.ex
**References:** 3+ files reference this module
**Purpose:** View mode registry and coordination.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| register_view | 3 | Registers a new view type | |

**Review Notes:**
- Simple registry module for view types
- Used to coordinate between detail, aggregate, and graph views

---

### lib/selecto_components/results.ex
**References:** 4+ files reference this module
**Purpose:** Results display component for query output.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| render | 1 | Main render function for results | Live component render |

**Review Notes:**
- Phoenix LiveComponent for displaying query results
- Handles different view modes (detail, aggregate, graph)

---

### lib/selecto_components/form.ex
**References:** 6+ files reference this module
**Purpose:** Main form component and macro provider for SelectoComponents forms.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| __using__ | 1 | Macro for form functionality | |
| sanitize_error_for_environment | 1 | Sanitizes errors based on environment | |
| dev_mode? | 0 | Checks if in development mode | |
| get_selected_columns_from_params | 1 | Extracts columns from URL params | |

**Review Notes:**
- Entry point for form-related functionality
- Imports event handlers, state management, and helpers

---

### lib/selecto_components/router.ex
**References:** Used by consumer applications
**Purpose:** Phoenix Router macros for SelectoComponents routes.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| __using__ | 1 | Macro for router integration | |
| selecto_routes | 2 | Defines SelectoComponents routes | |
| dashboard_routes | 1 | Defines dashboard routes | |
| admin_routes | 1 | Defines admin routes | |
| get_all_routes | 0 | Lists all registered routes | |
| live_dashboard_enabled? | 0 | Checks if live dashboard is enabled | |
| live_dashboard_path | 1 | Returns live dashboard path | |
| build_route_path | 2 | Constructs route paths | |
| resolve_live_view | 2 | Resolves LiveView modules | |
| default_live_view | 0 | Returns default LiveView module | |
| validate_options | 1 | Validates route options | |
| merge_options | 2 | Merges route options | |
| get_scope_prefix | 1 | Gets route scope prefix | |
| sanitize_path | 1 | Sanitizes URL paths | |
| full_path | 2 | Builds full URL path | |

**Review Notes:**
- Comprehensive router integration
- Supports multiple route groups (dashboard, admin)

---

### lib/selecto_components/safe_atom.ex
**References:** 15+ files reference this module
**Purpose:** Secure atom handling to prevent atom table exhaustion attacks.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| to_existing | 1 | Converts string to existing atom only | Returns nil if not exists |
| to_view_mode | 1 | Safely converts to view mode atom | :detail, :aggregate, :graph |
| to_sort_direction | 1 | Safely converts to sort direction | :asc, :desc |
| to_aggregate_function | 1 | Safely converts to aggregate function | :sum, :count, etc. |
| to_chart_type | 1 | Safely converts to chart type | :bar, :line, :pie |
| to_filter_comparison | 1 | Safely converts to comparison operator | =, !=, <, >, etc. |
| field_config_keys | 0 | Returns allowed field config keys | |
| view_config_keys | 0 | Returns allowed view config keys | |
| to_field_config_key | 1 | Safely converts field config keys | |
| to_view_config_key | 1 | Safely converts view config keys | |
| to_filter_key | 1 | Safely converts filter keys | |
| to_form_field | 1 | Safely converts form field names | |
| safe_to_atom | 2 | Converts with fallback | |
| whitelist_atom | 2 | Checks against whitelist | |
| sanitize_map_keys | 2 | Converts map keys safely | |
| known_field_keys | 0 | Returns all known field keys | |
| known_view_keys | 0 | Returns all known view keys | |
| known_filter_keys | 0 | Returns all known filter keys | |
| is_safe_identifier? | 1 | Validates identifier format | |
| sanitize_identifier | 1 | Sanitizes identifier string | |
| to_existing_or_new | 2 | Creates atom only if in whitelist | |
| merge_safe_atoms | 2 | Merges atom sets safely | |
| filter_safe_atoms | 2 | Filters to safe atoms only | |
| atomize_keys | 1 | Converts map keys to atoms safely | |
| string_keys | 1 | Converts atom keys to strings | |
| deep_atomize_keys | 1 | Recursively atomizes keys | |
| deep_string_keys | 1 | Recursively stringifies keys | |
| validate_atom | 2 | Validates atom against whitelist | |
| batch_validate | 2 | Validates multiple atoms | |
| get_validation_errors | 2 | Returns validation errors | |
| log_unknown_atom | 2 | Logs unknown atom attempts | |
| get_logged_unknowns | 0 | Returns logged unknown atoms | |
| clear_logged_unknowns | 0 | Clears logged unknowns | |
| stats | 0 | Returns usage statistics | |
| reset_stats | 0 | Resets statistics | |
| configure | 1 | Configures module behavior | |
| get_config | 0 | Gets current configuration | |

**Review Notes:**
- Critical security module
- Prevents atom table exhaustion from user input
- Used extensively throughout codebase
- Well-designed with comprehensive API

---

## Filter Subsystem

### lib/selecto_components/filter/filter_row.ex
**References:** 3+ files
**Purpose:** Individual filter row component with drag-and-drop support.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| filter_row | 1 | Renders a single filter row | |
| conjunction_row | 1 | Renders AND/OR conjunction selector | |
| draggable_filter | 1 | Wrapper for drag-and-drop | |

---

### lib/selecto_components/filter/filter_type_detector.ex
**References:** 2+ files
**Purpose:** Detects appropriate filter type based on column data type.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| detect_type | 1 | Determines filter type from column | |
| get_operators | 1 | Returns valid operators for type | |
| default_value | 1 | Returns default value for type | |
| validate_value | 2 | Validates value for type | |
| coerce_value | 2 | Coerces value to type | |
| format_for_display | 2 | Formats value for display | |

---

### lib/selecto_components/filter/date_range_filter.ex
**References:** 2+ files
**Purpose:** Specialized date range filter with shortcuts and relative dates.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| date_range_filter | 1 | Renders date range filter UI | |
| parse_shortcut | 1 | Parses date shortcuts (today, this_week, etc.) | |
| parse_relative | 1 | Parses relative dates (5, 3-7, -30) | |
| expand_shortcut | 1 | Expands shortcut to date range | |
| expand_relative | 1 | Expands relative to date range | |
| shortcut_options | 0 | Returns available shortcuts | |
| is_shortcut? | 1 | Checks if value is shortcut | |
| is_relative? | 1 | Checks if value is relative | |
| to_filter_clause | 1 | Converts to Selecto filter | |

---

### lib/selecto_components/filter/numeric_range_filter.ex
**References:** 2+ files
**Purpose:** Numeric range filter with between/boundaries support.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| numeric_range_filter | 1 | Renders numeric range filter | |
| parse_range | 1 | Parses range string | |
| to_filter_clause | 1 | Converts to Selecto filter | |
| format_value | 2 | Formats numeric value | |

---

### lib/selecto_components/filter/multi_select_filter.ex
**References:** 2+ files
**Purpose:** Multi-select filter for lookup/star/tag join modes.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| multi_select_filter | 1 | Renders multi-select filter | |
| checkbox_list | 1 | Checkbox list for small datasets | |
| searchable_select | 1 | Searchable select for large datasets | |
| load_options | 2 | Loads options from database | |
| to_filter_clause | 1 | Converts to IN clause | |

---

### lib/selecto_components/filter/custom_expression.ex
**References:** 2+ files
**Purpose:** Custom SQL expression filter builder.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| custom_expression | 1 | Renders custom expression builder | |
| validate_expression | 1 | Validates SQL expression | |
| parse_expression | 1 | Parses expression string | |
| to_filter_clause | 1 | Converts to Selecto filter | |
| safe_functions | 0 | Returns allowed SQL functions | |

---

### lib/selecto_components/filter/expression_builder.ex
**References:** 3+ files
**Purpose:** Visual expression builder for complex filters.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| expression_builder | 1 | Renders expression builder UI | |
| parse_tokens | 1 | Tokenizes expression | |
| validate_tokens | 1 | Validates token sequence | |
| build_expression | 1 | Builds expression from tokens | |
| to_filter_clause | 1 | Converts to Selecto filter | |
| get_field_suggestions | 2 | Returns field autocomplete | |
| get_function_suggestions | 1 | Returns function autocomplete | |
| format_expression | 1 | Pretty-prints expression | |

---

### lib/selecto_components/filter/dynamic_filters.ex
**References:** 4+ files
**Purpose:** Dynamic filter generation and management.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| dynamic_filters | 1 | Main dynamic filters component | |
| add_filter | 3 | Adds a new filter | |
| remove_filter | 2 | Removes a filter | |
| update_filter | 3 | Updates filter value | |
| reorder_filters | 2 | Reorders filter list | |
| apply_filters | 2 | Applies filters to query | |
| validate_filters | 1 | Validates all filters | |
| serialize_filters | 1 | Serializes for URL/storage | |
| deserialize_filters | 1 | Deserializes from URL/storage | |
| clear_filters | 1 | Clears all filters | |
| get_active_count | 1 | Returns count of active filters | |
| filter_changed? | 2 | Checks if filters changed | |
| get_filter_summary | 1 | Returns human-readable summary | |
| merge_filters | 2 | Merges filter sets | |
| diff_filters | 2 | Returns filter differences | |
| clone_filter | 1 | Clones a filter | |
| toggle_filter | 2 | Enables/disables filter | |
| group_filters | 1 | Groups filters by field | |

---

### lib/selecto_components/filter/filter_sets.ex
**References:** 3+ files
**Purpose:** Filter set persistence and management.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| filter_sets | 1 | Filter sets management component | |
| save_filter_set | 3 | Saves a filter set | |
| load_filter_set | 2 | Loads a filter set | |
| delete_filter_set | 2 | Deletes a filter set | |
| list_filter_sets | 1 | Lists available sets | |
| rename_filter_set | 3 | Renames a filter set | |
| export_filter_set | 1 | Exports to JSON | |
| import_filter_set | 2 | Imports from JSON | |
| share_filter_set | 2 | Creates shareable link | |
| clone_filter_set | 2 | Clones a filter set | |
| get_recent_sets | 2 | Gets recently used sets | |
| pin_filter_set | 2 | Pins a filter set | |
| unpin_filter_set | 2 | Unpins a filter set | |
| validate_filter_set | 1 | Validates filter set data | |
| merge_filter_sets | 2 | Merges two filter sets | |
| diff_filter_sets | 2 | Shows differences | |
| is_modified? | 2 | Checks if modified from saved | |
| get_filter_set_metadata | 1 | Gets metadata | |
| update_filter_set_metadata | 2 | Updates metadata | |
| filter_sets_storage | 0 | Returns storage backend | |
| configure_storage | 1 | Configures storage backend | |
| migrate_filter_sets | 2 | Migrates between versions | |
| backup_filter_sets | 1 | Creates backup | |

---

## Views Subsystem

### lib/selecto_components/views/detail.ex
**References:** 3+ files
**Purpose:** Detail view module aggregating all detail view components.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| render | 1 | Renders detail view | |

---

### lib/selecto_components/views/detail/component.ex
**References:** 2+ files
**Purpose:** Detail view LiveComponent implementation.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| render | 1 | Main render function | |
| mount | 1 | Component mount | |
| update | 2 | Component update | |
| handle_event | 3 | Event handling | |
| format_cell_value | 3 | Formats cell for display | |
| get_column_class | 2 | Returns CSS class for column | |
| get_row_class | 2 | Returns CSS class for row | |
| render_cell | 2 | Renders individual cell | |
| render_header | 1 | Renders table header | |
| render_pagination | 1 | Renders pagination controls | |
| render_actions | 1 | Renders row actions | |
| render_nested_data | 2 | Renders nested/denormalized data | |
| column_sortable? | 1 | Checks if column is sortable | |
| get_visible_columns | 1 | Returns visible columns | |
| get_column_width | 1 | Returns column width | |

---

### lib/selecto_components/views/detail/form.ex
**References:** 2+ files
**Purpose:** Form component for detail view configuration.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| render | 1 | Renders configuration form | |

---

### lib/selecto_components/views/detail/process.ex
**References:** 3+ files
**Purpose:** Query processing for detail view.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| initial_state | 2 | Returns initial state | |
| view | 5 | Builds query from config | |
| param_to_state | 2 | Converts params to state | |

---

### lib/selecto_components/views/detail/order_by_config.ex
**References:** 2+ files
**Purpose:** Order by configuration component.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| order_by_config | 1 | Renders order by config | |
| validate_order_by | 1 | Validates order by config | |

---

### lib/selecto_components/views/aggregate.ex
**References:** 3+ files
**Purpose:** Aggregate view module aggregating all aggregate view components.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| render | 1 | Renders aggregate view | |

---

### lib/selecto_components/views/aggregate/component.ex
**References:** 2+ files
**Purpose:** Aggregate view LiveComponent implementation.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| render | 1 | Main render function | |
| handle_event | 3 | Event handling for drill-down | |

---

### lib/selecto_components/views/aggregate/form.ex
**References:** 2+ files
**Purpose:** Form component for aggregate view configuration.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| render | 1 | Renders configuration form | |

---

### lib/selecto_components/views/aggregate/process.ex
**References:** 3+ files
**Purpose:** Query processing for aggregate view.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| initial_state | 2 | Returns initial state | |
| view | 5 | Builds query from config | |
| param_to_state | 2 | Converts params to state | |
| build_group_by | 2 | Builds GROUP BY clause | |
| build_aggregates | 2 | Builds aggregate functions | |

---

### lib/selecto_components/views/aggregate/group_by_config.ex
**References:** 2+ files
**Purpose:** Group by configuration component.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| group_by_config | 1 | Renders group by config | |

---

### lib/selecto_components/views/aggregate/aggregate_config.ex
**References:** 2+ files
**Purpose:** Aggregate function configuration component.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| aggregate_config | 1 | Renders aggregate config | |

---

### lib/selecto_components/views/graph.ex
**References:** 3+ files
**Purpose:** Graph view module aggregating all graph view components.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| render | 1 | Renders graph view | |

---

### lib/selecto_components/views/graph/component.ex
**References:** 2+ files
**Purpose:** Graph view LiveComponent implementation.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| render | 1 | Main render function | |
| handle_event | 3 | Event handling for clicks | |
| prepare_chart_data | 2 | Transforms data for charts | |
| get_chart_options | 1 | Returns chart.js options | |

---

### lib/selecto_components/views/graph/form.ex
**References:** 2+ files
**Purpose:** Form component for graph view configuration.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| render | 1 | Renders configuration form | |

---

### lib/selecto_components/views/graph/process.ex
**References:** 3+ files
**Purpose:** Query processing for graph view.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| initial_state | 2 | Returns initial state | |
| view | 5 | Builds query from config | |
| param_to_state | 2 | Converts params to state | |
| build_series_query | 2 | Builds series data query | |
| normalize_data | 2 | Normalizes chart data | |

---

### lib/selecto_components/views/graph/x_axis_config.ex
**References:** 2+ files
**Purpose:** X-axis configuration component.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| x_axis_config | 1 | Renders X-axis config | |

---

### lib/selecto_components/views/graph/y_axis_config.ex
**References:** 2+ files
**Purpose:** Y-axis configuration component.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| y_axis_config | 1 | Renders Y-axis config | |

---

### lib/selecto_components/views/graph/series_config.ex
**References:** 2+ files
**Purpose:** Series configuration component.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| series_config | 1 | Renders series config | |

---

## Components Subsystem

### lib/selecto_components/components/common.ex
**References:** 8+ files
**Purpose:** Shared UI components used across SelectoComponents.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| icon | 1 | Renders SVG icon | |
| loading_spinner | 1 | Loading spinner animation | |
| empty_state | 1 | Empty state display | |
| error_message | 1 | Error message display | |
| success_message | 1 | Success message display | |
| confirm_dialog | 1 | Confirmation dialog | |
| tooltip | 1 | Tooltip component | |
| badge | 1 | Badge component | |
| truncate | 1 | Text truncation | |

---

### lib/selecto_components/components/list_picker.ex
**References:** 4+ files
**Purpose:** Drag-and-drop list picker for field selection.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| list_picker | 1 | Main list picker component | |
| available_items | 1 | Available items panel | |
| selected_items | 1 | Selected items panel | |
| search_input | 1 | Search/filter input | |

---

### lib/selecto_components/components/tree_builder.ex
**References:** 3+ files
**Purpose:** Hierarchical tree builder for filter organization.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| tree_builder | 1 | Main tree builder component | |
| tree_node | 1 | Individual tree node | |
| tree_branch | 1 | Tree branch container | |

---

### lib/selecto_components/components/nested_table.ex
**References:** 2+ files
**Purpose:** Nested/hierarchical table display.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| nested_table | 1 | Main nested table component | |
| nested_row | 1 | Expandable nested row | |
| nested_content | 1 | Nested content area | |
| expand_all | 1 | Expand all rows | |
| collapse_all | 1 | Collapse all rows | |
| toggle_row | 2 | Toggle single row | |
| render_nested_data | 2 | Renders nested data | |
| get_nested_columns | 1 | Gets nested column config | |
| format_nested_value | 2 | Formats nested value | |
| is_expandable? | 1 | Checks if row is expandable | |
| get_expansion_depth | 1 | Gets current expansion depth | |
| set_max_depth | 2 | Sets maximum expansion depth | |
| render_expand_icon | 1 | Renders expand/collapse icon | |
| get_row_path | 1 | Gets path to row in tree | |
| find_row_by_path | 2 | Finds row by path | |
| update_row_by_path | 3 | Updates row at path | |

---

### lib/selecto_components/components/tabs.ex
**References:** 2+ files
**Purpose:** Tab navigation components.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| tabs | 1 | Tab container | |
| tab_button | 1 | Individual tab button | |

---

### lib/selecto_components/components/radio_tabs.ex
**References:** 2+ files
**Purpose:** Radio-style tab selection.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| radio_tabs | 1 | Radio tab group | |
| radio_tab | 1 | Individual radio tab | |

---

### lib/selecto_components/components/sql_debug.ex
**References:** 2+ files
**Purpose:** SQL query debugging display.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| sql_debug | 1 | SQL debug panel | |
| format_sql | 1 | Formats SQL for display | |
| highlight_sql | 1 | Syntax highlighting | |
| copy_sql | 1 | Copy to clipboard | |

---

## Form Event Handlers

### lib/selecto_components/form/event_handlers.ex
**References:** Central hub for form events
**Purpose:** Aggregates all form event handler modules.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| __using__ | 1 | Imports all event handlers | |
| get_initial_state | 2 | Initializes form state | |
| handle_info | 2 | Handles :view_set message | |

---

### lib/selecto_components/form/event_handlers/view_lifecycle.ex
**Purpose:** View configuration and validation events.

#### Key Events
- `set_active_tab` - Tab switching
- `view-validate` - Form validation
- `view-apply` - Form submission
- `load_view_config` - Load saved config

---

### lib/selecto_components/form/event_handlers/filter_operations.ex
**Purpose:** Filter manipulation events.

#### Key Events
- `treedrop` - Drag-and-drop filter add
- `filter_remove` - Remove filter
- `toggle_conjunction` - AND/OR toggle

---

### lib/selecto_components/form/event_handlers/drill_down.ex
**Purpose:** Drill-down navigation from aggregates/graphs.

#### Key Events
- `agg_add_filters` - Drill from aggregate
- `graph_drill_down` - Drill from graph
- `chart_click` - Chart element click

---

### lib/selecto_components/form/event_handlers/list_operations.ex
**Purpose:** List picker operations.

#### Key Events
- `list_picker_add` - Add item to list
- `list_picker_remove` - Remove from list
- `list_picker_move` - Reorder list

---

### lib/selecto_components/form/event_handlers/query_operations.ex
**Purpose:** Query execution and results handling.

#### Key Events
- `handle_params` - URL parameter routing
- `rerun_query_with_sort` - Sort results
- `update_detail_page` - Pagination
- `query_executed` - Query completion

---

### lib/selecto_components/form/event_handlers/modal_operations.ex
**Purpose:** Modal dialog events.

#### Key Events
- `show_detail_modal` - Open modal
- `close_detail_modal` - Close modal

---

### lib/selecto_components/form/params_state.ex
**References:** 8+ files
**Purpose:** URL parameter and state bidirectional conversion.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| view_config_to_params | 1 | Converts config to URL params | |
| filters_to_params | 1 | Converts filters to params | |
| view_filter_process | 2 | Processes filter params | |
| view_from_params | 2 | Executes view from URL params | Core function |
| view_from_params_with_sort | 3 | Executes with sorting | |
| filter_params_to_state | 2 | Updates filter state | |
| params_to_state | 2 | Full state update | |
| convert_saved_config_to_full_params | 2 | Saved config conversion | |
| view_params_changed? | 2 | Checks for significant changes | |
| view_specific_params_changed? | 3 | Checks view-specific changes | |
| normalize_param_map | 1 | Normalizes for comparison | |
| filter_structure_changed? | 2 | Checks filter structure | |
| state_to_url | 2 | Updates URL from state | |

---

### lib/selecto_components/form/filter_rendering.ex
**References:** 3+ files
**Purpose:** Filter form rendering logic.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| render_filter_form | 5 | Main filter form renderer | |
| render_datetime_filter | 1 | Datetime-specific filter | |
| render_standard_filter | 1 | Standard text/number filter | |
| format_datetime_value | 2 | Formats datetime for input | |
| is_date_shortcut | 1 | Checks for date shortcuts | |
| is_relative_date | 1 | Checks for relative dates | |
| hash_filter_structure | 1 | Hashes filter structure | |
| build_filter_list | 1 | Builds available filters | |

---

## Enhanced Table Subsystem

### lib/selecto_components/enhanced_table/sorting.ex
**References:** 3+ files
**Purpose:** Table column sorting functionality.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| init_sort_state | 1 | Initializes sort state | |
| handle_sort_click | 3 | Handles column click | |
| apply_sort_to_query | 2 | Applies sorting to query | |
| get_sort_indicator | 2 | Gets sort direction | |
| get_sort_position | 2 | Gets multi-sort position | |
| sort_indicator | 1 | Sort indicator component | |
| sortable_header | 1 | Sortable header component | |
| serialize_sort | 1 | Serializes for storage | |
| deserialize_sort | 1 | Deserializes from storage | |

---

### lib/selecto_components/enhanced_table/column_resize.ex
**Purpose:** Column resize functionality with drag handles.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| init_column_widths | 2 | Initializes column widths | |
| handle_resize | 3 | Handles resize event | |
| resize_handle | 1 | Resize handle component | |
| get_column_width | 2 | Gets current width | |
| set_column_width | 3 | Sets column width | |
| reset_column_widths | 1 | Resets to defaults | |
| save_column_widths | 2 | Persists widths | |
| load_column_widths | 1 | Loads saved widths | |
| __hooks__ | 0 | Returns JS hooks | |

---

### lib/selecto_components/enhanced_table/column_reorder.ex
**Purpose:** Column reordering via drag-and-drop.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| init_column_order | 1 | Initializes column order | |
| handle_reorder | 3 | Handles reorder event | |
| get_ordered_columns | 1 | Gets columns in order | |
| move_column | 4 | Moves column position | |
| reset_column_order | 1 | Resets to default order | |
| save_column_order | 2 | Persists order | |
| load_column_order | 1 | Loads saved order | |
| __hooks__ | 0 | Returns JS hooks | |

---

### lib/selecto_components/enhanced_table/row_selection.ex
**Purpose:** Row selection with checkboxes.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| init_selection | 1 | Initializes selection state | |
| select_row | 2 | Selects a row | |
| deselect_row | 2 | Deselects a row | |
| toggle_row | 2 | Toggles row selection | |
| select_all | 1 | Selects all rows | |
| deselect_all | 1 | Deselects all rows | |
| toggle_all | 1 | Toggles all rows | |
| get_selected | 1 | Gets selected row IDs | |
| get_selected_count | 1 | Gets selection count | |
| is_selected? | 2 | Checks if row selected | |
| selection_checkbox | 1 | Checkbox component | |
| header_checkbox | 1 | Header checkbox component | |

---

### lib/selecto_components/enhanced_table/bulk_actions.ex
**Purpose:** Bulk operations on selected rows.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| bulk_actions_bar | 1 | Bulk actions toolbar | |
| register_action | 3 | Registers bulk action | |
| execute_action | 3 | Executes bulk action | |
| available_actions | 1 | Lists available actions | |
| confirm_action | 2 | Shows confirmation | |
| action_button | 1 | Action button component | |

---

### lib/selecto_components/enhanced_table/inline_edit.ex
**Purpose:** Inline cell editing functionality.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| init_edit_state | 1 | Initializes edit state | |
| start_edit | 3 | Starts editing cell | |
| cancel_edit | 1 | Cancels editing | |
| save_edit | 2 | Saves edit changes | |
| editable_cell | 1 | Editable cell component | |
| edit_input | 1 | Edit input component | |
| is_editing? | 3 | Checks if cell editing | |
| get_edit_value | 1 | Gets current edit value | |
| validate_edit | 2 | Validates edit value | |

---

### lib/selecto_components/enhanced_table/virtualization.ex
**Purpose:** Virtual scrolling for large datasets.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| init_virtualization | 2 | Initializes virtual scroll | |
| virtual_table | 1 | Virtual table component | |
| handle_scroll | 2 | Handles scroll events | |
| get_visible_rows | 1 | Gets currently visible rows | |
| calculate_viewport | 2 | Calculates viewport bounds | |
| __hooks__ | 0 | Returns JS hooks | |

---

## Error Handling Subsystem

### lib/selecto_components/error_handling/error_categorizer.ex
**References:** 4+ files
**Purpose:** Categorizes and classifies errors.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| categorize | 1 | Main categorization function | |
| format_message | 1 | Formats user-friendly message | |
| recovery_suggestion | 1 | Provides recovery suggestions | |

---

### lib/selecto_components/error_handling/error_sanitizer.ex
**References:** 3+ files
**Purpose:** Sanitizes errors for production environments.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| production_env? | 0 | Checks if production | |
| sanitize_error | 2 | Sanitizes error data | |
| sanitize_details | 2 | Sanitizes error details | |
| sanitize_suggestions | 1 | Sanitizes suggestions | |
| user_friendly_message | 1 | Returns safe message | |
| safe_suggestions | 1 | Returns safe suggestions | |

---

### lib/selecto_components/error_handling/error_recovery.ex
**References:** 3+ files
**Purpose:** Error recovery with retry logic.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| retryable_error? | 1 | Checks if retryable | |
| classify_error | 1 | Classifies error type | |
| init_retry_state | 1 | Initializes retry state | |
| retry_operation | 3 | Attempts retry | |
| calculate_backoff | 1 | Calculates backoff delay | |
| schedule_retry | 3 | Schedules retry | |
| preserve_state | 2 | Preserves state for retry | |
| restore_state | 1 | Restores preserved state | |
| reset_retry_state | 1 | Resets retry state | |
| retry_status | 1 | Retry status component | |
| retry_button | 1 | Retry button component | |
| handle_retry_message | 2 | Handles retry messages | |

---

### lib/selecto_components/error_handling/error_display.ex
**References:** 2+ files
**Purpose:** Error display LiveComponent.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| render | 1 | Main render function | |
| error_card | 1 | Error card component | |
| error_details | 1 | Error details (dev mode) | |
| selecto_error_details | 1 | Selecto-specific details | |
| mount | 1 | Component mount | |
| update | 2 | Component update | |
| handle_event | 3 | Event handling | |

---

## Performance Subsystem

### lib/selecto_components/performance/metrics_collector.ex
**References:** 3+ files
**Purpose:** Query performance metrics collection (GenServer).

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| start_link | 1 | Starts GenServer | |
| record_query | 3 | Records query execution | |
| record_error | 2 | Records error | |
| record_cache | 1 | Records cache hit/miss | |
| get_metrics | 1 | Gets current metrics | |
| get_slow_queries | 2 | Gets slow queries | |
| get_timeline | 1 | Gets query timeline | |
| clear_metrics | 0 | Clears all metrics | |

---

### lib/selecto_components/performance/virtual_scroll.ex
**Purpose:** Virtual scrolling implementation.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| init | 1 | Initializes virtual scroll | |
| virtual_container | 1 | Container component | |
| calculate_visible | 2 | Calculates visible items | |
| handle_scroll | 2 | Handles scroll events | |
| __hooks__ | 0 | Returns JS hooks | |

---

### lib/selecto_components/performance/dashboard.ex
**Purpose:** Performance monitoring dashboard.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| dashboard | 1 | Main dashboard component | |
| metrics_panel | 1 | Metrics display panel | |
| slow_queries_panel | 1 | Slow queries list | |
| timeline_chart | 1 | Query timeline chart | |
| refresh_metrics | 1 | Refreshes metrics | |
| export_metrics | 1 | Exports metrics data | |

---

## Responsive Subsystem

### lib/selecto_components/responsive/responsive_table.ex
**References:** 2+ files
**Purpose:** Responsive table that adapts to screen sizes.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| init_responsive_table | 1 | Initializes responsive state | |
| set_column_priorities | 2 | Sets column display priorities | |
| update_view_mode | 2 | Updates view mode by width | |
| update_orientation | 2 | Updates device orientation | |
| responsive_table | 1 | Main responsive table | |
| mobile_card_view | 1 | Mobile card layout | |
| responsive_header | 1 | Responsive header cell | |
| responsive_cell | 1 | Responsive table cell | |
| column_selector | 1 | Column visibility selector | |
| sticky_header | 1 | Sticky header component | |
| __hooks__ | 0 | Returns JS hooks | |

---

### lib/selecto_components/responsive/mobile_layout.ex
**References:** 2+ files
**Purpose:** Mobile-optimized layout components.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| stacked_view | 1 | Mobile stacked card view | |
| accordion_view | 1 | Accordion expandable view | |
| swipeable_cards | 1 | Swipeable card carousel | |
| mobile_actions | 1 | Mobile action buttons | |
| mobile_filter_bar | 1 | Collapsible filter bar | |
| floating_action_button | 1 | FAB component | |
| __hooks__ | 0 | Returns JS hooks | |

---

## Modal Subsystem

### lib/selecto_components/modal/modal_wrapper.ex
**References:** 2+ files
**Purpose:** Reusable modal wrapper with animations.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| modal | 1 | Modal component | |
| show_modal | 1 | Shows modal with animation | |
| hide_modal | 1 | Hides modal with animation | |
| __hooks__ | 0 | Returns JS hooks | |

---

### lib/selecto_components/modal/detail_modal.ex
**References:** 2+ files
**Purpose:** Detail record modal with navigation.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| mount | 1 | Component mount | |
| update | 2 | Component update | |
| render | 1 | Main render function | |
| handle_event | 3 | Event handling | |

---

## Dashboard/Widget Subsystem

### lib/selecto_components/dashboard/widget_registry.ex
**Purpose:** Widget type registration.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| register | 3 | Registers widget type | |
| get | 1 | Gets widget by ID | |
| list_all | 0 | Lists all widgets | |
| unregister | 1 | Removes widget | |
| widget_types | 0 | Returns available types | |
| validate_config | 2 | Validates widget config | |
| default_config | 1 | Returns default config | |

---

### lib/selecto_components/dashboard/layout_manager.ex
**Purpose:** Dashboard layout management.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| init_layout | 1 | Initializes layout | |
| add_widget | 3 | Adds widget to layout | |
| remove_widget | 2 | Removes widget | |
| move_widget | 4 | Moves widget position | |
| resize_widget | 3 | Resizes widget | |
| save_layout | 2 | Saves layout | |
| load_layout | 1 | Loads layout | |
| export_layout | 1 | Exports layout JSON | |
| import_layout | 2 | Imports layout JSON | |
| get_widget_position | 2 | Gets widget position | |
| set_widget_position | 3 | Sets widget position | |
| calculate_grid | 1 | Calculates grid layout | |
| validate_layout | 1 | Validates layout | |
| reset_layout | 1 | Resets to default | |

---

### lib/selecto_components/dashboard/kpi_card.ex
**Purpose:** KPI display card component.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| kpi_card | 1 | Main KPI card | |
| format_value | 2 | Formats KPI value | |
| trend_indicator | 1 | Trend arrow indicator | |

---

### lib/selecto_components/dashboard/sparkline.ex
**Purpose:** Sparkline mini-chart component.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| sparkline | 1 | Main sparkline | |
| calculate_points | 2 | Calculates SVG points | |
| bar_sparkline | 1 | Bar chart variant | |
| line_sparkline | 1 | Line chart variant | |
| area_sparkline | 1 | Area chart variant | |
| __hooks__ | 0 | Returns JS hooks | |

---

### lib/selecto_components/dashboard/metric_display.ex
**Purpose:** Metric display components.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| metric_display | 1 | Main metric display | |
| comparison_display | 1 | Period comparison | |
| gauge_display | 1 | Gauge visualization | |
| progress_metric | 1 | Progress bar metric | |
| percentage_display | 1 | Percentage display | |
| currency_display | 1 | Currency display | |
| number_display | 1 | Number display | |
| date_display | 1 | Date display | |
| duration_display | 1 | Duration display | |
| format_metric | 2 | Formats metric value | |
| apply_formatting | 2 | Applies formatting | |
| calculate_change | 2 | Calculates period change | |

---

## Utility Modules

### lib/selecto_components/helpers/filters.ex
**References:** 6+ files
**Purpose:** Filter processing helper functions.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| filter_recurse | 3 | Recursively processes filters | |

---

### lib/selecto_components/helpers/bucket_parser.ex
**Purpose:** Date/time bucket parsing for grouping.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| parse_bucket | 1 | Parses bucket string | |
| bucket_to_sql | 2 | Converts to SQL | |
| available_buckets | 0 | Returns available buckets | |
| validate_bucket | 1 | Validates bucket config | |
| bucket_options | 1 | Returns bucket options | |

---

### lib/selecto_components/denormalization_detector.ex
**Purpose:** Detects denormalization needs.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| analyze_columns | 2 | Analyzes for denorm needs | |
| get_denorm_groups | 1 | Gets denormalization groups | |
| should_denormalize? | 2 | Checks if should denorm | |
| estimate_duplication | 2 | Estimates row duplication | |

---

### lib/selecto_components/subselect_builder.ex
**Purpose:** Builds subselects for denormalization.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| add_subselect_for_group | 3 | Adds subselect to query | |
| build_subselect | 3 | Builds subselect SQL | |
| merge_subselect_results | 2 | Merges results | |
| detect_subselect_paths | 2 | Detects needed paths | |
| optimize_subselects | 1 | Optimizes subselect queries | |
| validate_subselect_config | 1 | Validates config | |
| get_subselect_columns | 1 | Gets columns for subselect | |
| format_subselect_result | 2 | Formats result data | |
| handle_null_subselects | 1 | Handles null values | |

---

### lib/selecto_components/view_config_manager.ex
**Purpose:** View configuration management.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| save_config | 3 | Saves view configuration | |
| load_config | 2 | Loads view configuration | |
| delete_config | 2 | Deletes configuration | |
| list_configs | 1 | Lists saved configs | |
| export_config | 1 | Exports config JSON | |
| import_config | 2 | Imports config JSON | |
| validate_config | 1 | Validates configuration | |
| merge_configs | 2 | Merges configurations | |
| diff_configs | 2 | Compares configurations | |
| get_default_config | 1 | Gets default config | |
| set_default_config | 2 | Sets default config | |
| clone_config | 2 | Clones configuration | |

---

### lib/selecto_components/saved_views.ex
**Purpose:** Saved view persistence.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| save_view | 3 | Saves a view | |
| load_view | 2 | Loads a saved view | |
| delete_view | 2 | Deletes a view | |
| list_views | 1 | Lists saved views | |
| get_recent_views | 2 | Gets recent views | |
| pin_view | 2 | Pins a view | |
| unpin_view | 2 | Unpins a view | |
| share_view | 2 | Creates shareable view | |
| import_shared_view | 2 | Imports shared view | |

---

### lib/selecto_components/parameterized_field_builder.ex
**Purpose:** Builds parameterized field definitions.

#### Public Functions
| Function | Arity | Description | Notes |
|----------|-------|-------------|-------|
| build_field | 2 | Builds parameterized field | |
| parse_parameters | 1 | Parses field parameters | |
| validate_parameters | 2 | Validates parameters | |
| apply_parameters | 2 | Applies parameters to field | |
| get_parameter_schema | 1 | Gets parameter schema | |
| default_parameters | 1 | Gets default parameters | |
| merge_parameters | 2 | Merges parameter sets | |
| format_with_parameters | 2 | Formats with parameters | |

---

## Architecture Notes

### Module Organization
The codebase follows a well-organized hierarchical structure:
- Core modules at top level (`selecto_components.ex`, `form.ex`, `ui.ex`)
- Feature subsystems in subdirectories (`filter/`, `views/`, `components/`)
- Clear separation between UI components and business logic

### Design Patterns
1. **Use macro pattern** - Main entry points use `__using__` macros
2. **LiveComponent pattern** - Complex UI uses Phoenix LiveComponents
3. **Event handler separation** - Events organized by domain
4. **Functional components** - Simple UI uses function components
5. **GenServer for state** - MetricsCollector uses GenServer for persistence

### Security Considerations
- `SafeAtom` module prevents atom table exhaustion
- `ErrorSanitizer` removes sensitive data in production
- Input validation throughout filter system

### Areas for Potential Improvement
1. Some modules have very large function counts (SafeAtom, EnhancedTable components)
2. Some backup files exist that could be cleaned up (*.backup)
3. Test coverage could be documented
4. Some modules could benefit from more documentation

---

*This document was auto-generated for code review purposes.*
