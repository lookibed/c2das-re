#!/usr/bin/env bash
# Build dasCRuntime (the `crt` module) against DASLANG_ROOT into dasCRuntime/_build; the
# .shared_module lands beside the descriptor in dasCRuntime/. Idempotent: a configured tree
# is rebuilt incrementally. `--clean` wipes the build directory first.
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
. "$repo_root/scripts/env.sh"
build_dir="$repo_root/dasCRuntime/_build"
[ "${1:-}" = "--clean" ] && rm -rf "$build_dir"
cmake -S "$repo_root/dasCRuntime" -B "$build_dir" -DDASLANG_ROOT="$DASLANG_ROOT" -DCMAKE_BUILD_TYPE=Release >/dev/null
cmake --build "$build_dir" --config Release -- -j"$(nproc 2>/dev/null || echo 4)"
