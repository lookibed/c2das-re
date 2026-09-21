#!/usr/bin/env bash
# Verify that DASLANG_ROOT is a built daScript checkout with everything this repository
# needs: the binary, dastest, the lint and format tools, the review-md walker, the
# watchdog front (MCP/LSP/DAP), and the cbind module (dasClangBind). Exit 0 when complete.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/env.sh"
fail=0
need() { [ -e "$1" ] || { echo "verify: missing $1 ($2)"; fail=1; }; }
need "$DASLANG" "the daslang binary; build the checkout"
need "$DASLANG_ROOT/dastest/dastest.das" "dastest"
need "$DASLANG_ROOT/utils/lint/main.das" "the lint tool"
need "$DASLANG_ROOT/utils/das-fmt/dasfmt.das" "the formatter"
need "$DASLANG_ROOT/utils/internal/review-md/main.das" "the REVIEW.das walker"
need "$DASLANG_ROOT/bin/watchdog" "the watchdog front: configure with -DDAS_STDDLG_DISABLED=OFF"
need "$DASLANG_ROOT/modules/dasClangBind/dasModuleClangBind.shared_module" "dasClangBind: configure with -DDAS_CLANG_BIND_DISABLED=OFF and PATH_TO_LIBCLANG"
[ $fail = 0 ] || exit 1
"$DASLANG" -version >/dev/null 2>&1 || { echo "verify: $DASLANG does not run"; exit 1; }
pin=$(sed -n 's/^daScript commit: *\([0-9a-f]*\).*/\1/p' "$(dirname "${BASH_SOURCE[0]}")/../VERSIONS.md" | head -1)
head=$(git -C "$DASLANG_ROOT" rev-parse HEAD 2>/dev/null || echo unknown)
if [ -n "$pin" ] && [ "$head" != "$pin" ] && ! git -C "$DASLANG_ROOT" merge-base --is-ancestor "$pin" HEAD 2>/dev/null; then
    echo "verify: DASLANG_ROOT is at $head, which does not contain the pinned $pin (VERSIONS.md); DASLANG_ALLOW_UNPINNED=1 overrides for local experiments"
    [ "${DASLANG_ALLOW_UNPINNED:-0}" = 1 ] || exit 1
fi
echo "verify: daslang $("$DASLANG" -version 2>&1 | head -1) at $DASLANG_ROOT ($head)"
