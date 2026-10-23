#!/usr/bin/env bash
# Run borisbat/dasProfile at the pinned commit on this machine with the pinned clang, its das lanes
# and its C++ baseline (`--das-only`), and copy its capture to perf/dasprofile_linux.json with the
# commit and the toolchain line: the hand-written column of the dasProfile-method comparison.
# Steps: the daScript SDK installed from DASLANG_ROOT's build tree (VERSIONS.md names the path),
# the headers the install leaves out copied in, dasProfile cloned into its own folder, configured
# against the SDK with the pinned clang/clang++, its C++ lane, module and AOT module built, its
# runner run from the SDK's examples/profile, where its build stages the scripts.
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
. scripts/env.sh
commit="$(sed -n 's/^dasProfile commit: \([0-9a-f]\{40\}\).*/\1/p' VERSIONS.md)"
sdk="$(sed -n 's/^daScript SDK: \(\/[^ ]*\).*/\1/p' VERSIONS.md)"
if [ -z "$commit" ] || [ -z "$sdk" ]; then
    echo "perf/dasprofile.sh: VERSIONS.md names no dasProfile commit or daScript SDK path" >&2
    exit 2
fi
work="$repo_root/perf/work/dasprofile"
mkdir -p "$work" "$sdk"
cmake --install "$DASLANG_ROOT/build" --prefix "$sdk" >"$work/sdk_install.log"
# the install omits headers the installed ones include (daScript/misc/das_asan.h): copy every
# header the SDK lacks from the source tree, none it has
cp -rn "$DASLANG_ROOT/include/daScript/." "$sdk/include/daScript/"
if [ ! -d "$work/src/.git" ]; then
    git clone --quiet https://github.com/borisbat/dasProfile "$work/src"
fi
git -C "$work/src" fetch --quiet origin
git -C "$work/src" checkout --quiet "$commit"
cmake -S "$work/src" -B "$work/build" -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DDAS_DIR="$sdk/lib/cmake/DAS" \
    -DCMAKE_C_COMPILER="$PATH_TO_LIBCLANG/bin/clang" -DCMAKE_CXX_COMPILER="$PATH_TO_LIBCLANG/bin/clang++" \
    -DDAS_SOURCE_INCLUDE_DIR="$DASLANG_ROOT/include" >"$work/configure.log"
ninja -C "$work/build" stageProfileCpp sync_profile_descriptor sync_profile_examples testProfileAot >"$work/build.log"
(cd "$sdk/examples/profile" && "$sdk/bin/daslang" main.das -- --json --das-only >"$work/run.log")
das perf/dasprofile_capture.das -- --input "$sdk/examples/profile/profile_results_linux.json" --commit "$commit" --out perf/dasprofile_linux.json
echo "perf/dasprofile.sh: perf/dasprofile_linux.json from dasProfile $commit"
