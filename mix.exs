defmodule SelectoComponents.MixProject do
  use Mix.Project

  def project do
    [
      app: :selecto_components,
      version: "0.5.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      description:
        "Alpha: Phoenix LiveView components for interactive Selecto query building and data exploration",
      aliases: aliases(),
      package: package(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      deps: deps(),

      # Test coverage
      test_coverage: [tool: ExCoveralls]
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.json": :test,
        precommit: :test
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {SelectoComponents.Application, []},
      extra_applications: [:logger, :crypto]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:phoenix, "~> 1.8.0"},
      {:phoenix_live_view, "~> 1.1.4 or ~> 1.2.0"},
      # {:phoenix_html_helpers, "~> 1.0"},
      ecosystem_dep(:selecto, "selecto",
        ref: "62c9bce7de1b3918daf7e467b57cf750e6f10bba",
        override: true
      ),
      ecosystem_dep(:selecto_templates, "selecto_templates",
        ref: "4f22f50c52236655bca553a51479615f7e3b5732"
      ),
      {:uuid, "~> 1.1"},
      {:ex_doc, "~> 0.29.1", only: :dev, runtime: false},
      # {:vega_lite, "~> 0.1.6"},
      {:tzdata, "~> 1.1"},
      {:jason, "~> 1.2"},
      {:esbuild, "~> 0.5", runtime: Mix.env() == :dev},
      {:ecto, ">= 3.9.1 and < 4.0.0"},
      {:makeup, "~> 1.1"},
      {:makeup_sql, "~> 0.1.0"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:stream_data, "~> 1.1", only: :test},
      {:excoveralls, "~> 0.18", only: :test}
    ]
  end

  # --- Selecto ecosystem dependency resolution -------------------------------
  # Resolves a sibling Selecto package from a local checkout when one is
  # available and from its pinned GitHub commit otherwise.
  #
  #   SELECTO_LIVE_<SIBLING>       path to a checkout, overriding discovery
  #   SELECTO_ECOSYSTEM_USE_LOCAL  1/true forces siblings, 0/false forces git
  #   SELECTO_ECOSYSTEM_GIT_URL    "ssh" fetches over SSH instead of HTTPS
  #
  # A mix.exs cannot depend on a package to compute its own deps, so this block
  # is duplicated verbatim across the Selecto repos. Keep the copies identical.
  defp ecosystem_dep(name, sibling_name, opts) do
    {ref, dep_opts} = Keyword.pop!(opts, :ref)

    case ecosystem_sibling_path(sibling_name) do
      nil -> {name, Keyword.merge(ecosystem_git_source(sibling_name, ref), dep_opts)}
      path -> {name, Keyword.put(dep_opts, :path, path)}
    end
  end

  defp ecosystem_git_source(sibling_name, ref) do
    case System.get_env("SELECTO_ECOSYSTEM_GIT_URL") do
      value when value in ["ssh", "SSH"] ->
        [git: "git@github.com:seeken/#{sibling_name}.git", ref: ref]

      _value ->
        [github: "seeken/#{sibling_name}", ref: ref]
    end
  end

  defp ecosystem_sibling_path(sibling_name) do
    case System.get_env("SELECTO_LIVE_" <> String.upcase(sibling_name)) do
      path when is_binary(path) and path != "" ->
        Path.expand(path, __DIR__)

      _value ->
        sibling = Path.expand("../#{sibling_name}", __DIR__)

        case System.get_env("SELECTO_ECOSYSTEM_USE_LOCAL") do
          value when value in ["0", "false", "FALSE", "no", "NO", "off", "OFF"] -> nil
          value when value in ["1", "true", "TRUE", "yes", "YES", "on", "ON"] -> sibling
          _value -> if File.dir?(sibling), do: sibling
        end
    end
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/selecto-elixir/selecto_components",
        "SQL Patterns" => "https://seeken.github.io/selecto-sql-patterns",
        "Demo (Fly)" => "https://testselecto.fly.dev"
      },
      source_url: "https://github.com/selecto-elixir/selecto_components",
      files:
        ~w(mix.exs README.md CHANGELOG.md LICENSE lib/**/*.ex lib/**/*.js package.json priv/static/selecto_components.min.js)
    ]
  end

  defp aliases do
    [
      "assets.package": [
        "cmd mkdir -p priv/static",
        "esbuild.install --if-missing",
        "esbuild package --minify"
      ],
      "credo.atom_audit": ["credo -C atom_audit --all-priorities"],
      precommit: [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "cmd scripts/check_postgresql_boundary.sh",
        "credo",
        "test"
      ]
    ]
  end
end
