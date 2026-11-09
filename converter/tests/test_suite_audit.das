options gen2
require dastest/testing_boost public
require strings
require daslib/strings_boost
require daslib/fio
require ../../suites/suite_runner.das

//! The runner's skip audit (`--audit-skips`) over a stand-in suite: only the ledgered ids run,
//! each outcome lands in `work/skip_audit.tsv` with its feature, and the ratchet is untouched but
//! under `--update`, which only adds the ids that passed. The runner's `--tier`: each tier runs
//! the suite, an unknown tier and `--update` under any but the interpreter are refused.

def torture_verdict(id : string; _c_path : string; rc : int; output : string) : Outcome =>
    rc != 0 ? Outcome(id = id, status = "exit", reason = "exited {rc}: {first_line(output)}") : Outcome(id = id, status = "pass", reason = "")

let RATCHET_TEXT = "# stand-in\nplain\n"

// a stand-in suite under `dir`: tests/<id>.c for each program, the ledger and the ratchet; the
// ledgered `spin` has no program until a test writes one
def make_suite(dir : string; run_timeout : float) : SuiteSpec {
    let spec = SuiteSpec(name = "standin", tests_dir = path_join(dir, "tests"), work_dir = path_join(dir, "work"), expected_pass = path_join(dir, "expected_pass.txt"), skip_ledger = path_join(dir, "skip.txt"), run_timeout = run_timeout)
    mkdir_rec(spec.tests_dir)
    fwrite(path_join(spec.tests_dir, "ok.c"), "int main(void) \{ return 0; \}\n")
    fwrite(path_join(spec.tests_dir, "bad.c"), "int main(void) \{ return 3; \}\n")
    fwrite(path_join(spec.tests_dir, "plain.c"), "int main(void) \{ return 0; \}\n")
    fwrite(spec.skip_ledger, "# ledger\nok\tfeature a\treason\tP9.1\nbad\tfeature b\treason\tnever\nghost\tfeature a\treason\tnever\nspin\tfeature c\treason\tnever\n")
    fwrite(spec.expected_pass, RATCHET_TEXT)
    return spec
}

[test]
def test_audit_status(t : T?) {
    t |> run("a conversion error is split by the stage its prefix names, an output mismatch renamed") @(t : T?) {
        t |> equal(audit_status(Outcome(id = "a", status = "convert", reason = "dumper: clang refused it")), "dumper")
        t |> equal(audit_status(Outcome(id = "a", status = "convert", reason = "emitter: no lowering")), "emitter")
        t |> equal(audit_status(Outcome(id = "a", status = "convert", reason = "compile check: error[30304]")), "compile")
        t |> equal(audit_status(Outcome(id = "a", status = "convert", reason = "reader: bad C-IR")), "convert")
        t |> equal(audit_status(Outcome(id = "a", status = "output", reason = "got `1`")), "mismatch")
        t |> equal(audit_status(Outcome(id = "a", status = "exit", reason = "exited 1")), "exit")
        t |> equal(audit_status(Outcome(id = "a", status = "timeout", reason = "")), "timeout")
    }
    t |> run("a skip line of an id alone names no feature") @(t : T?) {
        t |> equal(skip_line("lonely").feature, "")
        t |> equal(skip_line("lonely").id, "lonely")
    }
    t |> run("an audit row keeps the reason's first line, tabs spelled as spaces") @(t : T?) {
        let row = audit_row("f", Outcome(id = "a", status = "exit", reason = "exited 1:\tx\nmore"))
        t |> equal(row.reason, "exited 1: x")
        t |> equal(row.feature, "f")
    }
    t |> run("the tally counts each status per feature, both sorted") @(t : T?) {
        let rows <- [AuditRow(id = "1", feature = "z", status = "pass"), AuditRow(id = "2", feature = "a", status = "exit"), AuditRow(id = "3", feature = "a", status = "dumper"), AuditRow(id = "4", feature = "a", status = "exit")]
        let lines <- audit_tally(rows)
        t |> equal(join(lines, "|"), "a: dumper 1, exit 2|z: pass 1")
    }
}

[test]
def test_audit_suite(t : T?) {
    var dir_error : string
    let dir = create_temp_directory("c2das_skip_audit", dir_error)
    t |> equal(dir_error, "")
    if (empty(dir)) {
        return
    }
    t |> run("only the ledgered ids run, each with its feature, into work/skip_audit.tsv; a ledgered id with no file is missing") @(t : T?) {
        let spec = make_suite(dir, 60.0)
        let rows <- audit_suite(spec, "", "linux", "interp", @@torture_verdict)
        let seen = join([for (r in rows); "{r.id}:{r.feature}:{r.status}"], " ")
        t |> equal(seen, "bad:feature b:exit ghost:feature a:missing ok:feature a:pass spin:feature c:missing")
        t |> success(find(fread(path_join(spec.work_dir, "skip_audit.tsv")), "ghost\tfeature a\tmissing\tno ghost.c in ") >= 0)
        let tsv = fread(path_join(spec.work_dir, "skip_audit.tsv"))
        t |> success(find(tsv, "bad\tfeature b\texit\texited 3: \n") >= 0, tsv)
        t |> success(find(tsv, "ok\tfeature a\tpass\t\n") >= 0, tsv)
        t |> success(find(tsv, "bad\t") < find(tsv, "ok\t"), "rows are sorted by id: {tsv}")
        t |> equal(fexist(path_join(spec.work_dir, "plain")), false, "an unlisted id never runs")
        t |> equal(fread(spec.expected_pass), RATCHET_TEXT)
    }
    t |> run("a filter narrows the missing ids too") @(t : T?) {
        let spec = make_suite(dir, 60.0)
        let rows <- audit_suite(spec, "ok", "linux", "interp", @@torture_verdict)
        t |> equal(join([for (r in rows); "{r.id}:{r.status}"], " "), "ok:pass")
    }
    t |> run("--update joins the audited ids that pass to the ratchet, sorted; a failure, a timeout or a missing file joins nothing") @(t : T?) {
        let spec = make_suite(dir, 60.0)
        let rows <- [AuditRow(id = "zeta", status = "pass"), AuditRow(id = "alpha", status = "pass"), AuditRow(id = "plain", status = "pass"), AuditRow(id = "bad", status = "exit"), AuditRow(id = "slow", status = "timeout"), AuditRow(id = "ghost", status = "missing")]
        t |> equal(join_audit_passes("standin", spec.expected_pass, rows), 2)
        t |> equal(fread(spec.expected_pass), "# standin tests that pass under the interpreter; the ratchet, kept sorted\nalpha\nplain\nzeta\n")
        t |> equal(join_audit_passes("standin", spec.expected_pass, rows), 0)
    }
    t |> run("a run past the suite's timeout is `timeout`, not `exit`") @(t : T?) {
        let spec = make_suite(dir, 3.0)
        fwrite(path_join(spec.tests_dir, "spin.c"), "int main(void) \{ volatile int x = 1; while (x) \{ \} return 0; \}\n")
        let rows <- audit_suite(spec, "spin", "linux", "interp", @@torture_verdict)
        t |> equal(length(rows), 1)
        if (length(rows) == 1) {
            t |> equal(rows[0].status, "timeout")
            t |> equal(rows[0].reason, "ran longer than 3 s")
        }
    }
    rmdir_rec(dir)
}

[test]
def test_audited_lines(t : T?) {
    t |> run("an audit judges each ledgered id once, by its first line, those the filter holds, sorted") @(t : T?) {
        let lines <- [skip_line("30\tgoto\tr\tP7.7"), skip_line("100\tgoto\tr\tP7.7"), skip_line("30\tother\tr\tnever"), skip_line("200")]
        let all <- audited_lines(lines, "")
        t |> equal(join([for (l in all); "{l.id}:{l.feature}"], " "), "100:goto 200: 30:goto")
        let some <- audited_lines(lines, "0")
        t |> equal(length(some), 3)
        let one <- audited_lines(lines, "20")
        t |> equal(join([for (l in one); l.id], " "), "200")
    }
}

// the stand-in tree a child run of `suites/gcc_torture/run.das` reads from its working folder:
// the tests, the ledger, the ratchet, and the module folders the converted run loads
def make_torture_tree(root : string) : string {
    let tests = path_join(root, "suites/gcc_torture/fetch/gcc/gcc/testsuite/gcc.c-torture/execute")
    mkdir_rec(tests)
    fwrite(path_join(tests, "ok.c"), "int main(void) \{ return 0; \}\n")
    fwrite(path_join(tests, "bad.c"), "int main(void) \{ return 3; \}\n")
    fwrite(path_join(tests, "plain.c"), "int main(void) \{ return 0; \}\n")
    fwrite(path_join(root, "suites/gcc_torture/skip.txt"), "# ledger\nok\tfeature a\treason\tP9.1\nbad\tfeature b\treason\tnever\n")
    fwrite(path_join(root, "suites/gcc_torture/expected_pass.txt"), RATCHET_TEXT)
    var out : string
    run_and_capture(["bash", "-c", "ln -s \"$(pwd)/c_runtime\" \"$(pwd)/dasCRuntime\" \"$1\"", "links", root], out, 60.0)
    return path_join(root, "suites/gcc_torture/expected_pass.txt")
}

// `suites/gcc_torture/run.das -- <flags>` run in `root`: its exit code, its output in `out`
def run_torture(root : string; flags : string; var out : string&) : int {
    let daslang = get_das_root() + "/bin/daslang"
    return run_and_capture(["bash", "-c", "repo=$(pwd); cd \"$1\" && \"$2\" -load_module \"$repo/dasCRuntime\" -load_module \"$repo/c_runtime\" \"$repo/suites/gcc_torture/run.das\" -- $3", "torture", root, daslang, flags], out, 600.0)
}

[test]
def test_audit_cli(t : T?) {
    var dir_error : string
    let root = create_temp_directory("c2das_audit_cli", dir_error)
    t |> equal(dir_error, "")
    if (empty(root)) {
        return
    }
    let ratchet = make_torture_tree(root)
    t |> run("--audit-skips runs the ledger alone and exits 0, the ratchet untouched and never run") @(t : T?) {
        var out : string
        t |> equal(run_torture(root, "--audit-skips", out), 0, out)
        t |> success(fexist(path_join(root, "suites/gcc_torture/work/skip_audit.tsv")), out)
        t |> equal(fexist(path_join(root, "suites/gcc_torture/work/plain")), false, "the ratchet's id ran: {out}")
        t |> equal(fread(ratchet), RATCHET_TEXT)
    }
    t |> run("--audit-skips --update joins the passing ledgered id, not the failing one") @(t : T?) {
        var out : string
        t |> equal(run_torture(root, "--audit-skips --update", out), 0, out)
        t |> equal(fread(ratchet), "# gcc_torture tests that pass under the interpreter; the ratchet, kept sorted\nok\nplain\n")
    }
    rmdir_rec(root)
}

[test]
def test_tier_refusal(t : T?) {
    t |> run("every tier of SUITE_TIERS runs, --update only under the interpreter; any other tier is refused by name") @(t : T?) {
        for (tier in SUITE_TIERS) {
            t |> equal(tier_refusal(tier, false), "", tier)
        }
        t |> equal(tier_refusal("interp", true), "")
        t |> equal(tier_refusal("jit", true), "--update records the interpreter's ratchet; run it under --tier interp")
        t |> equal(tier_refusal("exe", true), "--update records the interpreter's ratchet; run it under --tier interp")
        t |> equal(tier_refusal("aot", false), "unknown tier `aot`: one of interp, jit, exe")
        t |> equal(tier_refusal("", false), "unknown tier ``: one of interp, jit, exe")
    }
}

// whether a JIT library sits under `root`'s `.cache/daslang`: the interpreter caches only modules there
def has_jit_library(root : string) : bool {
    var out : string
    run_and_capture(["bash", "-c", "find \"$1/.cache/daslang\" -name '*.dll' 2>/dev/null | head -1", "jit", root], out, 60.0)
    return !empty(strip(out))
}

[test]
def test_tier_cli(t : T?) {
    var dir_error : string
    let root = create_temp_directory("c2das_tier_cli", dir_error)
    t |> equal(dir_error, "")
    if (empty(root)) {
        return
    }
    let ratchet = make_torture_tree(root)
    let exe = path_join(root, "suites/gcc_torture/work/plain/plain_exe")
    t |> run("--tier interp, the default, runs the ratchet's id in the interpreter: no JIT library, no exe") @(t : T?) {
        var out : string
        t |> equal(run_torture(root, "--tier interp --filter plain", out), 0, out)
        t |> success(fexist(path_join(root, "suites/gcc_torture/work/plain/plain.das")), out)
        t |> equal(has_jit_library(root), false, out)
        t |> equal(fexist(exe), false, out)
    }
    t |> run("--tier jit runs it under the JIT, whose library lands in the working folder's cache") @(t : T?) {
        var out : string
        t |> equal(run_torture(root, "--tier jit --filter plain", out), 0, out)
        t |> success(has_jit_library(root), out)
        t |> equal(fexist(exe), false, out)
    }
    t |> run("--tier exe builds the module's executable beside it and runs that") @(t : T?) {
        var out : string
        t |> equal(run_torture(root, "--tier exe --filter plain", out), 0, out)
        t |> success(fexist(exe), out)
    }
    t |> run("a listed id that fails under a tier breaks the ratchet under that tier") @(t : T?) {
        fwrite(path_join(root, "suites/gcc_torture/fetch/gcc/gcc/testsuite/gcc.c-torture/execute/plain.c"), "int main(void) \{ return 5; \}\n")
        var out : string
        t |> equal(run_torture(root, "--tier jit --filter plain", out), 1, out)
        t |> success(out |> contains("ratchet broken, these passed before: plain"), out)
    }
    t |> run("an unknown tier exits 2 naming the tiers, --update under the JIT exits 2; neither runs a test") @(t : T?) {
        rmdir_rec(path_join(root, "suites/gcc_torture/work"))
        var out : string
        t |> equal(run_torture(root, "--tier aot", out), 2, out)
        t |> success(out |> contains("unknown tier `aot`: one of interp, jit, exe"), out)
        t |> equal(run_torture(root, "--tier jit --update", out), 2, out)
        t |> success(out |> contains("--update records the interpreter's ratchet"), out)
        t |> equal(fexist(path_join(root, "suites/gcc_torture/work")), false, out)
        t |> equal(fread(ratchet), RATCHET_TEXT)
    }
    rmdir_rec(root)
}

[test]
def test_closed_phase(t : T?) {
    t |> run("the phase column parses to its phase number, never and other text to -1") @(t : T?) {
        t |> equal(phase_number("P7.5"), 7)
        t |> equal(phase_number("P3.3"), 3)
        t |> equal(phase_number("P4"), 4)
        t |> equal(phase_number("P12.1"), 12)
        t |> equal(phase_number("never"), -1)
        t |> equal(phase_number("P"), -1)
        t |> equal(phase_number("Px.1"), -1)
    }
    t |> run("the highest closed phase is the largest v0.<N>.0 tag, never below the floor") @(t : T?) {
        t |> equal(highest_closed_phase([""]), CLOSED_PHASE_FLOOR)
        t |> equal(highest_closed_phase(["v0.4.0", "v0.5.0", "v0.6.1", "v1.7.0", "v0.x.0"]), 5)
        t |> equal(highest_closed_phase(["v0.2.0"]), CLOSED_PHASE_FLOOR)
        t |> equal(highest_closed_phase(["v0.9.0.0", "v0.9"]), CLOSED_PHASE_FLOOR)
    }
    t |> run("a phase column is never or a row id; anything else is malformed") @(t : T?) {
        for (good in fixed_array("never", "P7", "P7.5", "P5.1c", "P12.10")) {
            t |> equal(phase_well_formed(good), true, good)
        }
        for (bad in fixed_array("P4a", "Px", "P7.", "P.5", "P7.5.1", "P7.c", "p7.5", "", "Never")) {
            t |> equal(phase_well_formed(bad), false, bad)
        }
    }
    t |> run("a phase at or below the highest closed one is closed; never and a later phase are not") @(t : T?) {
        t |> equal(names_closed_phase("P3.3", 4), true)
        t |> equal(names_closed_phase("P4", 4), true)
        t |> equal(names_closed_phase("P5.1c", 4), false)
        t |> equal(names_closed_phase("P7.5", 4), false)
        t |> equal(names_closed_phase("never", 4), false)
    }
}

[test]
def test_review_gate(t : T?) {
    var dir_error : string
    let root = create_temp_directory("c2das_suites_gate", dir_error)
    t |> equal(dir_error, "")
    if (empty(root)) {
        return
    }
    for (suite in fixed_array("c_testsuite", "gcc_torture", "csmith")) {
        mkdir_rec(path_join(root, "suites/{suite}"))
    }
    fwrite(path_join(root, "suites/gcc_torture/skip.txt"), "# ledger\nclosed\tf\tr\tP4\nlive\tf\tr\tP7.5\nnone\tf\tr\tnever\nodd\tf\tr\tP4a\n")
    t |> run("suites/REVIEW.das names a skip line of a closed phase and a malformed phase, and passes a live row and never") @(t : T?) {
        var out : string
        let daslang = get_das_root() + "/bin/daslang"
        let rc = run_and_capture(["bash", "-c", "repo=$(pwd); cd \"$1\" && \"$2\" \"$repo/suites/REVIEW.das\"", "gate", root, daslang], out, 120.0)
        t |> equal(rc, 1, out)
        t |> success(out |> contains("`closed` names P4, a closed phase"), out)
        t |> success(out |> contains("`odd\tf\tr\tP4a`: a skip line is id, feature, reason, ledger row id"), out)
        t |> success(!(out |> contains("`live`")), out)
        t |> success(!(out |> contains("`none`")), out)
        t |> success(!(out |> contains("filter_rules.das")), out)
    }
    t |> run("suites/REVIEW.das names a filter rule whose phase a v0.<N>.0 tag closed") @(t : T?) {
        var out : string
        let daslang = get_das_root() + "/bin/daslang"
        let git = "git -c user.name=gate -c user.email=gate@invalid"
        let script = "repo=$(pwd); cd \"$1\" && git init -q && {git} commit -q --allow-empty -m tag && git tag v0.7.0 && \"$2\" \"$repo/suites/REVIEW.das\""
        let rc = run_and_capture(["bash", "-c", script, "gate", root, daslang], out, 120.0)
        t |> equal(rc, 1, out)
        t |> success(out |> contains("suites/gcc_torture/filter_rules.das: the rule for `_Complex` names P7.5"), out)
        t |> success(!(out |> contains("names never")), out)
    }
    rmdir_rec(root)
}
