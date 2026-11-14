#!/usr/bin/env bash
# Run perf/run.das from the repository root with both modules loaded; flags: scripts/run_perf.sh -?
# Two modes go first and run both methods (perf/ARCHITECTURE.md section 6):
#   --from-scratch  rebuild the crt, drop perf/work, rerun dasProfile (perf/dasprofile.sh), then
#                   record both captures and both docs/performance.md sections from fresh conversions
#   --check         rerun both methods into a scratch folder and compare each with its committed
#                   capture: exit 1 when a cell drifts past --tolerance (10% by default) either way
# Every other flag goes to perf/run.das, in both modes to each of its two runs.
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
. scripts/env.sh
mode=""
case "${1:-}" in
    --from-scratch|--check) mode="$1"; shift ;;
esac
if [ -z "$mode" ]; then
    das perf/run.das -- "$@"
    exit
fi
if [ "$mode" = "--from-scratch" ]; then
    bash scripts/build_crt.sh
    rm -rf "${repo_root:?}/perf/work"
    bash perf/dasprofile.sh
    rc=0
    das perf/run.das -- --readme "$@" || rc=1
    das perf/run.das -- --method dasprofile --readme "$@" || rc=1
    exit "$rc"
fi
scratch="$(mktemp -d)"
rc=0
das perf/run.das -- --check --out "$scratch/results_linux.json" "$@" || rc=1
das perf/run.das -- --check --method dasprofile --out "$scratch/results_method_linux.json" "$@" || rc=1
rm -rf "${scratch:?}"
exit "$rc"
