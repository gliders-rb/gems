#!/usr/bin/env bash
# Runs every gem's benchmarks/perf.rb with YJIT off then on, profiles the slowest workloads with StackProf,
# and writes results/*.json, results/profiles/*, results/tables.md.
#
#   benchmarks/perf/run_all.sh                 full run (about 25 minutes)
#   PERF_TIME=1 PERF_WARMUP=0.5 PERF_PROFILE_SECONDS=2 benchmarks/perf/run_all.sh    quick smoke run
#   SKIP_IPS=1 / SKIP_PROFILE=1                skip a phase (profiles reuse results from an earlier ips run)
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
export PERF_OUT="${PERF_OUT:-$root/benchmarks/perf/results}"
gems="gems/field_struct gems/actionable adapters/field_struct-json_schema adapters/field_struct-avro adapters/field_struct-protobuf adapters/actionable-otel adapters/actionable-tools"

if [ -z "${SKIP_IPS:-}" ]; then
  rm -f "$PERF_OUT"/*.json
  mkdir -p "$PERF_OUT"
  for flag in --disable-yjit --yjit; do
    for g in $gems; do
      echo "=== $g $flag"
      (cd "$root/$g" && bundle exec ruby "$flag" benchmarks/perf.rb)
    done
  done
fi

if [ -z "${SKIP_PROFILE:-}" ]; then
  rm -rf "$PERF_OUT/profiles"
  # pick_top.rb prints "<gem dir>\t<workload name>" for the 5 slowest per-op workloads overall plus the
  # slowest of each gem not already covered.
  while IFS=$'\t' read -r dir name; do
    echo "=== profile $dir: $name"
    # shellcheck disable=SC2001
    only="^$(printf '%s' "$name" | sed 's/[][\.*^$()+?{}|/]/\\&/g')\$"
    (cd "$root/$dir" && PERF_ONLY="$only" PERF_PROFILE=cpu,wall PERF_NO_CHILD=1 bundle exec ruby --yjit benchmarks/perf.rb)
  done < <(ruby "$root/benchmarks/perf/pick_top.rb")
fi

ruby "$root/benchmarks/perf/report.rb" > "$PERF_OUT/tables.md"
echo "wrote $PERF_OUT/tables.md"
