#!/usr/bin/env bash
# Build the translator page (web/ARCHITECTURE.md section 8): c2das-re's C-IR-to-das path and
# c2das-ports' Lua, compiled to wasm64 by the libc++ wasm host, with the examples converted by the
# native pipeline, into a static site for c2das-re's own GitHub Pages.
# usage: scripts/build_translator_site.sh --ports <c2das-ports checkout> --interp <dir>
#            [--host <wasm host daScript>] [--out <dir>] [--pages <gh-pages checkout> [--commit]]
#   --interp the Run button's interpreter: the out/ folder of web/translator/interp/build_interp.sh
#            (daslang_static.js, .wasm and interp.json), built at VERSIONS.md's pin
#   --host   the libc++ + C++-exceptions daScript build (default $WASM_HOST, else /root/daScript-wasmhost);
#            its commit must be VERSIONS.md's pin
#   --out    the build folder (default out/translator); the site lands in <out>/site
#   --pages  replace the top of this checkout of c2das-re's gh-pages branch with the site, the deploy
#            workflow and a README naming every commit; --commit commits it there (never a site
#            built from a tree with changes)
# Needs emsdk 5.0.7 active (emcc on PATH), clang++-18 with libc++ for the host-side crt, and this
# tree's crt built for DASLANG_ROOT (scripts/build_crt.sh) for the examples' conversion.
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
WEB_SCRIPT=build_translator_site
. scripts/web_common.sh

ports="" interp="" host="${WASM_HOST:-/root/daScript-wasmhost}" out="out/translator" pages="" commit=0
while [ $# -gt 0 ]; do
    case "$1" in
        --ports) ports="$2"; shift 2 ;;
        --interp) interp="$2"; shift 2 ;;
        --host) host="$2"; shift 2 ;;
        --out) out="$2"; shift 2 ;;
        --pages) pages="$2"; shift 2 ;;
        --commit) commit=1; shift ;;
        *) sed -n '2,16p' "$0" >&2; exit 2 ;;
    esac
done

# every refusal comes before the first write (the lint below needs the staged modules, and the
# release's own failures come after it)
[ "$commit" = 0 ] || [ -n "$pages" ] || die "--commit commits into --pages <gh-pages checkout>; there is none"
[ -z "$pages" ] || check_pages "$pages" c2das-re
[ -n "$ports" ] || die "--ports <c2das-ports checkout> is required (the Lua console's conversion)"
lua="$ports/lua/readable/lua"
[ -f "$lua/lua.das" ] || die "$lua holds no converted Lua"
[ -n "$interp" ] || die "--interp <dir> is required (web/translator/interp/build_interp.sh's out/ folder)"
for f in daslang_static.js daslang_static.wasm interp.json; do [ -f "$interp/$f" ] || die "no $f in $interp"; done
# the interpreter at the pin, its crt this tree's: c_runtime.json is bundled from this tree, so a crt
# binding added since the interpreter's build would break every Run at its require
read_pin
interp_pin=$(sed -n 's/.*"daslang": "\([0-9a-f]*\)".*/\1/p' "$interp/interp.json")
[ "$interp_pin" = "${pin:0:10}" ] || die "the interpreter in $interp is daScript ${interp_pin:-?}, VERSIONS.md pins ${pin:0:10}; rebuild it"
interp_crt=$(sed -n 's/.*"crt": "\([0-9a-f]*\)".*/\1/p' "$interp/interp.json")
[ -n "$interp_crt" ] && git cat-file -e "$interp_crt^{commit}" 2>/dev/null \
    || die "the interpreter in $interp names no crt commit of this repository (${interp_crt:-none}); rebuild it"
git diff --quiet "$interp_crt" -- dasCRuntime/src \
    || die "dasCRuntime/src changed since the interpreter's crt ($interp_crt); rebuild it with web/translator/interp/build_interp.sh"
check_emcc
check_host "$host"
cm="$host/site/files/cm"
CM_FILES="codemirror.min.js codemirror.min.css simple-mode.js daslang-keywords.js daslang-mode.js cm-forge.css LICENSE"
for f in $CM_FILES; do [ -f "$cm/$f" ] || die "no $f in the CodeMirror bundle at $cm"; done
for f in liblibDaScript.a liblibUriParser.a; do
    [ -f "$host/web/output64/lib/$f" ] || die "no $f in $host/web/output64/lib: the translator links the whole compiler"
done
# the hosts pass the wasm host's format gate
for f in web/translator/main_web.das web/translator/lua_web.das web/translator/precompute.das web/translator/bundle.das; do
    "$host/bin/daslang" "$host/utils/das-fmt/dasfmt.das" -- --path "$f" --verify >/dev/null \
        || die "$f is not formatted (das-fmt of $host)"
done
. scripts/env.sh
[ -f dasCRuntime/dasModuleCRuntime.shared_module ] || die "build this tree's crt first (scripts/build_crt.sh): the examples convert natively"
c2das=$(sha_of .)
portsha=$(sha_of "$ports")
[ "$commit" = 0 ] || case "$c2das $portsha" in *-dirty*) die "--commit: c2das-re $c2das or c2das-ports $portsha has uncommitted changes" ;; esac

out="$(mkdir -p "$out" && cd "$out" && pwd)"
site="$out/site"
rm -rf "$out/stage" "$out/release" "$out/work" "$site"
mkdir -p "$out/stage" "$out/work" "$site/cm"

# the examples, converted by this tree's native pipeline
das web/translator/precompute.das -- web/translator/examples/examples.json "$site/examples.json" "$out/work/examples" \
    || die "the examples did not convert"

# the host-side crt for the wasm host, and its wasm64 archive rebuilt from this tree
DASLANG_ROOT="$host" CXX="${CXX:-clang++-18}" bash scripts/build_crt.sh --libcxx-host
rm -rf dasCRuntime/_wasm dasCRuntime/_wasm_build "$host/web/output64/lib/liblibDasModuleCRuntime.a"
crt_module() {
    mkdir -p "$1/modules/dasCRuntime"
    cp dasCRuntime/_wasmhost/.das_module dasCRuntime/_wasmhost/dasModuleCRuntime.shared_module "$1/modules/dasCRuntime/"
    local package pointed
    package=$(cat dasCRuntime/_wasmhost/.das_package)
    pointed="${package//'CRT_SOURCE = ".."'/"CRT_SOURCE = \"$repo_root/dasCRuntime\""}"
    [ "$pointed" != "$package" ] || die "crt's .das_package names no CRT_SOURCE"
    printf '%s\n' "$pointed" > "$1/modules/dasCRuntime/.das_package"
}

# the translator: the converter's modules with the host beside them (copies: the cross-compile
# writes a manifest beside every module it loads)
tstage="$out/stage/translator"
mkdir -p "$tstage/src/converter"
# the folder's architecture documents too: the lint resolves the modules' citations against them
for f in converter/*.das converter/ARCHITECTURE*.md; do cp "$f" "$tstage/src/converter/"; done
cp web/translator/main_web.das "$tstage/src/converter/"
# the sidecar reader's define parser, where converter/sidecar.das requires it: ../frontend/
mkdir -p "$tstage/src/frontend"
cp frontend/c_defines.das "$tstage/src/frontend/"
cp web/translator/translator.das_package "$tstage/.das_package"
crt_module "$tstage"

# the Lua console: c2das-ports' Lua with its host beside it, and this tree's c_runtime module
lstage="$out/stage/lua"
mkdir -p "$lstage/src" "$lstage/modules/c_runtime"
cp "$lua"/* "$lstage/src/"
cp web/translator/lua_web.das "$lstage/src/"
cp web/translator/lua.das_package "$lstage/.das_package"
cp c_runtime/.das_module "$lstage/modules/c_runtime/"
cp -r c_runtime/c_runtime "$lstage/modules/c_runtime/c_runtime"
crt_module "$lstage"

# the translator's host passes the wasm host's lint (the Lua console's lint would compile the
# converted Lua under lint's stricter policies, which generated code does not meet)
lint=$("$host/bin/daslang" -load_module "$tstage/modules/dasCRuntime" \
    "$host/utils/lint/main.das" -- "$tstage/src/converter/main_web.das" --quiet 2>&1) \
    || { echo "$lint"; die "lint findings in the translator host"; }
[ -z "$lint" ] || echo "$lint" | grep -q " 0 issue(s)" || { echo "$lint"; die "lint findings in the translator host"; }

for app in translator lua; do
    (cd "$host" && bin/daslang utils/daspkg/main.das -- release wasm --root "$out/stage/$app" --out "$out/release")
    cp "$out/release/$app/$app.js" "$out/release/$app/$app.wasm" "$site/"
done
cp web/translator/site/* "$site/"
cp web/site/coi-serviceworker.js "$site/"
cp "$interp/daslang_static.js" "$interp/daslang_static.wasm" "$site/"
das web/translator/bundle.das -- c_runtime "$site/c_runtime.json" || die "c_runtime did not bundle"
for f in $CM_FILES; do
    cp "$cm/$f" "$site/cm/"
done
printf '{"c2das_re": "%s", "ports": "%s", "daslang": "%s", "emscripten": "5.0.7", "interp_crt": "%s"}\n' \
    "$c2das" "$portsha" "${pin:0:10}" "$interp_crt" > "$site/build.json"
echo "build_translator_site: site in $site (c2das-re $c2das, c2das-ports $portsha, daScript ${pin:0:10})"

[ -n "$pages" ] || exit 0
find "$pages" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
cp -r "$site"/. "$pages/"
mkdir -p "$pages/.github/workflows"
cp web/translator/pages.yml "$pages/.github/workflows/pages.yml"
cat > "$pages/README.md" <<EOF
# c2das-re in the browser

The GitHub Pages site of [c2das-re](https://github.com/lookibed/c2das-re): its translator's C-IR-to-daslang
half and c2das-ports' Lua, compiled to WebAssembly. Generated, never hand-edited: c2das-re's
\`scripts/build_translator_site.sh --ports <c2das-ports> --interp <dir> --pages <this checkout>\` writes every
file here (sources: c2das-re's \`web/translator/\`), from c2das-re $c2das and c2das-ports $portsha, by daScript
${pin:0:10}'s libc++ wasm host with emscripten 5.0.7. \`daslang_static.*\` is daScript ${pin:0:10}'s playground
interpreter with c2das-re $interp_crt's crt, built by \`web/translator/interp/build_interp.sh\`. \`cm/\` is
daScript's CodeMirror bundle (MIT) and daslang mode (BSD-3).
EOF
[ "$commit" = 1 ] || exit 0
commit_pages "$pages" "site: c2das-re $c2das, c2das-ports $portsha, daScript ${pin:0:10}"
