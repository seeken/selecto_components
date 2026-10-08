# Native connected LiveView adversarial slice

This opt-in suite uses real Phoenix connected LiveView processes, the public
form/URL/component event handlers, the production detail-result component,
and the native Selecto PostgreSQL adapter. The existing capture-adapter tests
remain useful planning tests; this suite additionally observes actual rows,
grid cells, page counts, errors, and database state.

On 2026-10-07, all six native tests passed. The combined native and existing
suite passed 1,050 checks (1,046 tests and four properties). The required
`mix precommit` gate passed 1,044 checks (1,040 tests and four properties),
including the compile, format, PostgreSQL production-boundary, and Credo checks.

## Run

Database adapters remain outside this package's production code and dependency
graph. Supply a compiled host runtime containing `db_connection`, `postgrex`,
and `selecto_db_postgresql`, built with the same Elixir/OTP runtime as this
package. The verified run used Elixir 1.20 / OTP 29 and the task-owned MCP
runtime below. The package declares Elixir `~> 1.18`.

```sh
mise exec -- env MIX_ENV=test \
  MIX_BUILD_PATH=/tmp/selecto-components-adversarial-build \
  SELECTO_ECOSYSTEM_USE_LOCAL=1 \
  SELECTO_ADVERSARIAL_RUNTIME_PATH=/tmp/selecto-mcp-adversarial-build/lib \
  SELECTO_COMPONENTS_ADVERSARIAL_DATABASE_URL=postgres://postgres@127.0.0.1:55471/selecto_adv_liveview \
  mix test test/native_adversarial_test.exs

mise exec -- env MIX_ENV=test \
  MIX_BUILD_PATH=/tmp/selecto-components-adversarial-build \
  SELECTO_ECOSYSTEM_USE_LOCAL=1 mix precommit
```

The native suite requires a disposable loopback `selecto_adv_*` database on a
port other than 5432. It creates and drops its owned people/orders tables.
Omitting `SELECTO_ADVERSARIAL_RUNTIME_PATH` leaves the suite out of the default
gate; missing native runtime packages or database configuration fail explicitly.

## Input and proof

`fixtures/adversarial_v1.json` is byte-identical to the input-only central
certification fixture at implementation time. Its loader checks SHA-256
`9fe6115b44e8daab52c2d0d7a25412488895a8e3f4d1f477ecb324889c3d7ecd`.
Expectations are test code, not fixture properties. Host domains translate only
known committed field/type names; browser inputs cannot create atoms.

Every test runs the baseline, changed foreign-row, and changed secret-value
datasets. Full trusted state of both tables is checked against input rows and
after every probe. Public rendered row/page observations and error alerts are
compared across variants. The suite also checks IDs in the real production
grid cells, and checks the entire rendered page for private string canaries,
SQL, internal relation names, and stack details.

| Plan slices | Native observation |
| --- | --- |
| TR-01/02/03 | A browser tenant parameter cannot change trusted scope. Other-tenant equality and negative filters return no rows. A nested OR including the foreign tenant returns only the matching trusted row. |
| TR-17 | Form resubmission retains host `Selecto.filter` and tenant scope. Actual paging controls return the correct trusted rows and total. |
| FV-01/02/03, SURF-02 | URL select/filter/order over internal, redacted, or literal `hidden: true` fields refuses execution. A forged `sort_column` payload reaches the real detail component and remains denied by the parent execution plan. |
| SURF-02 | Real form submissions with conflicting `field`/`filter` or `comparator`/`comp` reject. A public but non-filterable field also rejects filtering. |
| TR-17, cache slice | A trusted host changes the baseline filter on a running view. Real sort reruns return the narrowed or widened rows and total instead of reusing pages from the prior scope. |
| FV-03, SURF-02 | An isolated connected detail host observes ordinary ascending/descending sorting over native rows, then rejects a forged redacted-field sort. |

The regressions exposed two defects: `order_by` over a redacted field was
accepted, and a submitted `comparator: "="` plus `comp: ">"` executed `>` after
the plan discarded aliases. Public query documents and pickers now omit private
fields, while internal validation retains disabled descriptors solely to
preserve documented role-specific denials. Raw conflicting filter keys reach
the existing ambiguity validator. Existing tests and ordinary CTE pickers retain
their behavior.

## Boundaries

Phoenix requires routable LiveViews for `handle_params` and navigation. Form,
URL, and page tests therefore use a real router with `live/3`; `live_isolated/3`
is used for the supported detail-component sorting host. The isolated host
calls the public `ParamsState` execution entry point on the component's actual
sort notification; it has no URL/navigation callbacks.

The host fixes trusted tenant/context in server/session state. The suite does
not certify authentication middleware, a deployed WebSocket handshake, Origin
validation, frame-size limits, exports, saved views, PubSub subscriptions,
record-editor writes, aggregate/graph/map query paths, joined private-field
aliases, other SQL dialects, full-page byte equality, or timing secrecy. Public
observation equality covers the rendered rows/page/count region and production
error alerts; transient Phoenix tokens and other markup are outside that claim.
The tests cover the named slices, not complete catalog rows or the entire plan.
