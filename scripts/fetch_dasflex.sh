#!/usr/bin/env bash
# Fetch dasFlex, the lexer generator frontend/pp_lexer.das is built on, at the commit the `dasFlex:`
# line of VERSIONS.md pins into fetch/dasFlex/ (gitignored); `das` of scripts/env.sh loads it as a
# module folder. Idempotent: a clean checkout at the pin is left alone, a clean checkout at another
# commit moves to the pin, and a checkout with local changes is refused, never overwritten.
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
. "$repo_root/suites/fetch_common.sh"
pin=$(pin_of dasFlex)
[ -n "$pin" ] || { echo "fetch: VERSIONS.md names no dasFlex pin" >&2; exit 1; }
dest="$repo_root/fetch/dasFlex"
if [ ! -d "$dest/.git" ]; then
    mkdir -p "$repo_root/fetch"
    git clone -q https://github.com/lookibed/dasFlex "$dest"
fi
if [ -n "$(git -C "$dest" status --porcelain)" ]; then
    echo "fetch: $dest has local changes; refusing it as the pin $pin" >&2
    exit 1
fi
case "$(git -C "$dest" rev-parse HEAD)" in "$pin"*) exit 0 ;; esac
git -C "$dest" cat-file -e "$pin^{commit}" 2>/dev/null || git -C "$dest" fetch -q origin
git -C "$dest" checkout -q "$pin"
case "$(git -C "$dest" rev-parse HEAD)" in "$pin"*) echo "fetch: dasFlex at $pin" ;; *) echo "fetch: $dest is not at $pin" >&2; exit 1 ;; esac
