#!/usr/bin/env bash
# The checks and helpers the browser builds share (scripts/build_web.sh, scripts/build_translator_site.sh;
# web/ARCHITECTURE.md section 2). Sourced from the repository root.

die() { echo "${WEB_SCRIPT:-web}: $*" >&2; exit 1; }

# a checkout's short commit, `-dirty` when it has changes
sha_of() { local s; s=$(git -C "$1" rev-parse --short=10 HEAD); [ -z "$(git -C "$1" status --porcelain)" ] || s="$s-dirty"; echo "$s"; }

# emscripten 5.0.7 on PATH
check_emcc() {
    local emver
    emver=$(emcc --version 2>/dev/null | head -1) || die "emcc is not on PATH (source emsdk_env.sh)"
    case "$emver" in *" 5.0.7 "*) ;; *) die "emcc is not emscripten 5.0.7: $emver" ;; esac
}

# the wasm host `$1` at VERSIONS.md's pin (one daScript version across the pin and its tools) and
# linking libc++; sets `pin` to the pinned commit
check_host() {
    local have
    pin=$(sed -n 's/^daScript commit: \([0-9a-f]\{40\}\).*/\1/p' VERSIONS.md)
    have=$(git -C "$1" rev-parse HEAD 2>/dev/null) || die "$1 is not a daScript checkout"
    [ "$have" = "$pin" ] || die "the wasm host $1 is at $have, VERSIONS.md pins $pin; rebuild it with web/build_wasm_host.sh"
    ldd "$1/bin/daslang" | grep -q 'libc++\.so' || die "$1/bin/daslang does not link libc++: not a wasm host"
}

# a gh-pages checkout `$1` of the repository `$2` (its origin ends in it), at its top, on the
# gh-pages branch: each build fills its own repository's site and never wipes the other's
check_pages() {
    local top origin
    top=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) || die "$1 is not a git checkout"
    [ "$top" = "$(cd "$1" && pwd)" ] || die "$1 is not the top of its checkout ($top is)"
    [ "$(git -C "$1" rev-parse --abbrev-ref HEAD)" = "gh-pages" ] || die "$1 is not on the gh-pages branch"
    origin=$(git -C "$1" remote get-url origin 2>/dev/null) || die "$1 has no origin remote"
    case "${origin%.git}" in */"$2") ;; *) die "$1 is a checkout of $origin, not of $2" ;; esac
}

# commits everything in the gh-pages checkout `$1` with the message `$2`, unless nothing changed
commit_pages() {
    git -C "$1" add -A
    if git -C "$1" diff --cached --quiet; then
        echo "${WEB_SCRIPT:-web}: $1 already holds this site"
    else
        git -C "$1" commit -q -m "$2"
        echo "${WEB_SCRIPT:-web}: committed in $1 (push it to deploy)"
    fi
}
