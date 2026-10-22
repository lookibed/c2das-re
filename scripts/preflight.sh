#!/usr/bin/env bash
# Preflight: the gates a change clears before it is pushed, the same gates CI would run.
# `scripts/preflight.sh` runs the fast tier; `--full` adds the test lanes; `--only <gate>`
# runs one gate whatever changed; `--skip <gate>` drops one; `--list-gates` prints the table.
# Every gate prints `[PASS] name`, `[FAIL] name` or `[SKIP] name - reason`; the run exits
# nonzero on the first FAIL of the fast tier and after the lanes otherwise.
set -uo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
. scripts/env.sh
base="${PREFLIGHT_BASE:-origin/main}"
git rev-parse --verify -q "$base" >/dev/null 2>&1 || base="$(git rev-list --max-parents=0 HEAD 2>/dev/null | tail -1)"
full=0; only=(); skip=()
while [ $# -gt 0 ]; do
    case "$1" in
        --full) full=1 ;;
        --only) only+=("$2"); shift ;;
        --skip) skip+=("$2"); shift ;;
        --list-gates)
            cat <<'TABLE'
env          fast   DASLANG_ROOT is a built daScript with dastest, lint, das-fmt, the review-md walker, the watchdog and dasClangBind, at or past the VERSIONS.md pin
native       fast   scripts/build_crt.sh builds dasCRuntime (the crt module) against DASLANG_ROOT
untracked    fast   `git ls-files --others --exclude-standard` prints nothing
format       fast   das-fmt --verify over every .das folder (mirrors daScript's CI format gate)
lint         fast   lint of every .das folder, zero findings under .lint_config
compile      fast   -compile-only of every .das outside fixtures/
ast-verify   fast   -dry-run --ast-verify of every changed .das (a verify line or a crash fails)
md-ascii     fast   no em-dash, arrow or ellipsis added to a rule document (docs/ is exempt: authored elsewhere)
review-md    fast   the REVIEW.das gates of every folder the diff touches
tests        lane   every dastest suite: probes/, dasCRuntime/tests, c_runtime/tests, converter/tests, lua/tests, perf/tests, ports/tests, metrics/tests, tests/
TABLE
            exit 0 ;;
        *) echo "preflight: unknown flag $1" >&2; exit 2 ;;
    esac
    shift
done
wants() { local g="$1"; for s in "${skip[@]:-}"; do [ "$s" = "$g" ] && return 1; done; [ ${#only[@]} -eq 0 ] && return 0; for o in "${only[@]}"; do [ "$o" = "$g" ] && return 0; done; return 1; }
das_dirs=(); for d in converter c_runtime dasCRuntime lua metrics perf ports probes suites tests; do [ -d "$d" ] && das_dirs+=("$d"); done
# a suite's fetch/ and work/, lua/fetch and lua/work, perf/work and metrics/work hold inputs and converted output, never house code
das_files() { [ ${#das_dirs[@]} -gt 0 ] && find "${das_dirs[@]}" -type d \( -name fetch -o -name work \) -prune -o -type f -name '*.das' -print | sort; }
changed_das() { git diff --name-only "$base" -- '*.das' 2>/dev/null; git ls-files --others --exclude-standard -- '*.das'; }
pass() { echo "[PASS] $1"; }
fail() { echo "[FAIL] $1 - $2"; return 1; }
skipped() { echo "[SKIP] $1 - $2"; }
gate_env() { scripts/verify_daslang.sh >/dev/null && pass env || fail env "scripts/verify_daslang.sh names what is missing"; }
gate_native() { local out; out=$(scripts/build_crt.sh 2>&1) && pass native || { echo "$out" | tail -20; fail native "dasCRuntime does not build"; }; }
gate_untracked() { local u; u=$(git ls-files --others --exclude-standard); [ -z "$u" ] && pass untracked || fail untracked "$(echo "$u" | tr '\n' ' ')"; }
gate_format() {
    [ ${#das_dirs[@]} -gt 0 ] || { skipped format "no .das folders"; return 0; }
    local f
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        das "$DASLANG_ROOT/utils/das-fmt/dasfmt.das" -- --path "$f" --verify >/dev/null 2>&1 || { fail format "unformatted $f (run the formatter)"; return 1; }
    done < <(das_files)
    pass format
}
gate_lint() {
    [ ${#das_dirs[@]} -gt 0 ] || { skipped lint "no .das folders"; return 0; }
    local files; mapfile -t files < <(das_files)
    local out; out=$(das "$DASLANG_ROOT/utils/lint/main.das" -- "${files[@]}" --quiet --disable LINT019 2>&1) || { echo "$out" | tail -20; fail lint "findings above"; return 1; }
    echo "$out" | grep -q " 0 issue(s)" && pass lint || { echo "$out" | tail -20; fail lint "findings above"; }
}
gate_compile() {
    local n=0 f
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        case "$f" in */fixtures/*) continue ;; esac
        das -compile-only "$f" >/dev/null 2>&1 || { fail compile "$f does not compile"; return 1; }
        n=$((n + 1))
    done < <(das_files)
    pass "compile ($n files)"
}
gate_ast_verify() {
    local n=0 f
    while IFS= read -r f; do
        [ -n "$f" ] && [ -f "$f" ] || continue
        case "$f" in */fixtures/*) continue ;; esac
        local out; out=$(das -dry-run --ast-verify "$f" 2>&1) || true
        echo "$out" | grep -q "AST verify" && { echo "$out" | grep "AST verify" | head -5; fail ast-verify "$f"; return 1; }
        n=$((n + 1))
    done < <(changed_das | sort -u)
    pass "ast-verify ($n changed files)"
}
gate_md_ascii() {
    local bad; bad=$(git diff "$base" -- ':(glob)**/REVIEW*.md' ':(glob)**/ARCHITECTURE*.md' ':(glob)**/CLAUDE.md' ':(glob)**/AGENTS.md' 'skills/internal/*.md' 2>/dev/null | grep '^+' | grep -vP '^\+\+\+' | grep -P '[\x{2014}\x{2192}\x{2026}]' || true)
    [ -z "$bad" ] && pass md-ascii || { echo "$bad" | head -5; fail md-ascii "smart punctuation added to a rule document"; }
}
gate_review_md() {
    local out; out=$(das "$DASLANG_ROOT/utils/internal/review-md/main.das" -- --base "$base" 2>&1) || { echo "$out" | tail -20; fail review-md "a REVIEW.das gate fired"; return 1; }
    pass review-md
}
gate_tests() {
    local d rc=0
    for d in probes dasCRuntime/tests c_runtime/tests converter/tests lua/tests perf/tests ports/tests metrics/tests tests; do
        [ -d "$d" ] || continue
        das "$DASLANG_ROOT/dastest/dastest.das" -- --test "$d" --failures-only || rc=1
    done
    [ $rc = 0 ] && pass tests || fail tests "a suite is red"
}
fast=(env native untracked format lint compile ast-verify md-ascii review-md)
red=0
for g in "${fast[@]}"; do
    wants "$g" || continue
    "gate_${g//-/_}" || { red=1; break; }
done
if [ $red = 0 ] && { [ $full = 1 ] || [ ${#only[@]} -gt 0 ]; }; then
    wants tests && { gate_tests || red=1; }
fi
[ $red = 0 ] && echo "preflight: green" || { echo "preflight: red"; exit 1; }
