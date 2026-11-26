#!/usr/bin/env bash
# Fetch dasBison, the LALR(1) parser generator the C.1 parser probe's LR candidate is built on, and
# dasFlex, which its runtime requires, each at the commit its VERSIONS.md line pins (`dasBison:`,
# `dasFlex:`), into fetch/<name>/ (gitignored); daslang loads both as module folders. A pin can be
# given before VERSIONS.md names one: DASBISON_PIN, DASFLEX_PIN. Idempotent: a clean checkout at the
# pin is left alone, a clean checkout at another commit moves to the pin, and a checkout with local
# changes is refused, never overwritten.
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
. "$repo_root/suites/fetch_common.sh"

# fetch_pinned <name> <url> <pin>
fetch_pinned() {
    local name="$1" url="$2" pin="$3"
    [ -n "$pin" ] || { echo "fetch: VERSIONS.md names no $name pin" >&2; exit 1; }
    local dest="$repo_root/fetch/$name"
    if [ ! -d "$dest/.git" ]; then
        mkdir -p "$repo_root/fetch"
        git clone -q "$url" "$dest"
    fi
    if [ -n "$(git -C "$dest" status --porcelain)" ]; then
        echo "fetch: $dest has local changes; refusing it as the pin $pin" >&2
        exit 1
    fi
    case "$(git -C "$dest" rev-parse HEAD)" in "$pin"*) return 0 ;; esac
    git -C "$dest" cat-file -e "$pin^{commit}" 2>/dev/null || git -C "$dest" fetch -q origin
    git -C "$dest" checkout -q "$pin"
    case "$(git -C "$dest" rev-parse HEAD)" in
        "$pin"*) echo "fetch: $name at $pin" ;;
        *) echo "fetch: $dest is not at $pin" >&2; exit 1 ;;
    esac
}

fetch_pinned dasFlex https://github.com/lookibed/dasFlex "${DASFLEX_PIN:-$(pin_of dasFlex)}"
fetch_pinned dasBison https://github.com/lookibed/dasBison "${DASBISON_PIN:-$(pin_of dasBison)}"
