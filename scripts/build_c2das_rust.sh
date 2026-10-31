#!/usr/bin/env bash
# Build the Rust translator lookibed/c2das at the commit VERSIONS.md pins, the other side of the
# P8.1 head-to-head (compare/ARCHITECTURE.md). The checkout is $C2DAS_RUST, default /root/c2das,
# cloned when absent; the build is cargo's, incremental, so a second run rebuilds nothing.
# Prints the binary's path. `--check` verifies the checkout, the toolchain and the binary and
# builds nothing; `--allow-other` builds a checkout at another commit than the pin.
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
. "$repo_root/suites/fetch_common.sh"

usage() {
    cat <<'HELP'
usage: scripts/build_c2das_rust.sh [--check] [--allow-other]
  --check        verify the checkout, rustup, the toolchain, llvm-config and the binary; build
                 nothing; exit 1 naming each part that is missing
  --allow-other  accept a checkout at another commit than the VERSIONS.md pin
  -?, --help     show this help and exit
environment: C2DAS_RUST (the checkout, default /root/c2das), CARGO_HOME (default ~/.cargo)
HELP
}

check=0; allow_other=0
while [ $# -gt 0 ]; do
    case "$1" in
        --check) check=1 ;;
        --allow-other) allow_other=1 ;;
        -\?|--help) usage; exit 0 ;;
        *) echo "build_c2das_rust: unknown flag $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

# the first word after `name:` in VERSIONS.md
word_of() {
    sed -n "s/^$1: *\([^ ]*\).*/\1/p" "$repo_root/VERSIONS.md" | head -1
}

pin=$(pin_of "c2das (Rust translator)")
channel=$(word_of "rust toolchain")
llvm=$(word_of "LLVM for the Rust translator")
[ -n "$pin" ] && [ -n "$channel" ] && [ -n "$llvm" ] || { echo "build_c2das_rust: VERSIONS.md lacks a Rust translator pin" >&2; exit 1; }
checkout="${C2DAS_RUST:-/root/c2das}"
binary="$checkout/target/release/c2dascript-transpile"
export PATH="${CARGO_HOME:-$HOME/.cargo}/bin:$PATH"

missing=0
miss() { echo "build_c2das_rust: missing $1" >&2; missing=1; }

if [ ! -d "$checkout/.git" ]; then
    if [ $check = 1 ]; then
        miss "the checkout $checkout (run without --check to clone it)"
    else
        git clone -q https://github.com/lookibed/c2das "$checkout"
        git -C "$checkout" checkout -q "$pin"
    fi
fi
if [ -d "$checkout/.git" ]; then
    head=$(git -C "$checkout" rev-parse HEAD)
    if [ "$head" != "$pin" ] && [ $allow_other = 0 ]; then
        echo "build_c2das_rust: $checkout is at $head, not the pinned $pin (VERSIONS.md); --allow-other builds it anyway" >&2
        exit 1
    fi
fi
command -v rustup >/dev/null 2>&1 || miss "rustup (install it under ${CARGO_HOME:-$HOME/.cargo})"
if command -v rustup >/dev/null 2>&1 && ! grep -q "^$channel" <<<"$(rustup toolchain list)"; then
    miss "the rust toolchain $channel (rustup toolchain install $channel)"
fi
llvm_config=$(command -v "llvm-config-$llvm" || true)
[ -n "$llvm_config" ] || miss "llvm-config-$llvm (apt-get install llvm-$llvm-dev libclang-$llvm-dev clang-$llvm)"

if [ $check = 1 ]; then
    [ -x "$binary" ] || miss "the binary $binary (run without --check to build it)"
    [ $missing = 0 ] || exit 1
    echo "$binary"
    exit 0
fi
[ $missing = 0 ] || exit 1
(cd "$checkout" && LLVM_CONFIG_PATH="$llvm_config" cargo build --release -p c2dascript-transpile)
[ -x "$binary" ] || { echo "build_c2das_rust: cargo built no $binary" >&2; exit 1; }
echo "$binary"
