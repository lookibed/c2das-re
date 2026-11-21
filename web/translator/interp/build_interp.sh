#!/usr/bin/env bash
# Build the translator page's interpreter (web/ARCHITECTURE.md section 9): daScript's playground
# interpreter daslang_static at VERSIONS.md's pin, as daScript's web build makes it, memory64 and
# threaded, with this tree's crt linked in as an in-tree module. A one-time build on a machine with
# room (owner, addendum 37: HOME-PC); the site build takes its outputs with --interp.
# usage: web/translator/interp/build_interp.sh <work dir>
#   <work dir>/emsdk (5.0.7) and <work dir>/daScript (the pin) are made when missing; the outputs land
#   in <work dir>/out: daslang_static.js, daslang_static.wasm and interp.json naming the commits.
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
die() { echo "build_interp: $*" >&2; exit 1; }
[ $# = 1 ] || { sed -n '2,8p' "$0" >&2; exit 2; }

# every refusal comes before the first write
pin=$(sed -n 's/^daScript commit: \([0-9a-f]\{40\}\).*/\1/p' "$repo_root/VERSIONS.md")
[ -n "$pin" ] || die "VERSIONS.md names no daScript commit"
work="$1"
if [ -d "$work/daScript" ]; then
    # a re-run builds in the checkout it finds, which must be the pin with nothing changed
    [ "$(git -C "$work/daScript" rev-parse HEAD 2>/dev/null)" = "$pin" ] || die "$work/daScript is not at the pin $pin"
    [ -z "$(git -C "$work/daScript" status --porcelain --untracked-files=no)" ] || die "$work/daScript has changes"
    ! git -C "$work/daScript" submodule status --recursive | grep -q '^[-+U]' || die "$work/daScript's submodules are not at their commits"
fi
[ -z "$(git -C "$repo_root" status --porcelain -- dasCRuntime web/translator/interp VERSIONS.md)" ] \
    || die "dasCRuntime/, web/translator/interp/ or VERSIONS.md has changes: interp.json names a commit"
crt=$(git -C "$repo_root" rev-parse --short=10 HEAD)

mkdir -p "$work"
work="$(cd "$work" && pwd)"
cd "$work"
[ -d emsdk ] || { rm -rf emsdk.tmp && git clone -q https://github.com/emscripten-core/emsdk.git emsdk.tmp && mv emsdk.tmp emsdk; }
(cd emsdk && ./emsdk install 5.0.7 >/dev/null && ./emsdk activate 5.0.7 >/dev/null)
if [ ! -d daScript ]; then
    # cloned aside and moved in whole: an interrupted clone leaves no daScript/ to mistake for the pin
    rm -rf daScript.tmp
    git init -q daScript.tmp
    git -C daScript.tmp remote add origin https://github.com/GaijinEntertainment/daScript.git
    git -C daScript.tmp fetch -q --depth 1 origin "$pin"
    git -C daScript.tmp checkout -q FETCH_HEAD
    git -C daScript.tmp submodule update -q --init --recursive --depth 1
    mv daScript.tmp daScript
fi
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
