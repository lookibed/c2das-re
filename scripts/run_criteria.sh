#!/usr/bin/env bash
# Run metrics/criteria.das from the repository root with both modules loaded, fetching the suites
# and the Lua release first unless the help or the gate's --report is asked:
# `scripts/run_criteria.sh [--filter lua/] [--jobs 6] [--delta <capture>]`. The Lua inputs need
# up to 3 GB each and a compare project up to 6; cap the run on a shared box with a soft and a hard
# limit (`prlimit --as=3221225472:6442450944`): a project's worker raises its soft limit to the hard.
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
