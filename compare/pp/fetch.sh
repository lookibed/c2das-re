#!/usr/bin/env bash
# Fetch the preprocessor corpora of the token oracle's full arm (compare/pp/ARCHITECTURE.md#pp6)
# into compare/pp/fetch/ (gitignored), each at the commit VERSIONS.md pins: mcpp's test-t, tcc's
# tests/pp, gcc's gcc.dg/cpp and c-c++-common/cpp (a blob-less sparse clone at the gcc-torture
# pin), the sqlite amalgamation (its hash checked) and the five macro libraries the
# compare/pp/corpus/macrolibs.txt units include. Idempotent: a checkout already at its pin is left
# alone. PP_CORPUS_VERSIONS names another file to read the pins from.
set -euo pipefail
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$here/../.." && pwd)"
. "$repo_root/suites/fetch_common.sh"
versions="${PP_CORPUS_VERSIONS:-$repo_root/VERSIONS.md}"
pin() {
    local p
    p=$(sed -n "s/^$1: *\([0-9a-f]*\).*/\1/p" "$versions" | head -1)
    [ -n "$p" ] || { echo "fetch: $versions names no $1 pin" >&2; exit 1; }
    echo "$p"
}
dest="$here/fetch"
mkdir -p "$dest"
clone_at() {
    local url="$1" to="$2" commit="$3"
    at_pin "$to" "$commit" "$to/.git" && return 0
    rm -rf "${to:?}"
    git clone -q "$url" "$to"
    git -C "$to" checkout -q "$commit"
    echo "fetch: $(basename "$to") at $commit"
}
clone_at https://github.com/museoa/mcpp.git "$dest/mcpp" "$(pin pp-mcpp)"
clone_at https://github.com/TinyCC/tinycc.git "$dest/tcc" "$(pin pp-tcc)"
clone_at https://github.com/swansontec/map-macro "$dest/macrolibs/map-macro" "$(pin pp-map-macro)"
clone_at https://github.com/boostorg/preprocessor "$dest/macrolibs/preprocessor" "$(pin pp-boost-preprocessor)"
clone_at https://github.com/pfultz2/Cloak "$dest/macrolibs/Cloak" "$(pin pp-cloak)"
clone_at https://github.com/Hirrolot/metalang99 "$dest/macrolibs/metalang99" "$(pin pp-metalang99)"
clone_at https://gitlab.inria.fr/gustedt/p99.git "$dest/macrolibs/p99" "$(pin pp-p99)"

gcc_pin=$(pin_of gcc-torture)
gcc_tag=$(sed -n 's/^gcc-torture: *[0-9a-f]* *(gcc-mirror\/gcc \([^,]*\),.*/\1/p' "$repo_root/VERSIONS.md" | head -1)
[ -n "$gcc_pin" ] && [ -n "$gcc_tag" ] || { echo "fetch: VERSIONS.md names no gcc-torture pin" >&2; exit 1; }
if ! at_pin "$dest/gcc" "$gcc_pin" "$dest/gcc/gcc/testsuite/gcc.dg/cpp"; then
    rm -rf "${dest:?}/gcc"
    git clone -q --filter=blob:none --no-checkout --depth 1 --branch "$gcc_tag" https://github.com/gcc-mirror/gcc "$dest/gcc"
    git -C "$dest/gcc" sparse-checkout set --no-cone gcc/testsuite/gcc.dg/cpp gcc/testsuite/c-c++-common/cpp
    git -C "$dest/gcc" checkout -q
    [ "$(git -C "$dest/gcc" rev-parse HEAD)" = "$gcc_pin" ] || { echo "fetch: $gcc_tag is not at $gcc_pin" >&2; exit 1; }
    echo "fetch: gcc.dg/cpp at $gcc_pin"
fi

sqlite_line=$(grep -m1 '^pp-sqlite: ' "$versions" || true)
sqlite_url=$(echo "$sqlite_line" | grep -o 'https://[^ )]*\.zip' | head -1)
sqlite_sha=$(echo "$sqlite_line" | grep -o 'sha256 [0-9a-f]*' | cut -d' ' -f2)
[ -n "$sqlite_url" ] && [ -n "$sqlite_sha" ] || { echo "fetch: $versions names no pp-sqlite url and sha256" >&2; exit 1; }
sqlite_dir="$dest/$(basename "$sqlite_url" .zip)"
if [ ! -f "$sqlite_dir/sqlite3.c" ]; then
    curl -fsSL "$sqlite_url" -o "$dest/sqlite.zip"
    echo "$sqlite_sha  $dest/sqlite.zip" | sha256sum -c --quiet
    (cd "$dest" && unzip -q -o sqlite.zip)
    rm -f -- "${dest:?}/sqlite.zip"
    echo "fetch: $(basename "$sqlite_dir")"
fi
