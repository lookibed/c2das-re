#!/usr/bin/env bash
# Build dasCRuntime (the `crt` module) against DASLANG_ROOT into dasCRuntime/_build; the
# .shared_module lands beside the descriptor in dasCRuntime/. Idempotent: a configured tree
# is rebuilt incrementally. `--clean` wipes the build directory first. `--libcxx-host` builds for
# a libc++ + C++-exceptions host (daScript's web/build_wasm_host.sh, DASLANG_ROOT naming it) with
# clang++ (CXX overrides) into dasCRuntime/_build_wasmhost, the module in dasCRuntime/_wasmhost/.
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
. "$repo_root/scripts/env.sh"
build_dir="$repo_root/dasCRuntime/_build"
flavor=()
clean=0
for arg in "$@"; do
    case "$arg" in
        --clean) clean=1 ;;
        --libcxx-host)
            build_dir="$repo_root/dasCRuntime/_build_wasmhost"
            flavor=(-DDAS_CRT_LIBCXX_HOST=ON "-DCMAKE_CXX_COMPILER=${CXX:-clang++}") ;;
        *) echo "build_crt: unknown argument $arg (--clean, --libcxx-host)" >&2; exit 2 ;;
    esac
done
[ "$clean" = 1 ] && rm -rf "${build_dir:?}"
cmake -S "$repo_root/dasCRuntime" -B "$build_dir" -DDASLANG_ROOT="$DASLANG_ROOT" -DCMAKE_BUILD_TYPE=Release "${flavor[@]}" >/dev/null
# at most 8 build jobs on this machine, whatever nproc says
jobs=$(nproc 2>/dev/null || echo 4); [ "$jobs" -gt 8 ] && jobs=8
cmake --build "$build_dir" --config Release -- -j"$jobs"
