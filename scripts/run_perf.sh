#!/usr/bin/env bash
# Run perf/run.das from the repository root with both modules loaded; flags: scripts/run_perf.sh -?
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
. scripts/env.sh
das perf/run.das -- "$@"
