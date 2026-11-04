#!/usr/bin/env bash
# Fetch doom2.wad, id Software's commercial IWAD, from a source the owner gives, into
# doom/fetch/wads/doom2.wad (gitignored), and check it against the `doom2:` line of VERSIONS.md: the
# size and the sha256 the line pins. The source is the first argument or $DOOM2_WAD_SOURCE: a local
# path (copied) or an http(s) URL (downloaded with curl); never a mirror the owner did not name,
# and without a source the script stops with a message. A wad already there with the pinned hash
# is left as it is. While the line pins no sha256 yet, the script prints the file's hash and the
# line to pin, removes the unverified copy and exits 1. The repository holds the script and the
# pin, never the wad. For tests: $VERSIONS_MD names the pin file, $DOOM2_WAD_DIR the folder.
set -euo pipefail
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$here/.." && pwd)"
versions="${VERSIONS_MD:-$repo_root/VERSIONS.md}"
dest_dir="${DOOM2_WAD_DIR:-$here/fetch/wads}"
source_arg="${1:-${DOOM2_WAD_SOURCE:-}}"

line=$(grep -m1 '^doom2: ' "$versions" || true)
[ -n "$line" ] || { echo "fetch_doom2: $versions has no \`doom2:\` line" >&2; exit 1; }
want_size=$(printf '%s\n' "$line" | sed -n 's/.*(\([0-9]\{1,\}\) bytes.*/\1/p')
want_hash=$(printf '%s\n' "$line" | sed -n 's/.*`doom2\.wad` (sha256 \([0-9a-f]\{64\}\)).*/\1/p')
[ -n "$want_size" ] || { echo "fetch_doom2: the doom2 line of $versions names no \`(<n> bytes\` size" >&2; exit 1; }

wad="$dest_dir/doom2.wad"
if [ -f "$wad" ] && [ -n "$want_hash" ] && [ "$(sha256sum "$wad" | cut -d' ' -f1)" = "$want_hash" ]; then
    echo "fetch_doom2: $wad is at the pin"
    exit 0
fi
[ -n "$source_arg" ] || {
    echo "fetch_doom2: no source: pass the owner's doom2.wad as the first argument or \$DOOM2_WAD_SOURCE (a local path or an http(s) URL); the script fetches from no mirror of its own" >&2
    exit 2
}

mkdir -p "$dest_dir"
part="$dest_dir/doom2.wad.part"
case "$source_arg" in
    http://*|https://*) curl -fsSL --retry 3 -o "$part" "$source_arg" ;;
    *) [ -f "$source_arg" ] || { echo "fetch_doom2: no file at $source_arg" >&2; exit 2; }
       cp -- "$source_arg" "$part" ;;
esac

have_size=$(stat -c %s "$part")
have_hash=$(sha256sum "$part" | cut -d' ' -f1)
if [ "$have_size" != "$want_size" ]; then
    echo "fetch_doom2: $source_arg has $have_size bytes, the doom2 line pins $want_size: not the pinned release" >&2
    rm -f -- "${dest_dir:?}/doom2.wad.part"
    exit 1
fi
if [ -z "$want_hash" ]; then
    echo "fetch_doom2: the doom2 line pins no sha256 yet; the file's is $have_hash. Pin it by adding \`doom2.wad\` (sha256 $have_hash) to that line, then run again" >&2
    rm -f -- "${dest_dir:?}/doom2.wad.part"
    exit 1
fi
if [ "$have_hash" != "$want_hash" ]; then
    echo "fetch_doom2: $source_arg has sha256 $have_hash, the doom2 line pins $want_hash" >&2
    rm -f -- "${dest_dir:?}/doom2.wad.part"
    exit 1
fi
mv -f -- "$part" "$wad"
echo "fetch_doom2: $wad ($have_size bytes, sha256 $have_hash)"
