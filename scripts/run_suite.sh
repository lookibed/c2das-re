#!/usr/bin/env bash
# Run one suite's runner from the repository root with both modules loaded, fetching the
# suite first when needed: `scripts/run_suite.sh c_testsuite [--filter 0000] [--update]`.
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
. scripts/env.sh
suite="${1:?suite name, e.g. c_testsuite}"
shift
[ -d "suites/$suite" ] || { echo "run_suite: no suites/$suite" >&2; exit 2; }
[ -x "suites/$suite/fetch.sh" ] && "suites/$suite/fetch.sh"
das "suites/$suite/run.das" -- "$@"
