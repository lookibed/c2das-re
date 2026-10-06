#!/usr/bin/env bash
# Run the perf comparison from the repository root with both modules loaded:
# `scripts/run_perf.sh [--filter name] [--samples N] [--readme]`; `--table` renders the stored
# results. The run builds the native kernels, converts them and runs every tier.
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
. scripts/env.sh
exec "$DASLANG" -load_module "$repo_root/dasCRuntime" -load_module "$repo_root/c_runtime" perf/run.das -- "$@"
