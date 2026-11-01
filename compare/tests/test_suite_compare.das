options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require daslib/json_boost
require ../../suites/suite_runner.das
require ../../suites/csmith/generate.das
require ../suite_compare.das
require _common

//! `compare/suite_compare.das` over a stand-in translator: a shell script that refuses
//! `refused.c`, sleeps on `slow.c`, and otherwise copies the das program `<stem>.das.src` beside
//! it into its output folder. The programs and the compile checks run on the real daslang; the
//! real Rust binary never runs here.

let STAND_IN = "#!/bin/sh\nout=\"\"\nprev=\"\"\nfor a in \"$@\"; do\n    if [ \"$prev\" = \"--output-dir\" ]; then out=\"$a\"; fi\n    prev=\"$a\"\ndone\nstem=$(basename \"$2\" .c)\necho \"c2dascript-transpile v0.1.0\" >&2\necho \"Transpiling $stem\"\ncase \"$stem\" in\n    refused) echo \"translation failed: unsupported external call: clock\" >&2; exit 2 ;;\n    slow) exec sleep 10 ;;\nesac\nmkdir -p \"$out\"\ncp \"$(dirname \"$0\")/$stem.das.src\" \"$out/$stem.das\"\n"

// a das program whose `main` runs `body`
def private das_main(body : string) : string => "options gen2\n[export]\ndef main() : int \{\n{body}\n\}\n"

// the stand-in's programs by C file stem
let PROGRAMS <- {
    "hello" => das_main("    print(\"hi\\n\")\n    return 0"),
    "wrong" => das_main("    print(\"bye\\n\")\n    return 0"),
    "exit1" => das_main("    print(\"bad\\n\")\n    return 1"),
    "loop" => das_main("    var i = 0\n    while (i >= 0) \{\n        i = (i + 1) % 7\n    \}\n    return i"),
    "broken" => das_main("    return undefined_name"),
    "nomain" => "options gen2\ndef helper() : int \{\n    return 0\n\}\n"
}

// a program of many functions: its compile check takes far longer than the 100 ms the timed
// capture polls its child at
def private many_functions : string {
    return build_string() $(var w) {
        w |> write("options gen2\n")
        for (i in range(10000)) {
            w |> write("def f{i}(a : int) : int \{\n    return a * {i} + {i}\n\}\n")
        }
        w |> write(das_main("    return f1(1)"))
    }
}

let LIMITS = Limits(translate = 60.0, compile = 60.0, run = 30.0, native = 10.0)

// a scratch folder holding the executable stand-in `rust` and the programs it copies, passed to
// `body` with the stand-in's path and removed after it
def private with_stand_in(t : T?; name : string; body : block<(dir, bin : string) : void>) {
    var dir_error : string
    let dir = create_temp_directory(name, dir_error)
    if (!empty(dir_error)) {
        t |> failure("no scratch folder: {dir_error}")
        return
    }
    let bin = path_join(dir, "rust")
    fwrite(bin, STAND_IN)
    var out : string
    run_and_capture(["chmod", "+x", bin], out, 30.0)
    for (stem, text in keys(PROGRAMS), values(PROGRAMS)) {
        fwrite(path_join(dir, "{stem}.das.src"), text)
    }
    fwrite(path_join(dir, "big.das.src"), many_functions())
    invoke(body, dir, bin)
    rmdir_rec(dir)
}

// the verdict on `<dir>/<stem>.c` in a fresh work folder `<dir>/w_<stem>`
def private judged(dir, bin, stem : string; limits : Limits; oracle : Oracle) : CaseVerdict => judge_translation(bin, path_join(dir, "{stem}.c"), path_join(dir, "w_{stem}"), limits, oracle)

[test]
def test_statuses(t : T?) {
    t |> run("refused, compile, timeout, exit, output and pass, each from its own program") @(t : T?) {
        t |> with_stand_in("cmp_status") $(dir, bin) {
            let hi = Oracle(judge_output = true, expected = "hi\n")
            var v = judged(dir, bin, "refused", LIMITS, hi)
            t |> equal(v.status, "refused")
            t |> equal(v.reason, "translation failed: unsupported external call: clock")
            v = judged(dir, bin, "nomain", LIMITS, hi)
            t |> equal(v.status, "refused")
            t |> success(v.reason |> ends_with("defines main"), v.reason)
            v = judged(dir, bin, "broken", LIMITS, hi)
            t |> equal(v.status, "compile")
            t |> success(v.reason |> starts_with("error[") && v.reason |> contains("undefined_name"), v.reason)
            v = judged(dir, bin, "exit1", LIMITS, hi)
            t |> equal(v.status, "exit")
            t |> equal(v.reason, "exited 1: bad")
            v = judged(dir, bin, "wrong", LIMITS, hi)
            t |> equal(v.status, "output")
            t |> equal(v.reason, "got `bye`, expected `hi`")
            v = judged(dir, bin, "hello", LIMITS, hi)
            t |> equal(v.status, "pass")
            t |> equal(v.reason, "")
        }
    }
    t |> run("an oracle that does not judge output passes any output and still judges the exit") @(t : T?) {
        t |> with_stand_in("cmp_exit_only") $(dir, bin) {
            t |> equal(judged(dir, bin, "wrong", LIMITS, Oracle()).status, "pass")
            t |> equal(judged(dir, bin, "exit1", LIMITS, Oracle()).status, "exit")
        }
    }
    t |> run("the translator, the compile check and the run past their limits") @(t : T?) {
        t |> with_stand_in("cmp_timeout") $(dir, bin) {
            var v = judged(dir, bin, "slow", Limits(translate = 0.3, compile = 60.0, run = 30.0), Oracle())
            t |> equal(v.status, "timeout")
            t |> success(v.reason |> starts_with("the translator took longer"), v.reason)
            v = judged(dir, bin, "big", Limits(translate = 60.0, compile = 0.01, run = 30.0), Oracle())
            t |> equal(v.status, "timeout")
            t |> success(v.reason |> starts_with("the compile check took longer"), v.reason)
            v = judged(dir, bin, "loop", Limits(translate = 60.0, compile = 60.0, run = 1.0), Oracle())
            t |> equal(v.status, "timeout")
            t |> success(v.reason |> starts_with("the run took longer"), v.reason)
        }
    }
}

[test]
def test_csmith_program(t : T?) {
    t |> run("a csmith program against its native build") @(t : T?) {
        t |> with_stand_in("cmp_csmith") $(dir, bin) {
            fwrite(path_join(dir, "hello.c"), "#include <stdio.h>\nint main(void) \{ printf(\"hi\\n\"); return 0; \}\n")
            fwrite(path_join(dir, "wrong.c"), "#include <stdio.h>\nint main(void) \{ printf(\"hi\\n\"); return 0; \}\n")
            fwrite(path_join(dir, "exit1.c"), "int main(void) \{ return 1; \}\n")
            fwrite(path_join(dir, "broken.c"), "int main(void) \{ return \n")
            fwrite(path_join(dir, "loop.c"), "int main(void) \{ for (;;) \{\} \}\n")
            let csmith_of = $(stem : string; limits : Limits) => judge_csmith_program(bin, path_join(dir, "{stem}.c"), path_join(dir, "w_{stem}"), limits)
            t |> equal(invoke(csmith_of, "hello", LIMITS).status, "pass")
            t |> equal(invoke(csmith_of, "wrong", LIMITS).status, "output")
            var v = invoke(csmith_of, "exit1", LIMITS)
            t |> equal(v.status, "native")
            t |> equal(v.reason, "the native run exited 1")
            v = invoke(csmith_of, "broken", LIMITS)
            t |> equal(v.status, "native")
            t |> success(v.reason |> starts_with("gcc refused it:"), v.reason)
            v = invoke(csmith_of, "loop", Limits(translate = 60.0, compile = 60.0, run = 30.0, native = 0.3))
            t |> equal(v.status, "timeout")
            t |> success(v.reason |> starts_with("the native run took longer"), v.reason)
        }
    }
    t |> run("a program the suite's run left is reused; otherwise one is generated into the work folder") @(t : T?) {
        t |> with_stand_in("cmp_csmith_source") $(dir, _bin) {
            mkdir_rec(path_join(dir, "reuse/17"))
            fwrite(path_join(dir, "reuse/17/17.c"), "int main(void) \{ return 0; \}\n")
            var prog = csmith_source("17", path_join(dir, "reuse"), path_join(dir, "work17"))
            t |> equal(prog.c_path, path_join(dir, "reuse/17/17.c"))
            prog = csmith_source("18", path_join(dir, "reuse"), path_join(dir, "work18"))
            if (fexist("{CSMITH_DIR}/build/src/csmith")) {
                t |> equal(prog.c_path, "{path_join(dir, "work18")}/18.c")
                t |> success(fexist(prog.c_path), prog.c_path)
            } else {
                t |> success(!empty(prog.error), "no csmith, yet a program")
            }
        }
    }
}

[test]
def test_judge_case(t : T?) {
    t |> run("each suite's oracle, the work folder emptied first and the verdict written into it") @(t : T?) {
        t |> with_stand_in("cmp_case") $(dir, bin) {
            fwrite(path_join(dir, "wrong.c"), "#include <stdio.h>\nint main(void) \{ printf(\"hi\\n\"); return 0; \}\n")
            fwrite(path_join(dir, "wrong.c.expected"), "hi\n")
            let c_spec = SuiteSpec(name = "c_testsuite", tests_dir = dir, work_dir = path_join(dir, "c_work"), run_timeout = 30.0)
            mkdir_rec(path_join(dir, "c_work/wrong/das"))
            fwrite(path_join(dir, "c_work/wrong/das/stale.das"), "stale")
            var v = judge_case(c_spec, "wrong", bin)
            t |> equal(v.status, "output")
            let back = read_case_verdict(case_verdict_path(c_spec, "wrong"))
            t |> equal(back.status, "output")
            t |> equal(back.reason, v.reason)
            t |> success(!fexist(path_join(dir, "c_work/wrong/das/stale.das")), "the work folder kept a stale file")
            let torture_spec = SuiteSpec(name = "gcc_torture", tests_dir = dir, work_dir = path_join(dir, "t_work"), run_timeout = 30.0)
            t |> equal(judge_case(torture_spec, "wrong", bin).status, "pass")
            mkdir_rec(path_join(dir, "seeds/wrong"))
            fwrite(path_join(dir, "seeds/wrong/wrong.c"), "#include <stdio.h>\nint main(void) \{ printf(\"hi\\n\"); return 0; \}\n")
            let csmith_spec = SuiteSpec(name = "csmith", tests_dir = path_join(dir, "seeds"), work_dir = path_join(dir, "s_work"), run_timeout = 30.0)
            v = judge_case(csmith_spec, "wrong", bin)
            t |> equal(v.status, "output")
            t |> success(v.seconds > 0.0)
        }
    }
}

[test]
def test_verdict_file(t : T?) {
    t |> run("a verdict round trip, a tab or newline in the reason a space; no file or a short line reads as no verdict") @(t : T?) {
        t |> with_stand_in("cmp_verdict") $(dir, _bin) {
            let path = path_join(dir, "verdict")
            write_case_verdict(path, CaseVerdict(status = "exit", reason = "exited 1:\tbad\nmore", seconds = 1.5))
            let back = read_case_verdict(path)
            t |> equal(back.status, "exit")
            t |> equal(back.reason, "exited 1: bad more")
            t |> equal(back.seconds, 1.5)
            write_case_verdict(path, CaseVerdict(status = "pass", seconds = 0.25))
            t |> equal(read_case_verdict(path).status, "pass")
            t |> equal(read_case_verdict(path).reason, "")
            fwrite(path, "pass\n")
            t |> equal(read_case_verdict(path).status, "")
            t |> equal(read_case_verdict(path_join(dir, "absent")).status, "")
        }
    }
}

[test]
def test_ids_and_tags(t : T?) {
    t |> run("an id's tag, and a suite's ids: the files of the folder, csmith's ratchet and ledger seeds") @(t : T?) {
        t |> with_stand_in("cmp_ids") $(dir, _bin) {
            fwrite(path_join(dir, "expected_pass.txt"), "# ratchet\n3\n12\n")
            fwrite(path_join(dir, "skip.txt"), "# ledger\n40\tfeature\treason\tP7.6\n")
            let ratchet <- read_ratchet(path_join(dir, "expected_pass.txt"), path_join(dir, "skip.txt"))
            t |> equal(id_tag(ratchet, "3"), "ours")
            t |> equal(id_tag(ratchet, "40"), "skipped")
            t |> equal(id_tag(ratchet, "5"), "unlisted")
            let csmith_spec = SuiteSpec(name = "csmith", tests_dir = path_join(dir, "seeds"))
            t |> equal(join(suite_ids(csmith_spec, ratchet, ""), " "), "12 3 40")
            t |> equal(join(suite_ids(csmith_spec, ratchet, "4"), " "), "40")
            fwrite(path_join(dir, "b.c"), "")
            fwrite(path_join(dir, "a.c"), "")
            let file_spec = SuiteSpec(name = "c_testsuite", tests_dir = dir)
            t |> equal(join(suite_ids(file_spec, ratchet, ""), " "), "a b")
        }
    }
}

[test]
def test_worker_id(t : T?) {
    t |> run("`<suite>/<id>` both ways; an empty part or a path in the id is refused") @(t : T?) {
        var suite, id : string
        t |> equal(worker_id("c_testsuite", "00001"), "c_testsuite/00001")
        t |> success(split_worker_id("c_testsuite/00001", suite, id))
        t |> equal(suite, "c_testsuite")
        t |> equal(id, "00001")
        for (bad in fixed_array("c_testsuite", "/00001", "csmith/", "csmith/a/b", "csmith/..")) {
            t |> success(!split_worker_id(bad, suite, id), bad)
        }
    }
}

[test]
def test_case_outcome(t : T?) {
    t |> run("a killed worker times out, one without a verdict crashed, any other gives its verdict") @(t : T?) {
        var o = case_outcome("7", "ours", true, -1, 600.0, CaseVerdict(status = "pass"))
        t |> equal(o.status, "timeout")
        o = case_outcome("7", "ours", false, 1, 600.0, CaseVerdict())
        t |> equal(o.status, "crash")
        t |> equal(o.reason, "the worker exited 1 without a verdict")
        o = case_outcome("7", "skipped", false, 0, 600.0, CaseVerdict(status = "exit", reason = "exited 1: x", seconds = 2.0))
        t |> equal(o.status, "exit")
        t |> equal(o.reason, "exited 1: x")
        t |> equal(o.tag, "skipped")
        t |> equal(o.seconds, 2.0)
    }
}

[test]
def test_suite_capture(t : T?) {
    t |> run("the ratchet's counts, the Rust side's per status and its passes per tag") @(t : T?) {
        var ratchet : Ratchet
        ratchet.expected <- ["1", "2"]
        ratchet.skips |> insert("3")
        var outcomes <- [CaseOutcome(id = "1", tag = "ours", status = "pass"), CaseOutcome(id = "2", tag = "ours", status = "compile"), CaseOutcome(id = "3", tag = "skipped", status = "pass"), CaseOutcome(id = "4", tag = "unlisted", status = "pass"), CaseOutcome(id = "5", tag = "unlisted", status = "refused")]
        let c <- suite_capture(ratchet, outcomes, 3.0)
        t |> equal(c.ids, 5)
        t |> equal(c.ours_pass, 2)
        t |> equal(c.ours_skipped, 1)
        t |> equal(c.rust?["pass"] ?? -1, 3)
        t |> equal(c.rust?["compile"] ?? -1, 1)
        t |> equal(c.rust?["refused"] ?? -1, 1)
        t |> equal(c.rust?["timeout"] ?? -1, 0)
        t |> equal(length(c.rust), length(STATUSES))
        t |> equal(c.rust_pass_of_ours, 1)
        t |> equal(c.rust_pass_of_skipped, 1)
        t |> equal(c.rust_pass_of_unlisted, 1)
        t |> equal(length(c.outcomes), 5)
    }
}

[test]
def test_write_capture(t : T?) {
    t |> run("a run replaces its suites only: another suite and another section stay; the stamps are set") @(t : T?) {
        t |> with_stand_in("cmp_capture") $(dir, _bin) {
            let path = path_join(dir, "results.json")
            fwrite(path, "\{\"perf\": \{\"lanes\": 5\}, \"suites\": \{\"csmith\": \{\"ids\": 9\}, \"c_testsuite\": \{\"ids\": 1\}\}, \"date\": \"old\"\}")
            var entries <- {"c_testsuite" => JV(2)}
            t |> equal(write_capture(path, entries, {"date" => "new", "rust_commit" => "abc"}), "")
            var error : string
            let js = read_json(fread(path), error)
            t |> equal(error, "")
            t |> equal(js?["perf"]?["lanes"] ?? 0, 5)
            t |> equal(js?["suites"]?["csmith"]?["ids"] ?? 0, 9)
            t |> equal(js?["suites"]?["c_testsuite"] ?? 0, 2)
            t |> equal(js?["date"] ?? "", "new")
            t |> equal(js?["rust_commit"] ?? "", "abc")
        }
    }
    t |> run("a fresh file gets the section; a file that is not a JSON object is left alone") @(t : T?) {
        t |> with_stand_in("cmp_capture_new") $(dir, _bin) {
            let path = path_join(dir, "fresh.json")
            var entries <- {"csmith" => JV(4)}
            t |> equal(write_capture(path, entries, {"date" => "d"}), "")
            var error : string
            let js = read_json(fread(path), error)
            t |> equal(js?["suites"]?["csmith"] ?? 0, 4)
            let bad = path_join(dir, "bad.json")
            fwrite(bad, "[1, 2]")
            t |> success(write_capture(bad, entries, {"date" => "d"}) |> starts_with("cannot read"))
            t |> equal(fread(bad), "[1, 2]")
        }
    }
}

[test]
def test_missing_inputs(t : T?) {
    t |> run("the Rust binary first, then each suite's input; csmith's input is the built csmith") @(t : T?) {
        t |> with_stand_in("cmp_missing") $(dir, bin) {
            let present = SuiteSpec(name = "c_testsuite", tests_dir = dir)
            let absent = SuiteSpec(name = "gcc_torture", tests_dir = path_join(dir, "absent"))
            with_env(path_join(dir, "no_rust"), "") {
                t |> success(missing_inputs([present]) |> contains("run scripts/build_c2das_rust.sh"))
            }
            with_env(bin, "") {
                t |> equal(missing_inputs([present]), "")
                t |> equal(missing_inputs([present, absent]), "{path_join(dir, "absent")} is missing: run suites/gcc_torture/fetch.sh")
            }
            t |> equal(input_of(SuiteSpec(name = "csmith", tests_dir = dir)), "{CSMITH_DIR}/build/src/csmith")
            t |> equal(input_of(present), dir)
        }
    }
}
