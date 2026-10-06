#!/usr/bin/env bash
# Fetch c-testsuite at the commit VERSIONS.md pins into suites/c_testsuite/fetch/ (gitignored).
# Idempotent: an existing checkout at the pin is left alone.
set -euo pipefail
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$here/../.." && pwd)"
pin=$(sed -n 's/^c-testsuite: *\([0-9a-f]*\).*/\1/p' "$repo_root/VERSIONS.md" | head -1)
[ -n "$pin" ] || { echo "fetch: VERSIONS.md names no c-testsuite pin" >&2; exit 1; }
dest="$here/fetch/c-testsuite"
if [ -d "$dest/.git" ] && [ "$(git -C "$dest" rev-parse HEAD)" = "$pin" ]; then
    exit 0
fi
rm -rf "$dest"
mkdir -p "$here/fetch"
git clone -q https://github.com/c-testsuite/c-testsuite "$dest"
git -C "$dest" checkout -q "$pin"
echo "fetch: c-testsuite at $pin"
