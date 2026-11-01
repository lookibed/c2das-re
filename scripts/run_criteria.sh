#!/usr/bin/env bash
# Run metrics/criteria.das from the repository root with both modules loaded, fetching the suites
# and the Lua release first unless the help or the gate's --report is asked:
# `scripts/run_criteria.sh [--filter lua/] [--jobs 6] [--delta <capture>]`. The Lua inputs need
# up to 3 GB each; cap the run (`prlimit --as=3221225472`) on a shared box.
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
. scripts/env.sh
fetch=1
for arg in "$@"; do
    case "$arg" in -\?|--show-help|--report) fetch=0 ;; esac
done
if [ $fetch = 1 ]; then
    for suite in c_testsuite gcc_torture csmith; do
        "suites/$suite/fetch.sh"
    done
    lua/fetch.sh
fi
das metrics/criteria.das -- "$@"
