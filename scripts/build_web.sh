#!/usr/bin/env bash
# Build the browser demos (web/ARCHITECTURE.md): PureDOOM's processed variant from a c2das-ports
# checkout, compiled to wasm64 by the libc++ wasm host, into a static site.
# usage: scripts/build_web.sh --ports <c2das-ports checkout> [--host <wasm host daScript>] [--out <dir>]
#        [--pages <gh-pages checkout> [--commit]]
#   --host   the libc++ + C++-exceptions daScript build (default $WASM_HOST, else /root/daScript-wasmhost);
#            its commit must be VERSIONS.md's pin
#   --out    the build folder (default out/web); the site lands in <out>/site
#   --pages  copy the site into this checkout of the ports repository's gh-pages branch, with the
#            deploy workflow and a README naming every commit; --commit commits it there
# Needs emsdk 5.0.7 active (emcc on PATH) and clang++-18 with libc++ for the host-side crt.
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

ports="" host="${WASM_HOST:-/root/daScript-wasmhost}" out="out/web" pages="" commit=0
while [ $# -gt 0 ]; do
    case "$1" in
        --ports) ports="$2"; shift 2 ;;
        --host) host="$2"; shift 2 ;;
        --out) out="$2"; shift 2 ;;
        --pages) pages="$2"; shift 2 ;;
        --commit) commit=1; shift ;;
        *) sed -n '2,11p' "$0" >&2; exit 2 ;;
    esac
done
die() { echo "build_web: $*" >&2; exit 1; }
[ -n "$ports" ] || die "--ports <c2das-ports checkout> is required"
doom="$ports/puredoom-readable"
[ -f "$doom/processed/doom/doom_main.das" ] || die "$doom/processed/doom holds no converted PureDOOM"

# one daScript version across the pin and its tools (VERSIONS.md): the host is built at the pin's commit
pin=$(sed -n 's/^daScript commit: \([0-9a-f]\{40\}\).*/\1/p' VERSIONS.md)
have=$(git -C "$host" rev-parse HEAD 2>/dev/null) || die "$host is not a daScript checkout"
[ "$have" = "$pin" ] || die "the wasm host $host is at $have, VERSIONS.md pins $pin; rebuild it with web/build_wasm_host.sh"
ldd "$host/bin/daslang" | grep -q 'libc++\.so' || die "$host/bin/daslang does not link libc++: not a wasm host"
emver=$(emcc --version 2>/dev/null | head -1) || die "emcc is not on PATH (source emsdk_env.sh)"
case "$emver" in *" 5.0.7 "*) ;; *) die "emcc is not emscripten 5.0.7: $emver" ;; esac

out="$(mkdir -p "$out" && cd "$out" && pwd)"
stage="$out/stage/puredoom"
site="$out/site"
rm -rf "$out/stage" "$out/release" "$site"
mkdir -p "$stage/src" "$stage/modules" "$site/puredoom"

# the host-side crt this tree builds for the wasm host, and its wasm64 archive rebuilt from this tree:
# daspkg never refreshes an archive it staged before
DASLANG_ROOT="$host" CXX="${CXX:-clang++-18}" bash scripts/build_crt.sh --libcxx-host
rm -rf dasCRuntime/_wasm dasCRuntime/_wasm_build "$host/web/output64/lib/liblibDasModuleCRuntime.a"

# the project daspkg releases; copies, never links: the cross-compile writes a manifest beside
# every module it loads
cp "$doom"/processed/doom/* "$stage/src/"
cp web/puredoom/main_web.das "$stage/src/"
cp web/puredoom/.das_package web/puredoom/shell.html "$stage/"
cp -r "$doom/runtime/c_runtime" "$stage/modules/c_runtime"
mkdir -p "$stage/modules/dasCRuntime"
cp dasCRuntime/_wasmhost/.das_module dasCRuntime/_wasmhost/dasModuleCRuntime.shared_module "$stage/modules/dasCRuntime/"
sed "s|CRT_SOURCE = \"..\"|CRT_SOURCE = \"$repo_root/dasCRuntime\"|" dasCRuntime/_wasmhost/.das_package > "$stage/modules/dasCRuntime/.das_package"
grep -q "CRT_SOURCE = \"$repo_root/dasCRuntime\"" "$stage/modules/dasCRuntime/.das_package" || die "crt's .das_package names no CRT_SOURCE"

# the web host passes the host's own format and lint gates (the pin has no dasGlfw, so the
# preflight gates do not list web/)
"$host/bin/daslang" "$host/utils/das-fmt/dasfmt.das" -- --path web/puredoom/main_web.das --verify >/dev/null \
    || die "web/puredoom/main_web.das is not formatted (das-fmt of $host)"
lint=$("$host/bin/daslang" -load_module "$stage/modules/dasCRuntime" -load_module "$stage/modules/c_runtime" \
    "$host/utils/lint/main.das" -- "$stage/src/main_web.das" --quiet 2>&1) || { echo "$lint"; die "lint findings in main_web.das"; }
[ -z "$lint" ] || echo "$lint" | grep -q " 0 issue(s)" || { echo "$lint"; die "lint findings in main_web.das"; }

(cd "$host" && bin/daslang utils/daspkg/main.das -- release wasm --root "$stage" --out "$out/release")
cp "$out/release/doom/doom.html" "$out/release/doom/doom.js" "$out/release/doom/doom.wasm" "$site/puredoom/"
cp "$doom/ref/freedoom2_demo1.log" "$site/puredoom/demo1_ref.log"
cp web/site/index.html web/site/coi-serviceworker.js "$site/"

sha_of() { local s; s=$(git -C "$1" rev-parse --short=10 HEAD); [ -z "$(git -C "$1" status --porcelain)" ] || s="$s-dirty"; echo "$s"; }
c2das=$(sha_of .)
portsha=$(sha_of "$ports")
converted=$(cut -c1-10 "$doom/processed/c2das-re.commit")
printf '{"c2das_re": "%s", "ports": "%s", "converted_by": "%s", "daslang": "%s", "emscripten": "5.0.7"}\n' \
    "$c2das" "$portsha" "$converted" "${pin:0:10}" > "$site/puredoom/build.json"
echo "build_web: site in $site (c2das-re $c2das, c2das-ports $portsha, daScript ${pin:0:10})"

[ -n "$pages" ] || exit 0
[ "$(git -C "$pages" rev-parse --abbrev-ref HEAD)" = "gh-pages" ] || die "$pages is not on the gh-pages branch"
find "$pages" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
cp -r "$site"/. "$pages/"
mkdir -p "$pages/.github/workflows"
cp web/site/pages.yml "$pages/.github/workflows/pages.yml"
cat > "$pages/README.md" <<EOF
# c2das-ports in the browser

The GitHub Pages site of [c2das-ports](https://github.com/lookibed/c2das-ports): its programs compiled
to WebAssembly. Generated, never hand-edited: c2das-re's \`scripts/build_web.sh --ports <c2das-ports>
--pages <this checkout>\` writes every file here (sources: c2das-re's \`web/\`).

- PureDOOM (\`puredoom/\`): c2das-ports $portsha \`puredoom-readable/processed\` (converted by c2das-re
  $converted), with c2das-re $c2das's \`crt\` and browser host, compiled by daScript ${pin:0:10}'s libc++ wasm
  host with emscripten 5.0.7.
- No game data is in this branch: the deploy workflow downloads Freedoom 0.13.0 from its official
  release and checks its sha256 before it publishes \`puredoom/freedoom2.wad\`.
EOF
[ "$commit" = 1 ] || exit 0
git -C "$pages" add -A
git -C "$pages" commit -q -m "site: c2das-re $c2das, c2das-ports $portsha, daScript ${pin:0:10}"
echo "build_web: committed in $pages (push it to deploy)"
