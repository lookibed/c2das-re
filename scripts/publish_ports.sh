#!/usr/bin/env bash
# Regenerate the ports repository (lookibed/c2das-ports) from this checkout: ports/publish.das
# with the crt and c_runtime modules loaded, run from the repository root.
# usage: scripts/publish_ports.sh [--repo <clone>] [--program lua] [--no-convert] [--perf]
#        [--samples N] [--lanes interp,jit,exe,aot] [--timeout S] [--allow-dirty] [--commit [--push]]
# The clone defaults to $C2DAS_PORTS, else ../c2das-ports beside this repository; -? prints the help.
set -uo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
. scripts/env.sh
das ports/publish.das -- "$@"
