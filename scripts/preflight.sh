#!/usr/bin/env bash
# Preflight: the gates a change clears before it is pushed, the same gates CI would run.
# `scripts/preflight.sh` runs the fast tier; `--full` adds the test lanes; `--only <gate>`
# runs one gate whatever changed; `--skip <gate>` drops one; `--list-gates` prints the table;
# `--jobs N` runs up to N test suites at once (1: one after another).
# Every gate prints `[PASS] name`, `[FAIL] name` or `[SKIP] name - reason`; the run exits
# nonzero on the first FAIL of the fast tier and after the lanes otherwise.
set -uo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
. scripts/env.sh
base="${PREFLIGHT_BASE:-origin/main}"
git rev-parse --verify -q "$base" >/dev/null 2>&1 || base="$(git rev-list --max-parents=0 HEAD 2>/dev/null | tail -1)"
full=0; jobs=4; only=(); skip=()
while [ $# -gt 0 ]; do
    case "$1" in
        --full) full=1 ;;
        --only) only+=("$2"); shift ;;
        --skip) skip+=("$2"); shift ;;
        --jobs)
            case "${2:-}" in ""|*[!0-9]*|0*) echo "preflight: --jobs takes a positive count" >&2; exit 2 ;; esac
            jobs="$2"; shift ;;
        --list-gates)
            cat <<'TABLE'
env          fast   DASLANG_ROOT is a built daScript with dastest, lint, das-fmt, the review-md walker, the watchdog and dasClangBind, at or past the VERSIONS.md pin; PATH_TO_LIBCLANG's clang is the pinned version; dasFlex a checkout of its own at its pin; under the tests lane, Lua fetched at its pin
native       fast   scripts/build_crt.sh builds dasCRuntime (the crt module) against DASLANG_ROOT
untracked    fast   `git ls-files --others --exclude-standard` prints nothing
format       fast   das-fmt --verify over every .das folder (mirrors daScript's CI format gate)
lint         fast   lint of every .das folder, zero findings under .lint_config
compile      fast   -compile-only of every .das outside fixtures/
ast-verify   fast   -dry-run --ast-verify of every changed .das (a verify line or a crash fails)
md-ascii     fast   no em-dash, arrow or ellipsis added to a rule document (docs/ is exempt: authored elsewhere)
review-md    fast   the REVIEW.das gates of every folder the diff touches
pp-oracle    fast   the token oracle's fast set, `compare/pp/run.das -- --pp6 --fast` (the fixtures, the own headers, c-testsuite, fetched by its fetch.sh): no unit differs from clang -E, every clang/gcc disagreement is listed in compare/pp/implementation_defined.txt
criteria     fast   a report: the readability criteria of metrics/criteria_linux.json, the delta against the base's and the sample's freshness; red only when the capture is missing or unreadable
pp-oracle-full lane the token oracle's full set, `--pp6 --full` (the fast set, gcc-torture, Lua, PureDOOM, chibicc, the Rust checkout's projects, every list of compare/pp/corpus/), each corpus fetched by its fetch.sh first; budget 1800 s
tests        lane   every dastest suite, --jobs N at once (default 4): probes/, dasCRuntime/tests, c_runtime/tests, frontend/tests, frontend/include/tests, converter/tests, lua/tests, chibicc/tests, perf/tests, ports/tests, metrics/tests, compare/tests, doom/tests, tests/
TABLE
            exit 0 ;;
        *) echo "preflight: unknown flag $1" >&2; exit 2 ;;
    esac
    shift
done
wants() { local g="$1"; for s in "${skip[@]:-}"; do [ "$s" = "$g" ] && return 1; done; [ ${#only[@]} -eq 0 ] && return 0; for o in "${only[@]}"; do [ "$o" = "$g" ] && return 0; done; return 1; }
# PREFLIGHT_DAS_DIRS replaces the folder list (a space between folders), for a test of the gates
das_dirs=(); for d in ${PREFLIGHT_DAS_DIRS-chibicc converter c_runtime compare dasCRuntime doom frontend lua metrics perf ports probes suites tests}; do [ -d "$d" ] && das_dirs+=("$d"); done
# a suite's fetch/ and work/, lua/fetch and lua/work, perf/work and metrics/work hold inputs and converted output, never house code
das_files() { [ ${#das_dirs[@]} -gt 0 ] && find "${das_dirs[@]}" -type d \( -name fetch -o -name work \) -prune -o -type f -name '*.das' -print | sort; }
changed_das() { git diff --name-only "$base" -- '*.das' 2>/dev/null; git ls-files --others --exclude-standard -- '*.das'; }
pass() { echo "[PASS] $1"; }
fail() { echo "[FAIL] $1 - $2"; return 1; }
skipped() { echo "[SKIP] $1 - $2"; }
# the tests lane's inputs are checked here, before any gate runs: a missing fetch found by the last
# suite of a --full run costs the whole run
gate_env() {
    scripts/verify_daslang.sh >/dev/null || { fail env "scripts/verify_daslang.sh names what is missing"; return 1; }
    local want got
    want=$(grep -m1 '^libclang: ' VERSIONS.md | grep -o 'LLVM [0-9][0-9.]*' | cut -d' ' -f2)
    got=$("${PATH_TO_LIBCLANG:-}/bin/clang" --version 2>/dev/null | grep -o 'clang version [0-9][0-9.]*' | cut -d' ' -f3)
    [ -n "$want" ] && [ "$got" = "$want" ] || { fail env "PATH_TO_LIBCLANG=${PATH_TO_LIBCLANG:-} gives clang '${got:-none}', VERSIONS.md pins $want: every clang oracle reads its dump"; return 1; }
    [ -L fetch/dasFlex ] && { fail env "fetch/dasFlex is a symlink; scripts/fetch_dasflex.sh needs a checkout of its own at the pin"; return 1; }
    scripts/fetch_dasflex.sh >/dev/null || { fail env "scripts/fetch_dasflex.sh cannot put dasFlex at the VERSIONS.md pin"; return 1; }
    if { [ $full = 1 ] || [ ${#only[@]} -gt 0 ]; } && wants tests; then
        lua/fetch.sh >/dev/null || { fail env "lua/fetch.sh cannot put Lua at the VERSIONS.md pin, which lua/tests and compare/tests read"; return 1; }
    fi
    pass env
}
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
    # at env.sh's DAS_LOG_LEVEL=info a compile's own LOG_INFO lines (dasFlex's [flex] scanner shape
    # on a cold module cache) would print, and the gate reads any output as findings
    local out; out=$(DAS_LOG_LEVEL=warning das "$DASLANG_ROOT/utils/lint/main.das" -- "${files[@]}" --quiet --disable LINT019 2>&1) || { echo "$out" | tail -20; fail lint "findings above"; return 1; }
    # under --quiet a clean run prints nothing at all (daScript abf1d40e35), else its summary
    { [ -z "$out" ] || echo "$out" | grep -q " 0 issue(s)"; } && pass lint || { echo "$out" | tail -20; fail lint "findings above"; }
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
gate_criteria() {
    local out rc
    out=$(das metrics/criteria.das -- --report --delta-ref "$base" 2>&1); rc=$?
    echo "$out"
    [ $rc = 0 ] && pass criteria || fail criteria "metrics/criteria_linux.json is missing or unreadable: run scripts/run_criteria.sh"
}
gate_pp_oracle() {
    suites/c_testsuite/fetch.sh >/dev/null || { fail pp-oracle "suites/c_testsuite/fetch.sh cannot put c-testsuite at its pin"; return 1; }
    pp_oracle_run pp-oracle 600 --fast
}
gate_pp_oracle_full() {
    local f
    for f in suites/c_testsuite/fetch.sh suites/gcc_torture/fetch.sh lua/fetch.sh doom/fetch.sh chibicc/fetch.sh compare/pp/fetch.sh; do
        "$f" >/dev/null || { fail pp-oracle-full "$f cannot fetch its corpus at the VERSIONS.md pin"; return 1; }
    done
    pp_oracle_run pp-oracle-full 1800 --full
}
# the token oracle over a set under a time budget in seconds: each corpus's line and every unit
# that is not clean printed, the whole output when the run is red
pp_oracle_run() {
    local name="$1" budget="$2" set="$3" out rc
    out=$(timeout "$budget" bash -c '. scripts/env.sh; das compare/pp/run.das -- --pp6 "$1"' _ "$set" 2>&1); rc=$?
    if [ $rc = 0 ]; then
        echo "$out" | grep -E '\(pp6|^total \(pp6\)|drop its line'
        pass "$name"
    else
        echo "$out" | tail -60
        fail "$name" "a unit differs from clang -E, a clang/gcc disagreement or a reference failure is unlisted, or the run passed its $budget s budget (rc $rc)"
    fi
}
# The tests lane. suite_order is the order the suites' output prints in. A test_groups entry is the
# suites that run one after another because they write the same paths (the collision map,
# skills/internal/preflight.md); up to --jobs groups run at once, started longest first. The
# isolated_suites run each test file in its own dastest worker: their files share no path.
suite_order=(probes dasCRuntime/tests c_runtime/tests frontend/tests frontend/include/tests converter/tests lua/tests chibicc/tests perf/tests ports/tests metrics/tests compare/tests doom/tests tests)
test_groups=(converter/tests compare/tests lua/tests chibicc/tests ports/tests probes perf/tests c_runtime/tests doom/tests metrics/tests tests dasCRuntime/tests frontend/include/tests frontend/tests)
# PREFLIGHT_ISOLATED_SUITES replaces the list (a space between suites), for a test of the arm
read -ra isolated_suites <<< "${PREFLIGHT_ISOLATED_SUITES-probes converter/tests c_runtime/tests doom/tests}"
iso_threads=2
# a suite's whole-run budget in seconds where dastest's default (1200) is too short on a loaded box:
# compare/tests converts real projects in test_projects.das (13 minutes alone under load) and shares a
# work folder, so it cannot run isolated; PREFLIGHT_SUITE_TIMEOUTS replaces the list, `suite=seconds`
read -ra suite_timeouts <<< "${PREFLIGHT_SUITE_TIMEOUTS-compare/tests=3600}"
suite_timeout() {
    local e
    for e in "${suite_timeouts[@]}"; do [ "${e%%=*}" = "$1" ] && { echo "${e#*=}"; return; }; done
}
run_suite() {
    local iso=() budget=() s t
    for s in "${isolated_suites[@]}"; do [ "$s" = "$1" ] && iso=(--isolated-mode --isolated-mode-threads "$iso_threads"); done
    t=$(suite_timeout "$1"); [ -n "$t" ] && budget=(--timeout "$t")
    das "$DASLANG_ROOT/dastest/dastest.das" -- --test "$1" --failures-only "${iso[@]}" "${budget[@]}"
}
suite_file() { echo "$tests_logs/${1//\//_}.$2"; }
# prints, in suite_order, every suite whose run has ended and that no unfinished suite precedes; with
# `final`, every group has ended, so a suite without a status is reported and the printing goes on
print_ended_suites() {
    local d
    while [ "$tests_printed" -lt ${#tests_order[@]} ]; do
        d="${tests_order[$tests_printed]}"
        if [ -d "$d" ]; then
            if [ -f "$(suite_file "$d" rc)" ]; then
                cat "$(suite_file "$d" log)"
                [ "$(cat "$(suite_file "$d" rc)")" = 0 ] || tests_rc=1
            elif [ "${1:-}" = final ]; then
                [ -f "$(suite_file "$d" log)" ] && cat "$(suite_file "$d" log)"
                echo "preflight: suite $d ended without a status"
                tests_rc=1
            else
                return 0
            fi
        fi
        tests_printed=$((tests_printed + 1))
    done
}
remove_tests_logs() { [ -n "${tests_logs:-}" ] && [ -d "$tests_logs" ] && find "$tests_logs" -mindepth 1 -delete && rmdir "$tests_logs"; tests_logs=""; }
gate_tests() {
    local groups d g running=0 next=0
    tests_rc=0; tests_printed=0
    if [ -n "${PREFLIGHT_TEST_GROUPS:-}" ]; then
        # named groups replace the lane's: `;` between groups, a space between the suites of one, in
        # print order; a named folder that does not exist is a red lane (the default list skips one)
        IFS=';' read -ra groups <<< "$PREFLIGHT_TEST_GROUPS"
        tests_order=(); for g in "${groups[@]}"; do for d in $g; do tests_order+=("$d"); done; done
        for d in "${tests_order[@]}"; do
            [ -d "$d" ] || { fail tests "PREFLIGHT_TEST_GROUPS names $d, no such suite folder"; return 1; }
        done
    else
        groups=("${test_groups[@]}"); tests_order=("${suite_order[@]}")
    fi
    if [ "$jobs" = 1 ]; then
        # one suite after another in print order, each single-threaded, its output streamed
        for d in "${tests_order[@]}"; do
            [ -d "$d" ] || continue
            t=$(suite_timeout "$d")
            das "$DASLANG_ROOT/dastest/dastest.das" -- --test "$d" --failures-only ${t:+--timeout "$t"} || tests_rc=1
        done
    else
        tests_logs=$(mktemp -d) || { fail tests "no scratch folder for the suites' output"; return 1; }
        trap remove_tests_logs EXIT
        trap 'kill $(jobs -p) 2>/dev/null; remove_tests_logs; exit 130' INT TERM
        while [ $next -lt ${#groups[@]} ] || [ $running -gt 0 ]; do
            while [ $running -lt "$jobs" ] && [ $next -lt ${#groups[@]} ]; do
                (
                    for d in ${groups[$next]}; do
                        [ -d "$d" ] || continue
                        run_suite "$d" > "$(suite_file "$d" log)" 2>&1
                        echo $? > "$(suite_file "$d" rc.tmp)" && mv "$(suite_file "$d" rc.tmp)" "$(suite_file "$d" rc)"
                    done
                ) &
                running=$((running + 1)); next=$((next + 1))
            done
            wait -n; running=$((running - 1))
            print_ended_suites
        done
        print_ended_suites final
        remove_tests_logs
        trap - EXIT INT TERM
    fi
    [ $tests_rc = 0 ] && pass tests || fail tests "a suite is red"
}
fast=(env native untracked format lint compile ast-verify md-ascii review-md pp-oracle criteria)
red=0
for g in "${fast[@]}"; do
    wants "$g" || continue
    "gate_${g//-/_}" || { red=1; break; }
done
if [ $red = 0 ] && { [ $full = 1 ] || [ ${#only[@]} -gt 0 ]; }; then
    wants tests && { gate_tests || red=1; }
    wants pp-oracle-full && { gate_pp_oracle_full || red=1; }
fi
[ $red = 0 ] && echo "preflight: green" || { echo "preflight: red"; exit 1; }
