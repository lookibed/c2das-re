#!/usr/bin/env bash
# Fetch the GCC c-torture `execute` subtree at the commit VERSIONS.md pins into
# suites/gcc_torture/fetch/gcc (gitignored): a blob-less sparse clone of gcc-mirror/gcc holding
# only gcc/testsuite/gcc.c-torture/execute. Idempotent: a checkout already at the pin is left alone.
set -euo pipefail
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$here/../.." && pwd)"
. "$repo_root/suites/fetch_common.sh"
pin=$(pin_of gcc-torture)
tag=$(sed -n 's/^gcc-torture: *[0-9a-f]* *(gcc-mirror\/gcc \([^,]*\),.*/\1/p' "$repo_root/VERSIONS.md" | head -1)
[ -n "$pin" ] && [ -n "$tag" ] || { echo "fetch: VERSIONS.md names no gcc-torture pin" >&2; exit 1; }
dest="$here/fetch/gcc"
if at_pin "$dest" "$pin" "$dest/.git"; then
    exit 0
fi
rm -rf "${dest:?}"
mkdir -p "$here/fetch"
git clone -q --filter=blob:none --no-checkout --depth 1 --branch "$tag" https://github.com/gcc-mirror/gcc "$dest"
git -C "$dest" sparse-checkout set --no-cone gcc/testsuite/gcc.c-torture/execute
git -C "$dest" checkout -q
[ "$(git -C "$dest" rev-parse HEAD)" = "$pin" ] || { echo "fetch: $tag is at $(git -C "$dest" rev-parse HEAD), VERSIONS.md pins $pin" >&2; exit 1; }
echo "fetch: gcc-torture at $pin"
