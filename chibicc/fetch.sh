#!/usr/bin/env bash
# Fetch chibicc at the commit the `chibicc:` line of VERSIONS.md pins into chibicc/fetch/chibicc/
# (gitignored), apply chibicc/patches/*.patch to it and build the native compiler
# chibicc/fetch/chibicc/chibicc from the patched sources at -O2, the oracle of the converted one.
# Idempotent: a checkout at the pin with the patches applied is left as it is.
set -euo pipefail
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$here/.." && pwd)"
source "$repo_root/suites/fetch_common.sh"

pin=$(pin_of chibicc)
[ -n "$pin" ] || { echo "fetch: VERSIONS.md names no chibicc pin" >&2; exit 1; }
tree="$here/fetch/chibicc"
if [ ! -d "$tree/.git" ] || [ "$(git -C "$tree" rev-parse HEAD)" != "$pin" ]; then
    rm -rf "${tree:?}"
    git clone -q https://github.com/rui314/chibicc "$tree"
    git -C "$tree" checkout -q "$pin"
    echo "fetch: chibicc $pin"
fi
for patch in "$here"/patches/*.patch; do
    if git -C "$tree" apply --reverse --check "$patch" 2>/dev/null; then
        continue
    fi
    git -C "$tree" apply "$patch" || { echo "fetch: $patch does not apply to $tree" >&2; exit 1; }
    echo "fetch: applied $(basename "$patch")"
done
# the oracle is compiled as the converter reads the sources: by their full paths (`__FILE__`) and
# with plain `char` unsigned, the converter's dialect
cc -std=c11 -O2 -fno-common -funsigned-char -w -o "$tree/chibicc" "$tree"/*.c
