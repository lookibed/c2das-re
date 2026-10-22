#!/usr/bin/env bash
# Fetch Lua at the release VERSIONS.md pins, with the test suite of the same release, into
# lua/fetch/ (gitignored): each tarball is downloaded unless present, checked against its sha256
# in VERSIONS.md and extracted into lua/fetch/<name>/. Idempotent; a hash mismatch stops it.
set -euo pipefail
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$here/.." && pwd)"
line=$(grep -m1 '^lua: ' "$repo_root/VERSIONS.md" || true)
[ -n "$line" ] || { echo "fetch: VERSIONS.md names no lua pin" >&2; exit 1; }
# the `lua:` line names each tarball as `<url> (sha256 <hash>)`
pairs=$(printf '%s\n' "$line" | grep -o 'https://[^ ]*\.tar\.gz (sha256 [0-9a-f]\{64\})' || true)
[ "$(printf '%s\n' "$pairs" | grep -c .)" = 2 ] || { echo "fetch: the lua line of VERSIONS.md names two tarballs, each \`<url> (sha256 <hash>)\`" >&2; exit 1; }
mkdir -p "$here/fetch"
while read -r url _ hash; do
    hash="${hash%)}"
    tarball="$here/fetch/$(basename "$url")"
    name="$(basename "$url" .tar.gz)"
    if [ ! -f "$tarball" ]; then
        curl -fsSL -o "$tarball.part" "$url"
        mv "$tarball.part" "$tarball"
    fi
    have=$(sha256sum "$tarball" | cut -d' ' -f1)
    if [ "$have" != "$hash" ]; then
        echo "fetch: $tarball has sha256 $have, VERSIONS.md pins $hash" >&2
        exit 1
    fi
    if [ ! -d "$here/fetch/$name" ]; then
        tar -xzf "$tarball" -C "$here/fetch"
        [ -d "$here/fetch/$name" ] || { echo "fetch: $tarball holds no $name/" >&2; exit 1; }
        echo "fetch: $name"
    fi
done <<< "$pairs"
