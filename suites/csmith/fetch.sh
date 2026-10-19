#!/usr/bin/env bash
# Fetch csmith at the commit VERSIONS.md pins into suites/csmith/fetch/csmith (gitignored) and
# build it there with cmake: the runner needs `build/src/csmith` and the `runtime/` headers, the
# generated `build/runtime/safe_math.h` among them. With `--cvise`, also fetch and build the cvise
# reducer `reduce.sh` drives, against PATH_TO_LIBCLANG, its Python packages in a venv beside it.
# Idempotent: a checkout at its pin with its build present is left alone.
set -euo pipefail
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$here/../.." && pwd)"
. "$repo_root/suites/fetch_common.sh"
fetch="$here/fetch"
mkdir -p "$fetch"

# a cmake build whose output lands in `log`, shown only when it fails
build() {
    local src="$1" log="$2"
    shift 2
    if ! { cmake -S "$src" -B "$src/build" -DCMAKE_BUILD_TYPE=Release "$@" && cmake --build "$src/build" -j "$(nproc)"; } >"$log" 2>&1; then
        tail -30 "$log" >&2
        echo "fetch: the build of $src failed; the log is $log" >&2
        exit 1
    fi
}

csmith_pin=$(pin_of csmith)
[ -n "$csmith_pin" ] || { echo "fetch: VERSIONS.md names no csmith pin" >&2; exit 1; }
csmith="$fetch/csmith"
if checkout_if_stale https://github.com/csmith-project/csmith "$csmith" "$csmith_pin" "$csmith/build/src/csmith"; then
    build "$csmith" "$fetch/csmith-build.log"
    echo "fetch: csmith at $csmith_pin"
fi

[ "${1:-}" = "--cvise" ] || exit 0
cvise_pin=$(pin_of cvise)
[ -n "$cvise_pin" ] || { echo "fetch: VERSIONS.md names no cvise pin" >&2; exit 1; }
: "${PATH_TO_LIBCLANG:?scripts/env.sh sets PATH_TO_LIBCLANG, the LLVM tree cvise builds against}"
cvise="$fetch/cvise"
venv="$fetch/cvise-venv"
# the Python packages cvise imports, at the versions its build was checked with; the venv
# records the set it installed, so a failed install or an edited list installs again
packages=("Pebble==5.2.3" "chardet==7.7.0" "msgspec==0.22.0" "psutil==7.2.2" "zstandard==0.25.0")
marker="$venv/c2das-packages.txt"
if [ ! -x "$venv/bin/python" ] || [ "$(cat "$marker" 2>/dev/null)" != "${packages[*]}" ]; then
    python3 -m venv "$venv"
    "$venv/bin/pip" install -q "${packages[@]}"
    printf '%s' "${packages[*]}" > "$marker"
fi
if checkout_if_stale https://github.com/marxin/cvise "$cvise" "$cvise_pin" "$cvise/build/clang_delta/clang_delta"; then
    build "$cvise" "$fetch/cvise-build.log" -DCMAKE_PREFIX_PATH="$PATH_TO_LIBCLANG" -DPython3_EXECUTABLE="$venv/bin/python"
    echo "fetch: cvise at $cvise_pin"
fi
