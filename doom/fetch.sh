#!/usr/bin/env bash
# Fetch PureDOOM at the commit the `puredoom:` line of VERSIONS.md pins into doom/fetch/PureDOOM/
# and apply doom/patches/*.patch to it, and the freedoom release the `freedoom:` line pins into
# doom/fetch/wads/, its freedoom2.wad extracted; both folders are gitignored. The zip and the wad
# are checked against the line's sha256 hashes. Idempotent: a checkout at the pin with the patches
# applied and a wad of the right hash are left as they are; a mismatch stops it. doom2.wad is
# never fetched (doom/ARCHITECTURE.md section 1).
set -euo pipefail
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$here/.." && pwd)"
source "$repo_root/suites/fetch_common.sh"

pin=$(pin_of puredoom)
[ -n "$pin" ] || { echo "fetch: VERSIONS.md names no puredoom pin" >&2; exit 1; }
line=$(grep -m1 '^freedoom: ' "$repo_root/VERSIONS.md" || true)
zip_url=$(printf '%s\n' "$line" | grep -o 'https://[^ ]*\.zip' | head -1 || true)
zip_hash=$(printf '%s\n' "$line" | sed -n 's/.*\.zip (sha256 \([0-9a-f]\{64\}\)).*/\1/p')
wad_hash=$(printf '%s\n' "$line" | sed -n 's/.*freedoom2\.wad` (sha256 \([0-9a-f]\{64\}\)).*/\1/p')
[ -n "$zip_url" ] && [ -n "$zip_hash" ] && [ -n "$wad_hash" ] || {
    echo "fetch: the freedoom line of VERSIONS.md names \`<url>.zip (sha256 <hash>)\` and \`freedoom2.wad\` (sha256 <hash>)" >&2
    exit 1
}

tree="$here/fetch/PureDOOM"
mkdir -p "$here/fetch/wads"
if [ ! -d "$tree/.git" ] || [ "$(git -C "$tree" rev-parse HEAD)" != "$pin" ]; then
    rm -rf "${tree:?}"
    git clone -q https://github.com/Daivuk/PureDOOM "$tree"
    git -C "$tree" checkout -q "$pin"
    echo "fetch: PureDOOM $pin"
fi
for patch in "$here"/patches/*.patch; do
    if git -C "$tree" apply --reverse --check "$patch" 2>/dev/null; then
        continue
    fi
    git -C "$tree" apply "$patch" || { echo "fetch: $patch does not apply to $tree" >&2; exit 1; }
    echo "fetch: applied $(basename "$patch")"
done

check_hash() {
    local file="$1" want="$2" have
    have=$(sha256sum "$file" | cut -d' ' -f1)
    [ "$have" = "$want" ] || { echo "fetch: $file has sha256 $have, VERSIONS.md pins $want" >&2; exit 1; }
}
wad="$here/fetch/wads/freedoom2.wad"
if [ ! -f "$wad" ]; then
    zip="$here/fetch/wads/$(basename "$zip_url")"
    if [ ! -f "$zip" ]; then
        curl -fsSL -o "$zip.part" "$zip_url"
        mv "$zip.part" "$zip"
    fi
    check_hash "$zip" "$zip_hash"
    unzip -o -j -q "$zip" '*/freedoom2.wad' -d "$here/fetch/wads"
    echo "fetch: freedoom2.wad"
fi
check_hash "$wad" "$wad_hash"
