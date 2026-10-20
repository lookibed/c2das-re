#!/usr/bin/env bash
# Run metrics/readability.das from the repository root with both modules loaded, fetching the
# suites first unless the help is asked: `scripts/run_readability.sh [--filter perf/] [--update] [--jobs 6]`.
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
. scripts/env.sh
help=0
for arg in "$@"; do
    case "$arg" in -\?|--show-help) help=1 ;; esac
done
if [ $help = 0 ]; then
    for suite in c_testsuite gcc_torture csmith; do
        "suites/$suite/fetch.sh"
    done
fi
das metrics/readability.das -- "$@"
