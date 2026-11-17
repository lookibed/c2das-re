#!/usr/bin/env bash
# Build the translator page's interpreter (web/ARCHITECTURE.md section 9): daScript's playground
# interpreter daslang_static at VERSIONS.md's pin, as daScript's web build makes it, memory64 and
# threaded, with this tree's crt linked in as an in-tree module. A one-time build on a machine with
# room (owner, addendum 37: HOME-PC); the site build takes its two outputs with --interp.
# usage: web/translator/interp/build_interp.sh <work dir>
#   <work dir>/emsdk (5.0.7) and <work dir>/daScript (the pin) are made when missing; the outputs land in
#   <work dir>/out: daslang_static.js, daslang_static.wasm and interp.json naming the commits.
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
[ $# = 1 ] || { sed -n '2,9p' "$0" >&2; exit 2; }
work="$(mkdir -p "$1" && cd "$1" && pwd)"
pin=$(sed -n 's/^daScript commit: \([0-9a-f]\{40\}\).*/\1/p' "$repo_root/VERSIONS.md")
crt=$(git -C "$repo_root" rev-parse --short=10 HEAD)
[ -z "$(git -C "$repo_root" status --porcelain dasCRuntime web/translator/interp)" ] || { echo "build_interp: dasCRuntime/ or web/translator/interp/ has changes" >&2; exit 1; }
cd "$work"
[ -d emsdk ] || git clone -q https://github.com/emscripten-core/emsdk.git emsdk
(cd emsdk && ./emsdk install 5.0.7 >/dev/null && ./emsdk activate 5.0.7 >/dev/null)
if [ ! -d daScript ]; then
    git init -q daScript
    git -C daScript remote add origin https://github.com/GaijinEntertainment/daScript.git
    git -C daScript fetch -q --depth 1 origin "$pin"
    git -C daScript checkout -q FETCH_HEAD
    git -C daScript submodule update -q --init --recursive --depth 1
fi
[ "$(git -C daScript rev-parse HEAD)" = "$pin" ] || { echo "build_interp: $work/daScript is not at the pin $pin" >&2; exit 1; }
rm -rf daScript/modules/dasCRuntime && mkdir -p daScript/modules/dasCRuntime
cp -r "$repo_root/dasCRuntime/src" daScript/modules/dasCRuntime/
cp "$repo_root/web/translator/interp/crt_module.cmake" daScript/modules/dasCRuntime/CMakeLists.txt
. emsdk/emsdk_env.sh >/dev/null 2>&1
# daScript's web/build_site_wasm.cmake configures web/build64 so; no host daslang: nothing cross-compiles here
emcmake cmake -S daScript/web -B daScript/web/build64 -G Ninja -DCMAKE_BUILD_TYPE=Release \
    "-DDAS_WEB_OUTPUT_DIR=$work/daScript/web/output64" -DDAS_WASM_MEMORY64=ON -DDAS_WASM_PTHREADS=ON \
    -DCMAKE_CXX_FLAGS=-sMEMORY64=1 -DCMAKE_C_FLAGS=-sMEMORY64=1 -DDAS_HOST_DASLANG_OVERRIDE=/bin/true >/dev/null
ninja -C daScript/web/build64 daslang_static
mkdir -p out
cp daScript/web/output64/daslang_static.js daScript/web/output64/daslang_static.wasm out/
printf '{"daslang": "%s", "crt": "%s", "emscripten": "5.0.7"}\n' "${pin:0:10}" "$crt" > out/interp.json
echo "build_interp: $work/out (daScript ${pin:0:10}, crt of c2das-re $crt)"
