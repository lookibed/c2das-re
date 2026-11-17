#!/usr/bin/env bash
# Build the browser demos (web/ARCHITECTURE.md): PureDOOM's processed variant from a c2das-ports
# checkout, compiled to wasm64 by the libc++ wasm host, into a static site.
# usage: scripts/build_web.sh --ports <c2das-ports checkout> [--host <wasm host daScript>] [--out <dir>]
#                             [--pages <gh-pages checkout> [--commit]]
#        scripts/build_web.sh --from <built site> --pages <gh-pages checkout> [--commit]
#   --host   the libc++ + C++-exceptions daScript build (default $WASM_HOST, else /root/daScript-wasmhost);
#            its commit must be VERSIONS.md's pin
#   --out    the build folder (default out/web); the site lands in <out>/site
#   --from   no build: fill the gh-pages checkout from a site this script built before
#   --pages  replace the top of this gh-pages checkout of the ports repository with the site, the
#            deploy workflow and a README naming every commit; --commit commits it there (never a
#            site built from a tree with changes, never a game data file)
# Needs emsdk 5.0.7 active (emcc on PATH) and clang++-18 with libc++ for the host-side crt.
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

ports="" host="${WASM_HOST:-/root/daScript-wasmhost}" out="out/web" pages="" from="" commit=0
while [ $# -gt 0 ]; do
    case "$1" in
        --ports) ports="$2"; shift 2 ;;
        --host) host="$2"; shift 2 ;;
        --out) out="$2"; shift 2 ;;
        --from) from="$2"; shift 2 ;;
        --pages) pages="$2"; shift 2 ;;
        --commit) commit=1; shift ;;
        *) sed -n '2,14p' "$0" >&2; exit 2 ;;
    esac
done
die() { echo "build_web: $*" >&2; exit 1; }
sha_of() { local s; s=$(git -C "$1" rev-parse --short=10 HEAD); [ -z "$(git -C "$1" status --porcelain)" ] || s="$s-dirty"; echo "$s"; }

# every refusal comes before the first write
[ "$commit" = 0 ] || [ -n "$pages" ] || die "--commit commits into --pages <gh-pages checkout>; there is none"
if [ -n "$pages" ]; then
    top=$(git -C "$pages" rev-parse --show-toplevel 2>/dev/null) || die "$pages is not a git checkout"
    [ "$top" = "$(cd "$pages" && pwd)" ] || die "$pages is not the top of its checkout ($top is)"
    [ "$(git -C "$pages" rev-parse --abbrev-ref HEAD)" = "gh-pages" ] || die "$pages is not on the gh-pages branch"
fi
if [ -n "$from" ]; then
    [ -n "$pages" ] || die "--from <site> fills --pages <gh-pages checkout>; there is none"
    [ -z "$ports" ] || die "--from takes a built site, --ports builds one: not both"
    [ -f "$from/puredoom/build.json" ] || die "$from holds no built site (no puredoom/build.json)"
    site="$(cd "$from" && pwd)"
else
    [ -n "$ports" ] || die "--ports <c2das-ports checkout> is required"
    doom="$ports/puredoom-readable"
    [ -f "$doom/processed/doom/doom_main.das" ] || die "$doom/processed/doom holds no converted PureDOOM"
    # the C baseline's defines: the sidecar's, as the converted code has them
    defines=$(sed -n 's/.*"defines": \[\(.*\)\],*/\1/p' doom/doom.c2das 2>/dev/null | tr -d '" ' | tr ',' ' ')
    [ -n "$defines" ] || die "doom/doom.c2das names no defines"
    dflags=()
    for d in $defines; do dflags+=("-D$d"); done

    emver=$(emcc --version 2>/dev/null | head -1) || die "emcc is not on PATH (source emsdk_env.sh)"
    case "$emver" in *" 5.0.7 "*) ;; *) die "emcc is not emscripten 5.0.7: $emver" ;; esac

    # one daScript version across the pin and its tools (VERSIONS.md): the host is built at the pin's commit
    pin=$(sed -n 's/^daScript commit: \([0-9a-f]\{40\}\).*/\1/p' VERSIONS.md)
    have=$(git -C "$host" rev-parse HEAD 2>/dev/null) || die "$host is not a daScript checkout"
    [ "$have" = "$pin" ] || die "the wasm host $host is at $have, VERSIONS.md pins $pin; rebuild it with web/build_wasm_host.sh"
    ldd "$host/bin/daslang" | grep -q 'libc++\.so' || die "$host/bin/daslang does not link libc++: not a wasm host"
    # the browser gate the C baseline's page inlines, then its sources: PureDOOM at the pin with the
    # patches (fetch.sh refuses a wrong tree), fetched into doom/fetch/, not into the site
    gate="$host/site/files/wasm-gate.js"
    [ -f "$gate" ] || die "no browser gate at $gate"
    bash doom/fetch.sh >/dev/null || die "doom/fetch.sh could not fetch PureDOOM"
    c2das=$(sha_of .)
    portsha=$(sha_of "$ports")
    [ "$commit" = 0 ] || case "$c2das $portsha" in *-dirty*) die "--commit: c2das-re $c2das or c2das-ports $portsha has uncommitted changes" ;; esac

    out="$(mkdir -p "$out" && cd "$out" && pwd)"
    stage="$out/stage/puredoom"
    site="$out/site"
    rm -rf "$out/stage" "$out/release" "$site"
    mkdir -p "$stage/src" "$stage/modules" "$site/puredoom"

    # the host-side crt this tree builds for the wasm host, and its wasm64 archive rebuilt from this
    # tree: daspkg never refreshes an archive it staged before
    DASLANG_ROOT="$host" CXX="${CXX:-clang++-18}" bash scripts/build_crt.sh --libcxx-host
    rm -rf dasCRuntime/_wasm dasCRuntime/_wasm_build "$host/web/output64/lib/liblibDasModuleCRuntime.a"

    # the project daspkg releases; copies, never links: the cross-compile writes a manifest beside
    # every module it loads
    cp "$doom"/processed/doom/* "$stage/src/"
    cp web/puredoom/main_web.das web/puredoom/tic_digest.das "$stage/src/"
    cp web/puredoom/.das_package web/puredoom/shell.html "$stage/"
    cp -r "$doom/runtime/c_runtime" "$stage/modules/c_runtime"
    mkdir -p "$stage/modules/dasCRuntime"
    cp dasCRuntime/_wasmhost/.das_module dasCRuntime/_wasmhost/dasModuleCRuntime.shared_module "$stage/modules/dasCRuntime/"
    package=$(cat dasCRuntime/_wasmhost/.das_package)
    pointed="${package//'CRT_SOURCE = ".."'/"CRT_SOURCE = \"$repo_root/dasCRuntime\""}"
    [ "$pointed" != "$package" ] || die "crt's .das_package names no CRT_SOURCE"
    printf '%s\n' "$pointed" > "$stage/modules/dasCRuntime/.das_package"

    # the web host passes the host's own format and lint gates (the pin has no dasGlfw, so the
    # preflight gates do not list web/)
    for f in web/puredoom/main_web.das web/puredoom/tic_digest.das; do
        "$host/bin/daslang" "$host/utils/das-fmt/dasfmt.das" -- --path "$f" --verify >/dev/null \
            || die "$f is not formatted (das-fmt of $host)"
    done
    lint=$("$host/bin/daslang" -load_module "$stage/modules/dasCRuntime" -load_module "$stage/modules/c_runtime" \
        "$host/utils/lint/main.das" -- "$stage/src/main_web.das" "$stage/src/tic_digest.das" --quiet 2>&1) \
        || { echo "$lint"; die "lint findings in the web host"; }
    [ -z "$lint" ] || echo "$lint" | grep -q " 0 issue(s)" || { echo "$lint"; die "lint findings in the web host"; }

    (cd "$host" && bin/daslang utils/daspkg/main.das -- release wasm --root "$stage" --out "$out/release")
    sed 's/__DOOM_BUILD__/daslang/' "$out/release/doom/doom.html" > "$site/puredoom/doom.html"
    cp "$out/release/doom/doom.js" "$out/release/doom/doom.wasm" "$site/puredoom/"

    # the C baseline (web/ARCHITECTURE.md section 6): PureDOOM's own C at the pinned commit with
    # c2das-re's patches (doom/fetch.sh), the sidecar's defines, the C twin of the host, and the link
    # flags daspkg gives the daslang build, -O3; the same shell and browser gate
    mkdir -p "$out/c"
    emcc -O3 -w "${dflags[@]}" -Idoom/fetch/PureDOOM/src/DOOM doom/fetch/PureDOOM/src/DOOM/*.c \
        web/puredoom_c/main_web.c -o "$out/c/doom_c.html" --shell-file web/puredoom/shell.html \
        -sMINIFY_HTML=0 -sMEMORY64=2 -msimd128 -sFULL_ES3 -sMAX_WEBGL_VERSION=2 -sUSE_GLFW=3 \
        -sALLOW_MEMORY_GROWTH=1 -sMAXIMUM_MEMORY=2GB -sSTACK_SIZE=4MB -fwasm-exceptions -sWASM_LEGACY_EXCEPTIONS=0 \
        -sSUPPORT_LONGJMP=wasm -sEXIT_RUNTIME=0 -sFORCE_FILESYSTEM=1 -sEXPORTED_RUNTIME_METHODS=FS,ENV,wasmMemory \
        -pthread -sPTHREAD_POOL_SIZE=16
    awk -v gate="$gate" '/<!-- @wasm-gate -->/ { print "<script>"; while ((getline l < gate) > 0) print l; print "</script>"; next } { print }' \
        "$out/c/doom_c.html" | sed 's/__DOOM_BUILD__/c/' > "$site/puredoom/doom_c.html"
    cp "$out/c/doom_c.js" "$out/c/doom_c.wasm" "$site/puredoom/"
    cp "$doom/ref/freedoom2_demo1.log" "$site/puredoom/demo1_ref.log"
    cp web/site/index.html web/site/coi-serviceworker.js "$site/"

    converted=$(cut -c1-10 "$doom/processed/c2das-re.commit")
    puredoom=$(git -C doom/fetch/PureDOOM rev-parse --short=10 HEAD)
    printf '{"c2das_re": "%s", "ports": "%s", "converted_by": "%s", "daslang": "%s", "emscripten": "5.0.7", "puredoom": "%s"}\n' \
        "$c2das" "$portsha" "$converted" "${pin:0:10}" "$puredoom" > "$site/puredoom/build.json"
    echo "build_web: site in $site (c2das-re $c2das, c2das-ports $portsha, daScript ${pin:0:10})"
fi

[ -n "$pages" ] || exit 0
# the commits the site names, read back from it, so a --from site is described as it was built
field() { sed -n "s/.*\"$1\": \"\([^\"]*\)\".*/\1/p" "$site/puredoom/build.json"; }
c2das=$(field c2das_re) portsha=$(field ports) converted=$(field converted_by) daslang=$(field daslang) puredoom=$(field puredoom)
[ "$commit" = 0 ] || case "$c2das $portsha" in *-dirty*) die "--commit: the site names a tree with changes (c2das-re $c2das, c2das-ports $portsha)" ;; esac
data=$(find "$site" \( -iname '*.wad' -o -iname '*.zip' -o -iname '*.pak' \) -print)
[ -z "$data" ] || die "the site holds game data, which no branch ever carries: $data"

find "$pages" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
cp -r "$site"/. "$pages/"
mkdir -p "$pages/.github/workflows"
cp web/site/pages.yml "$pages/.github/workflows/pages.yml"
baseline=""
if [ -n "$puredoom" ] && [ -f "$site/puredoom/doom_c.html" ]; then
    baseline="- Its C baseline (\`puredoom/doom_c.html\`): PureDOOM $puredoom's own C with c2das-re $c2das's patches and
  the C twin of the browser host, by emscripten 5.0.7 at -O3 with the daslang build's wasm flags.
"
fi
cat > "$pages/README.md" <<EOF
# c2das-ports in the browser

The GitHub Pages site of [c2das-ports](https://github.com/lookibed/c2das-ports): its programs compiled
to WebAssembly. Generated, never hand-edited: c2das-re's \`scripts/build_web.sh --ports <c2das-ports>
--pages <this checkout>\` writes every file here (sources: c2das-re's \`web/\`).

- PureDOOM (\`puredoom/\`): c2das-ports $portsha \`puredoom-readable/processed\` (converted by c2das-re
  $converted), with c2das-re $c2das's \`crt\` and browser host, compiled by daScript $daslang's libc++ wasm
  host with emscripten 5.0.7.
$baseline- No game data is in this branch: the deploy workflow downloads Freedoom 0.13.0 from its official
  release and checks its sha256 before it publishes \`puredoom/freedoom2.wad\` into the Pages artifact.
EOF
[ "$commit" = 1 ] || exit 0
data=$(find "$pages" -path "$pages/.git" -prune -o \( -iname '*.wad' -o -iname '*.zip' -o -iname '*.pak' \) -print)
[ -z "$data" ] || die "game data in $pages, not committed: $data"
git -C "$pages" add -A
if git -C "$pages" diff --cached --quiet; then
    echo "build_web: $pages already holds this site"
else
    git -C "$pages" commit -q -m "site: c2das-re $c2das, c2das-ports $portsha, daScript $daslang"
    echo "build_web: committed in $pages (push it to deploy)"
fi
