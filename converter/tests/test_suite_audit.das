options gen2
require dastest/testing_boost public
require strings
require daslib/strings_boost
require daslib/fio
require ../../suites/suite_runner.das

//! The runner's skip audit (`--audit-skips`) over a stand-in suite: only the ledgered ids run,
//! each outcome lands in `work/skip_audit.tsv` with its feature, and the ratchet is untouched.

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
    t |> run("only the ledgered ids present run, each with its feature, into work/skip_audit.tsv") @(t : T?) {
        let spec = make_suite(dir, 60.0)
        let rows <- audit_suite(spec, "", "linux", @@torture_verdict)
        let seen = join([for (r in rows); "{r.id}:{r.feature}:{r.status}"], " ")
        t |> equal(seen, "ok:feature a:pass bad:feature b:exit")
        let tsv = fread(path_join(spec.work_dir, "skip_audit.tsv"))
        t |> success(find(tsv, "bad\tfeature b\texit\texited 3: \n") >= 0, tsv)
        t |> success(find(tsv, "ok\tfeature a\tpass\t\n") >= 0, tsv)
        t |> success(find(tsv, "bad\t") < find(tsv, "ok\t"), "rows are sorted by id: {tsv}")
        t |> equal(fexist(path_join(spec.work_dir, "plain")), false, "an unlisted id never runs")
        t |> equal(fread(spec.expected_pass), RATCHET_TEXT)
    }
    t |> run("a run past the suite's timeout is `timeout`, not `exit`") @(t : T?) {
        let spec = make_suite(dir, 3.0)
        fwrite(path_join(spec.tests_dir, "spin.c"), "int main(void) \{ volatile int x = 1; while (x) \{ \} return 0; \}\n")
        let rows <- audit_suite(spec, "spin", "linux", @@torture_verdict)
        t |> equal(length(rows), 1)
        if (length(rows) == 1) {
            t |> equal(rows[0].status, "timeout")
            t |> equal(rows[0].reason, "ran longer than 3 s")
        }
    }
    rmdir_rec(dir)
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
    }
    t |> run("a phase at or below the highest closed one is closed; never and a later phase are not") @(t : T?) {
        t |> equal(names_closed_phase("P3.3", 4), true)
        t |> equal(names_closed_phase("P4", 4), true)
        t |> equal(names_closed_phase("P5.1c", 4), false)
        t |> equal(names_closed_phase("P7.5", 4), false)
        t |> equal(names_closed_phase("never", 4), false)
    }
}
