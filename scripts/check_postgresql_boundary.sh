#!/usr/bin/env bash
set -euo pipefail

production_pattern='Postgrex|postgrex_opts|postgres|23505|23503|23502|LIMIT[[:space:]]+\$[0-9]+'
native_type_pattern='(^|[^[:alnum:]_])(tsvector|tsquery|jsonb|int2|int4|int8|float4|float8|bpchar|timestamptz|timetz|bytea|regclass|hstore|macaddr|bigserial|smallserial)([^[:alnum:]_]|$)'
dependency_pattern='Postgrex|postgrex|selecto_db_postgresql|postgrex_opts'
component_sql_pattern='interpolate_params|escape_sql_value|ARRAY\[|(^|[^[:alnum:]_])psql([^[:alnum:]_]|$)'
postgresql_sql_pattern='(^|[^[:alnum:]_])(ILIKE|TO_CHAR|TO_TIMESTAMP|BTRIM|REGEXP_REPLACE)([^[:alnum:]_]|$)|AT[[:space:]]+TIME[[:space:]]+ZONE|::(int|integer|text|numeric|bigint)([^[:alnum:]_]|$)'

if command -v rg >/dev/null 2>&1; then
  production_matches="$(rg -n -i "$production_pattern|$native_type_pattern|$component_sql_pattern|$postgresql_sql_pattern" lib || true)"
  placeholder_matches="$(rg -n '[$][0-9]+' lib | rg -v ':"[$][0-9]+"|Currency \([$][0-9,]+|"[$][0-9]+",' || true)"
  dependency_matches="$(rg -n -i "$dependency_pattern" mix.exs | rg -v 'check_postgresql_boundary' || true)"
else
  production_matches="$(grep -RniE "$production_pattern|$native_type_pattern|$component_sql_pattern|$postgresql_sql_pattern" lib || true)"
  placeholder_matches="$(grep -RniE '[$][0-9]+' lib | grep -vE ':"[$][0-9]+"|Currency \([$][0-9,]+|"[$][0-9]+",' || true)"
  dependency_matches="$(grep -niE "$dependency_pattern" mix.exs | grep -v 'check_postgresql_boundary' || true)"
fi

matches="${production_matches}${placeholder_matches:+$'\n'}${placeholder_matches}${dependency_matches:+$'\n'}${dependency_matches}"

if [[ -n "$matches" ]]; then
  echo "selecto_components PostgreSQL production-boundary violation:" >&2
  echo "$matches" >&2
  exit 1
fi

echo "selecto_components PostgreSQL production boundary: clean"
