defmodule SelectoComponents.NativeAdversarialFixture do
  @moduledoc false
  @path Path.join(__DIR__, "fixtures/adversarial_v1.json")
  @sha256 "9fe6115b44e8daab52c2d0d7a25412488895a8e3f4d1f477ecb324889c3d7ecd"
  @tables %{"people" => "selecto_cert_adv_people", "orders" => "selecto_cert_adv_orders"}
  @fields %{
    "id" => :id,
    "tenant_id" => :tenant_id,
    "name" => :name,
    "secret_score" => :secret_score,
    "ssn" => :ssn,
    "amount" => :amount
  }
  @options %{
    "internal" => :internal,
    "hidden" => :hidden,
    "filterable" => :filterable,
    "sortable" => :sortable,
    "groupable" => :groupable
  }
  @types %{"integer" => :integer, "string" => :string}

  def load do
    bytes = File.read!(@path)

    unless Base.encode16(:crypto.hash(:sha256, bytes), case: :lower) == @sha256,
      do: raise("LiveView fixture differs from the shared input-only fixture")

    Jason.decode!(bytes)
  end

  def variants(fixture),
    do: [%{"variant" => "baseline", "dataset" => fixture["dataset"]} | fixture["variants"]]

  def domain(fixture, hidden? \\ false) do
    authored = if hidden?, do: fixture["case_domains"]["AF003"], else: fixture["domain"]
    source = authored["source"]

    columns =
      Map.new(source["columns"], fn {field, config} ->
        definition =
          Map.new(config, fn
            {"type", type} -> {:type, Map.fetch!(@types, type)}
            {flag, value} -> {Map.fetch!(@options, flag), value}
          end)

        {Map.fetch!(@fields, field), definition}
      end)

    %{
      name: "Native adversarial people",
      source: %{
        source_table: source["source_table"],
        primary_key: :id,
        tenant_field: :tenant_id,
        fields: Enum.map(source["fields"], &Map.fetch!(@fields, &1)),
        redact_fields: Enum.map(source["redact_fields"], &Map.fetch!(@fields, &1)),
        columns: columns,
        associations: %{}
      },
      joins: %{},
      schemas: %{},
      default_selected: ["id", "name"],
      default_order_by: ["id"]
    }
  end

  def source(connection, tenant, name_filter \\ nil, hidden? \\ false) do
    selecto =
      domain(load(), hidden?)
      |> Selecto.configure(connection,
        adapter: SelectoDBPostgreSQL.Adapter,
        mode: :strict,
        domain_sql: :declared
      )
      |> Selecto.with_tenant(%{tenant_id: tenant, tenant_field: "tenant_id", required: true})
      |> Selecto.apply_tenant_scope()

    if name_filter, do: Selecto.filter(selecto, {"name", name_filter}), else: selecto
  end

  def reset(connection, dataset) do
    cleanup(connection)

    Postgrex.query!(
      connection,
      "CREATE TABLE selecto_cert_adv_people (id INT NOT NULL PRIMARY KEY, tenant_id INT, name TEXT, secret_score INT, ssn TEXT, amount INT)",
      []
    )

    Postgrex.query!(
      connection,
      "CREATE TABLE selecto_cert_adv_orders (id INT NOT NULL PRIMARY KEY, tenant_id INT, person_id INT, total INT, state TEXT)",
      []
    )

    for {key, table} <- @tables, row <- dataset[key]["rows"] do
      placeholders = 1..length(row) |> Enum.map_join(",", &"$#{&1}")
      Postgrex.query!(connection, "INSERT INTO #{table} VALUES (#{placeholders})", row)
    end

    :ok
  end

  def cleanup(connection),
    do:
      Enum.each(@tables, fn {_key, table} ->
        Postgrex.query!(connection, "DROP TABLE IF EXISTS #{table}", [])
      end)

  def readback(connection),
    do:
      Map.new(@tables, fn {key, table} ->
        {key, Postgrex.query!(connection, "SELECT * FROM #{table} ORDER BY id", []).rows}
      end)

  def expected_state(dataset),
    do: Map.new(dataset, fn {table, data} -> {table, Enum.sort_by(data["rows"], &hd/1)} end)
end
