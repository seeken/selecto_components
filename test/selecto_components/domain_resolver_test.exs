defmodule SelectoComponents.DomainResolverTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias Selecto.Domain.Ref
  alias SelectoComponents.DomainResolver

  defmodule Registry do
    @behaviour Selecto.Domain.Registry

    @impl true
    def fetch("orders", %{actor: %{id: 7}}) do
      {:ok, SelectoComponents.DomainResolverTest.domain(), %{scope: :actor}}
    end

    def fetch("orders", _context), do: {:error, :forbidden}
    def fetch(_id, _context), do: {:error, :not_found}
  end

  test "requires exactly one configured domain source" do
    assert_raise ArgumentError, ~r/:domain, :resolver, or :registry/, fn ->
      DomainResolver.init!([], __MODULE__)
    end

    assert_raise ArgumentError, ~r/exactly one domain source/, fn ->
      DomainResolver.init!([domain: domain(), registry: Registry], __MODULE__)
    end
  end

  test "resolves an opaque request id through a trusted registry and preserves provenance" do
    conn =
      :get
      |> conn("/selecto/schema/orders/query-contract.json")
      |> Map.put(:path_params, %{"domain" => "orders"})

    opts =
      DomainResolver.init!(
        [
          registry: Registry,
          registry_context: fn _conn -> %{actor: %{id: 7}} end,
          registry_options: fn _conn -> [actor: %{id: 7}, capability_resolver: :trusted] end
        ],
        __MODULE__
      )

    assert {:ok, resolved, resolved_opts} = DomainResolver.resolve(conn, opts, "query contract")
    assert resolved.name == "Orders"
    assert resolved_opts[:domain_id] == "orders"
    assert resolved_opts[:actor] == %{id: 7}
    assert resolved_opts[:capability_resolver] == :trusted

    assert %Ref{id: "orders", registry: Registry, metadata: %{scope: :actor}} =
             resolved_opts[:domain_ref]
  end

  test "registry options cannot replace registry provenance" do
    conn = conn(:get, "/query-contract.json")

    opts = [
      registry: Registry,
      domain_id: "orders",
      registry_context: %{actor: %{id: 7}},
      registry_options: [domain_id: "spoofed", domain_ref: :spoofed]
    ]

    assert {:ok, _domain, resolved_opts} = DomainResolver.resolve(conn, opts, "query contract")
    assert resolved_opts[:domain_id] == "orders"
    assert %Ref{id: "orders", registry: Registry} = resolved_opts[:domain_ref]
  end

  test "maps unknown and unauthorized registry ids to the same public response" do
    for {id, context} <- [{"missing", %{actor: %{id: 7}}}, {"orders", %{}}] do
      conn =
        :get
        |> conn("/selecto/schema/#{id}/query-contract.json")
        |> Map.put(:path_params, %{"domain" => id})

      opts = [registry: Registry, registry_context: context]

      assert {:error, 404, :not_found, "query contract domain not found"} =
               DomainResolver.resolve(conn, opts, "query contract")
    end
  end

  def domain do
    %{
      schema_version: 1,
      domain_version: "1.0.0",
      domain_fingerprint: "sha256:orders",
      name: "Orders",
      source: %{
        source_table: "orders",
        primary_key: :id,
        fields: [:id, :status],
        columns: %{
          id: %{type: :integer, name: "ID"},
          status: %{type: :string, name: "Status"}
        },
        associations: %{}
      },
      schemas: %{},
      joins: %{}
    }
  end
end
