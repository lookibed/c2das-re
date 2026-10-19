# Sourced by the suites' fetch scripts after they set `repo_root`: the pin lookup and the
# checkout every fetch shares.

# the pinned commit of `name` in VERSIONS.md
pin_of() {
    local name="$1"
    sed -n "s/^$name: *\([0-9a-f]*\).*/\1/p" "$repo_root/VERSIONS.md" | head -1
}

# 0 when `dest` is a checkout at `pin` and `built` exists, so the fetch has nothing to do
at_pin() {
    local dest="$1" pin="$2" built="$3"
    [ -d "$dest/.git" ] && [ "$(git -C "$dest" rev-parse HEAD)" = "$pin" ] && [ -e "$built" ]
}

# clone `url` into `dest` at `pin` unless `dest` is already at the pin with `built` present;
# 0 when it cloned (a build is due), 1 when the checkout was current
checkout_if_stale() {
    local url="$1" dest="$2" pin="$3" built="$4"
    if at_pin "$dest" "$pin" "$built"; then
        return 1
    fi
    rm -rf "${dest:?}"
    git clone -q "$url" "$dest"
    git -C "$dest" checkout -q "$pin"
}
