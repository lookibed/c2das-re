#!/usr/bin/env bash
# Fetch c-testsuite at the commit VERSIONS.md pins into suites/c_testsuite/fetch/ (gitignored).
# Idempotent: an existing checkout at the pin is left alone.
set -euo pipefail
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$here/../.." && pwd)"
. "$repo_root/suites/fetch_common.sh"
pin=$(pin_of c-testsuite)
[ -n "$pin" ] || { echo "fetch: VERSIONS.md names no c-testsuite pin" >&2; exit 1; }
mkdir -p "$here/fetch"
dest="$here/fetch/c-testsuite"
if checkout_if_stale https://github.com/c-testsuite/c-testsuite "$dest" "$pin" "$dest/.git"; then
    echo "fetch: c-testsuite at $pin"
fi
