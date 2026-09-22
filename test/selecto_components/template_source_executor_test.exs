defmodule SelectoComponents.TemplateSourceExecutorTest do
  use ExUnit.Case, async: true

  alias SelectoComponents.TemplateSourceExecutor

  @fixture Path.expand(
             "../../../selecto-protocol/spec/fixtures/templates/order-browser.compile.json",
             __DIR__
           )

  defmodule Adapter do
    @behaviour Selecto.DB.Adapter

    @impl true
    def name, do: :template_source_executor_test

    @impl true
    def connect(pid), do: {:ok, pid}

    @impl true
    def execute(pid, sql, params, opts) do
      send(pid, {:template_query, sql, params, opts})

      {:ok,
       %{
         rows: [[1, "PO-100", "2026-09-21T12:00:00Z", "open", 44]],
         columns: ["id", "order_number", "ordered_at", "status", "customer_id"]
       }}
    end

    @impl true
    def placeholder(index), do: "$#{index}"

    @impl true
    def quote_identifier(identifier), do: ~s("#{identifier}")

    @impl true
    def supports?(_feature), do: false
  end

  test "resolves source intent server-side and obtains fresh scoped authority" do
    manifest = manifest()
    effect = effect(manifest, "PO-100")
    parent = self()

    authorize = fn source, received_effect ->
      send(parent, {:authorized, source["id"], received_effect["generation"]})

      selecto =
        domain()
        |> Selecto.configure(parent, adapter: Adapter, validate: false)
        |> Selecto.with_tenant(%{tenant_id: 7, required: true})
        |> Selecto.apply_tenant_scope()
        |> Selecto.filter({"status", "open"})

      {:ok, selecto}
    end

    assert {:ok, rows} =
             TemplateSourceExecutor.execute(manifest, effect, authorize,
               execute_options: [analyze_complexity: false]
             )

    assert_receive {:authorized, "orders", 1}
    assert_receive {:template_query, sql, params, _adapter_opts}
    assert sql =~ "selecto_root.tenant_id"
    assert 7 in params
    assert "open" in params
    assert "PO-100" in params

    assert rows == [
             %{
               "id" => 1,
               "order_number" => "PO-100",
               "ordered_at" => "2026-09-21T12:00:00Z",
               "status" => "open",
               "customer" => %{"id" => 44}
             }
           ]
  end

  test "rejects unknown effects before asking the host for authority" do
    authorize = fn _source, _effect -> flunk("authorization must not run") end
    unknown = Map.put(effect(manifest(), ""), "source", "missing")

    assert {:error, error} = TemplateSourceExecutor.execute(manifest(), unknown, authorize)
    assert error["code"] == "unknown_source"
  end

  test "bounds authorization and execution failures" do
    manifest = manifest()
    effect = effect(manifest, "PO-100")

    assert {:error, authorization_error} =
             TemplateSourceExecutor.execute(manifest, effect, fn _source, _effect ->
               {:error, %{token: "must-not-escape"}}
             end)

    assert authorization_error["code"] == "source_authorization_failed"
    refute inspect(authorization_error) =~ "must-not-escape"

    authorize = fn _source, _effect -> {:ok, authorized_query()} end

    assert {:error, execution_error} =
             TemplateSourceExecutor.execute(manifest, effect, authorize,
               execute: fn _query, _opts -> {:error, %{password: "must-not-escape"}} end
             )

    assert execution_error["code"] == "source_execution_failed"
    refute inspect(execution_error) =~ "must-not-escape"
  end

  defp manifest, do: @fixture |> File.read!() |> :json.decode()

  defp effect(manifest, search) do
    {:ok, observation} =
      SelectoTemplates.mount_runtime(manifest,
        instance_id: "source-executor-instance",
        release_id: "source-executor-release",
        inputs: %{}
      )

    observation["effects"]
    |> hd()
    |> put_in(["bindings", "state", "search"], search)
  end

  defp authorized_query do
    domain()
    |> Selecto.configure(:compile_only, adapter: Adapter, validate: false)
    |> Selecto.with_tenant(%{tenant_id: 7, required: true})
    |> Selecto.apply_tenant_scope()
  end

  defp domain do
    fingerprint = manifest()["sources"] |> hd() |> Map.fetch!("domain_fingerprint")

    %{
      schema_version: 1,
      domain_version: "1.0.0",
      domain_fingerprint: fingerprint,
      name: "Orders",
      source: %{
        source_table: "orders",
        primary_key: "id",
        tenant_field: "tenant_id",
        fields: ["id", "tenant_id", "order_number", "ordered_at", "status", "customer_id"],
        redact_fields: [],
        columns: %{
          "id" => %{type: :integer},
          "tenant_id" => %{type: :integer, internal: true},
          "order_number" => %{type: :string},
          "ordered_at" => %{type: :utc_datetime},
          "status" => %{type: :string},
          "customer_id" => %{type: :integer}
        },
        associations: %{
          "customer" => %{
            field: "customer",
            queryable: "customers",
            owner_key: "customer_id",
            related_key: "id",
            cardinality: :one,
            source_scope_key: "tenant_id",
            target_scope_key: "tenant_id"
          }
        }
      },
      schemas: %{
        "customers" => %{
          source_table: "customers",
          primary_key: "id",
          fields: ["id", "tenant_id", "company_name"],
          redact_fields: [],
          columns: %{
            "id" => %{type: :integer},
            "tenant_id" => %{type: :integer, internal: true},
            "company_name" => %{type: :string}
          },
          associations: %{}
        }
      },
      joins: %{"customer" => %{type: :left}},
      query_library: %{
        segments: %{
          "searchable_orders" => %{
            filters: [{:eq, "order_number", {:param, "value"}}],
            parameters: %{"value" => %{type: :string, required: true}}
          }
        },
        projections: %{},
        orderings: %{},
        views: %{}
      }
    }
  end
end
