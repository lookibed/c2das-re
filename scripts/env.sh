#!/usr/bin/env bash
# The daslang toolchain this repository binds to. Source it: `. scripts/env.sh`.
# The daScript checkout at DASLANG_ROOT is built in place with dasClangBind, dasStdDlg
# (the watchdog needs it), dasHV and dasLLVM enabled; VERSIONS.md pins its commit.
export DASLANG_ROOT="${DASLANG_ROOT:-/root/daScript}"
export DASLANG="${DASLANG:-$DASLANG_ROOT/bin/daslang}"
export DAS_LINT_CONFIG_PATH="${DAS_LINT_CONFIG_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.lint_config}"
export PATH_TO_LIBCLANG="${PATH_TO_LIBCLANG:-/root/libclang}"
export DAS_CLANG_INCLUDE="${DAS_CLANG_INCLUDE:-$PATH_TO_LIBCLANG/include}"
# daslang filters to_log(LOG_INFO) below the default `warning` floor; the tools here report through it
export DAS_LOG_LEVEL="${DAS_LOG_LEVEL:-info}"
# every daslang run sees the crt and c_runtime modules: they live here, not under DASLANG_ROOT/modules;
# and dasFlex, the frontend's lexer generator, once scripts/fetch_dasflex.sh fetched it (a missing
# folder given to -load_module stops daslang before the script, so it is passed only when present)
C2DAS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
das() {
    local flex=()
    [ -d "$C2DAS_ROOT/fetch/dasFlex" ] && flex=(-load_module "$C2DAS_ROOT/fetch/dasFlex")
    "$DASLANG" -load_module "$C2DAS_ROOT/dasCRuntime" -load_module "$C2DAS_ROOT/c_runtime" "${flex[@]}" "$@"
}
