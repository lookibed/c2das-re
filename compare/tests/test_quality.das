options gen2
// the quality worker converts in this process: the pipeline parses clang's JSON dump below its own
// frames, and a deep expression tree overflows the default 16 KB context stack
options stack = 1048576
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require daslib/json_boost
require ../../converter/tiers.das
require ../../suites/suite_runner.das
require ../suite_compare.das
require ../quality_compare.das
require _common

//! `compare/quality_compare.das` without the Rust binary: the corpus over a capture the test writes,
//! two sides measured over das files the test writes, the totals, the function extraction, the
//! section written beside the others, and a kernel measured by a worker with a stand-in translator.

// the stand-in translator: `refuse.c` is refused, any other file becomes a module defining `fibI`
// and the wrapper `main`
let STAND_IN = "#!/bin/sh\nout=\"\"\nprev=\"\"\nfor a in \"$@\"; do\n    if [ \"$prev\" = \"--output-dir\" ]; then out=\"$a\"; fi\n    prev=\"$a\"\ndone\nstem=$(basename \"$2\" .c)\ncase \"$*\" in\n    *nomain.c*) mkdir -p \"$out\"; echo 'options gen2' > \"$out/$stem.das\"; exit 0 ;;\n    *refuse.c*) echo \"translation failed: unsupported external call: ldexp\" >&2; exit 2 ;;\n    *.json*) echo \"translation failed: unsupported external call: ldexp\" >&2; exit 2 ;;\nesac\nmkdir -p \"$out\"\nprintf 'options gen2\\n\\n[export, sideeffects]\\ndef fibI(var n : int) : int \{\\n    return n\\n\}\\n[export]\\ndef main() : int \{\\n    return fibI(0)\\n\}\\nvar c2da_str_0 : int = 1\\n' > \"$out/$stem.das\"\nprintf 'options gen2\\n[sideeffects]\\ndef c2da_rt_helper() \{\\n\}\\n' > \"$out/aaa_helper.das\"\n"

// a scratch folder holding the executable stand-in `rust`, passed to `body` with its path
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
    invoke(body, dir, bin)
    rmdir_rec(dir)
}

def private json_of(t : T?; text : string) : JsonValue? {
    var error : string
    var js = read_json(text, error)
    t |> equal(error, "")
    return js
}

let CAPTURE_TEXT = "\{\"suites\": \{\"c_testsuite\": \{\"outcomes\": [\{\"id\": \"a\", \"status\": \"pass\"\}, \{\"id\": \"b\", \"status\": \"exit\"\}, \{\"id\": \"c\", \"status\": \"output\"\}, \{\"id\": \"d\", \"status\": \"compile\"\}, \{\"id\": \"e\", \"status\": \"refused\"\}, \{\"id\": \"f\", \"status\": \"pass\"\}]\}, \"csmith\": \{\"outcomes\": [\{\"id\": \"7\", \"status\": \"pass\"\}]\}, \"gcc_torture\": \{\"ids\": 3\}\}, \"perf\": \{\"kernels\": \{\"sieve\": \{\"rust\": \{\"status\": \"ran\"\}\}, \"qsort_cmp\": \{\"rust\": \{\"status\": \"refused\"\}\}, \"dasprofile/fib_loop\": \{\"rust\": \{\"status\": \"ran\"\}\}\}\}\}"

[test]
def test_corpus(t : T?) {
    t |> run("compiled Rust statuses the ratchet lists, kernels the Rust side ran, sorted, filtered") @(t : T?) {
        let results = json_of(t, CAPTURE_TEXT)
        var listed : table<string; table<string>>
        listed["c_testsuite"] <- {"a", "b", "c", "d", "e"}
        listed["gcc_torture"] <- {"x"}
        let all <- quality_corpus(results, listed, "")
        t |> equal(join(all, " "), "c_testsuite/a c_testsuite/b c_testsuite/c perf/dasprofile/fib_loop perf/sieve")
        t |> equal(join(quality_corpus(results, listed, "perf/"), " "), "perf/dasprofile/fib_loop perf/sieve")
        t |> equal(length(quality_corpus(json_of(t, "\{\}"), listed, "")), 0)
    }
    t |> run("the corpus of a capture file: the real ratchets; a file that is no JSON is an error") @(t : T?) {
        let dir = "compare/work/cmp_quality_corpus"
        mkdir_rec(dir)
        let path = path_join(dir, "results.json")
        fwrite(path, "\{\"suites\": \{\"c_testsuite\": \{\"outcomes\": [\{\"id\": \"00001\", \"status\": \"pass\"\}, \{\"id\": \"no-such-id\", \"status\": \"pass\"\}]\}\}\}")
        var error : string
        t |> equal(join(quality_corpus_of(path, "", error), " "), "c_testsuite/00001")
        t |> equal(error, "")
        fwrite(path, "[")
        t |> equal(length(quality_corpus_of(path, "", error)), 0)
        t |> success(error |> starts_with("cannot read {path}"), error)
        error = ""
        let absent = path_join(dir, "absent.json")
        t |> equal(length(quality_corpus_of(absent, "", error)), 0)
        t |> success(error |> starts_with("no capture at {absent}"), error)
        rmdir_rec(dir)
    }
}

let TWO_FUNCTIONS = "options gen2\n    \nvar private g : int = 3\n\ndef private f : int? \{\n    return unsafe(addr(g))\n\}\n\n[export]\ndef main() : int \{\n    var i = 0\n    while (i < 5) \{\n        i++\n    \}\n    return i\n\}\n"

[test]
def test_measure_side(t : T?) {
    t |> run("files, non-blank lines and the counters; a module that does not compile is `compile`") @(t : T?) {
        let dir = "compare/work/cmp_quality_side"
        mkdir_rec(dir)
        let good = path_join(dir, "good.das")
        let helper = path_join(dir, "helper.das")
        fwrite(good, TWO_FUNCTIONS)
        fwrite(helper, "options gen2\n\n\ndef helper() \{\n\}\n")
        t |> equal(nonblank_lines(TWO_FUNCTIONS), 13)
        let side <- measure_side([good, helper], good)
        t |> equal(side.status, "ok", side.error)
        t |> equal(side.files, 2)
        t |> equal(side.lines, 16)
        t |> equal(side.counts?["unsafe_expr"] ?? -1, 1)
        t |> equal(side.counts?["while_rangeable"] ?? -1, 1)
        t |> equal(side.counts?["c_function"] ?? -1, 0)
        let bad = path_join(dir, "bad.das")
        fwrite(bad, "options gen2\ndef main() : int \{\n    return int16 const(1)\n\}\n")
        let broken <- measure_side([bad], bad)
        t |> equal(broken.status, "compile")
        t |> success(!empty(broken.error), broken.error)
        rmdir_rec(dir)
    }
}

// a side with `lines` lines, one file and `unsafe_expr` sites
def private side_of(status : string; lines, unsafe_sites : int) : SideQuality {
    var side = SideQuality(status = status, files = 1, lines = lines)
    side.counts["unsafe_expr"] = unsafe_sites
    return <- side
}

[test]
def test_totals(t : T?) {
    t |> run("summed over the keys both sides measured, per group and over all, the rest excluded") @(t : T?) {
        var entries <- {"c_testsuite/a" => KeyQuality(ours <- side_of("ok", 10, 1), rust <- side_of("ok", 30, 4)), "c_testsuite/c" => KeyQuality(ours <- side_of("ok", 5, 2), rust <- side_of("ok", 6, 1)), "c_testsuite/b" => KeyQuality(ours <- side_of("ok", 20, 2), rust <- side_of("compile", 50, 9)), "perf/k" => KeyQuality(ours <- side_of("convert", 0, 0), rust <- side_of("ok", 5, 1))}
        entries |> get("c_testsuite/a") $(var q) {
            q.rust.runtime_lines = 15
        }
        entries |> get("c_testsuite/c") $(var q) {
            q.rust.runtime_lines = 3
        }
        let totals = quality_totals(entries)
        let all = totals?["all"]
        t |> equal(all?["keys"] ?? 0, 4)
        t |> equal(all?["counted"] ?? 0, 2)
        t |> equal(all?["excluded"]?["rust_compile"] ?? 0, 1)
        t |> equal(all?["excluded"]?["ours_convert"] ?? 0, 1)
        t |> equal(all?["ours"]?["lines"] ?? 0, 15)
        t |> equal(all?["rust"]?["lines"] ?? 0, 36)
        t |> equal(all?["rust"]?["files"] ?? 0, 2)
        t |> equal(all?["rust"]?["unsafe_expr"] ?? 0, 5)
        t |> equal(all?["ours"]?["goto"] ?? -1, 0)
        t |> equal(all?["line_ratio"] ?? 0.0lf, 36.0lf / 15.0lf)
        t |> equal(all?["rust"]?["runtime_lines"] ?? 0, 18)
        t |> equal(all?["program_line_ratio"] ?? 0.0lf, 18.0lf / 15.0lf)
        t |> equal(totals?["c_testsuite"]?["keys"] ?? 0, 3)
        t |> equal(totals?["perf"]?["program_line_ratio"] ?? -1.0lf, 0.0lf)
        t |> equal(totals?["perf"]?["counted"] ?? -1, 0)
        t |> equal(totals?["perf"]?["line_ratio"] ?? -1.0lf, 0.0lf)
    }
}

let MODULE_TEXT = "options gen2\n\nvar first : int\ndef first(a : int) : int \{\n    return a\n\}\n\n[export, sideeffects]\ndef private fib_loop__middle \{\n    first(1)\n\}\n\ndef helper_middle() => 1\n\n[c_function]\ndef c_main : int \{\n    return 0\n\}\n\ndef main_0() : int \{\n    return 0\n\}\n\ndef last() : int \{\n    return 2\n"

[test]
def test_function_text(t : T?) {
    t |> run("the first, a middle one with its annotation, a one-line one, the last without its brace") @(t : T?) {
        t |> equal(function_text(MODULE_TEXT, "first", "rust"), "def first(a : int) : int \{\n    return a\n\}")
        t |> equal(function_text(MODULE_TEXT, "middle", "ours"), "[export, sideeffects]\ndef private fib_loop__middle \{\n    first(1)\n\}")
        t |> equal(function_text(MODULE_TEXT, "helper_middle", "rust"), "def helper_middle() => 1")
        t |> equal(function_text(MODULE_TEXT, "last", "rust"), "def last() : int \{\n    return 2\n")
    }
    t |> run("C's main as each side names it; a missing name is empty") @(t : T?) {
        t |> equal(function_text(MODULE_TEXT, "main", "ours"), "[c_function]\ndef c_main : int \{\n    return 0\n\}")
        t |> equal(function_text(MODULE_TEXT, "main", "rust"), "def main_0() : int \{\n    return 0\n\}")
        t |> equal(function_text(MODULE_TEXT, "absent", "ours"), "")
        t |> equal(declared_name("def public x(y : int)"), "x")
        t |> equal(declared_name("struct private c2da_s \{"), "c2da_s")
        t |> equal(declared_name("    def x()"), "")
        t |> equal(declared_name("require strings"), "")
        t |> success(!is_c_function("main_0", "main", "ours") && !is_c_function("xmiddle", "middle", "ours"))
        t |> success(is_c_function("fib_loop__middle", "middle", "ours") && !is_c_function("fib_loop__middle", "middle", "rust"))
    }
}

[test]
def test_key_results(t : T?) {
    t |> run("a worker's result read back; none is a crash, a killed worker a timeout") @(t : T?) {
        let key = "perf/cmp_quality_result"
        mkdir_rec(quality_work(key))
        var q <- KeyQuality(ours <- side_of("ok", 3, 1), rust <- side_of("compile", 4, 0))
        q.functions |> push(FunctionPair(key = key, name = "f", ours = "def f \{\n\}", rust = ""))
        fwrite(quality_result_path(key), sprint_json(q, false))
        let back <- read_key_quality(key, false, 0)
        t |> equal(back.ours.lines, 3)
        t |> equal(back.rust.status, "compile")
        t |> equal(back.functions[0].ours, "def f \{\n\}")
        let killed <- read_key_quality(key, true, 9)
        t |> equal(killed.ours.status, "timeout")
        t |> equal(killed.rust.status, "timeout")
        rmdir_rec(quality_work(key))
        mkdir_rec(quality_work(key))
        fwrite(quality_result_path(key), "not json")
        t |> equal(read_key_quality(key, false, 0).ours.status, "crash")
        rmdir_rec(quality_work(key))
        let crashed <- read_key_quality(key, false, 3)
        t |> equal(crashed.ours.status, "crash")
        t |> equal(crashed.rust.error, "the worker exited 3 with no result")
    }
}

[test]
def test_section_capture(t : T?) {
    t |> run("the quality section replaces the old one and keeps suites and perf") @(t : T?) {
        let dir = "compare/work/cmp_quality_capture"
        mkdir_rec(dir)
        let path = path_join(dir, "results.json")
        fwrite(path, "\{\"suites\": \{\"csmith\": \{\"ids\": 9\}\}, \"perf\": \{\"samples\": 5\}, \"quality\": \{\"old\": 1\}\}")
        var entries : table<string; KeyQuality>
        var q <- KeyQuality(ours <- side_of("ok", 3, 1), rust <- side_of("ok", 6, 2))
        q.functions |> push(FunctionPair(key = "perf/sieve", name = "kernel_run", ours = "o", rust = "r"))
        entries["perf/sieve"] <- q
        var other <- KeyQuality(ours <- side_of("ok", 1, 0), rust <- side_of("ok", 1, 0))
        other.functions |> push(FunctionPair(key = "perf/other", name = "unsampled", ours = "x", rust = "y"))
        entries["perf/other"] <- other
        var fib <- KeyQuality(ours <- side_of("ok", 1, 0), rust <- side_of("ok", 1, 0))
        fib.functions |> push(FunctionPair(key = "perf/fib_loop", name = "fibI", ours = "f", rust = "g"))
        entries["perf/fib_loop"] <- fib
        var section = quality_section(Stamps(rust_commit = "abc", date = "today"), entries)
        t |> equal(write_capture_section(path, "quality", section), "")
        let js = json_of(t, fread(path))
        t |> equal(js?["suites"]?["csmith"]?["ids"] ?? 0, 9)
        t |> equal(js?["perf"]?["samples"] ?? 0, 5)
        t |> equal(js?["quality"]?["old"] ?? 0, 0)
        t |> equal(js?["quality"]?["rust_commit"] ?? "", "abc")
        t |> equal(js?["quality"]?["keys"]?["perf/sieve"]?["rust"]?["lines"] ?? 0, 6)
        t |> equal(js?["quality"]?["totals"]?["perf"]?["counted"] ?? 0, 3)
        t |> equal(js?["quality"]?["functions"]?[0]?["rust"] ?? "", "g")
        t |> equal(js?["quality"]?["functions"]?[1]?["rust"] ?? "", "r")
        t |> equal(js?["quality"]?["functions"]?[2] ?? "none", "none")
        rmdir_rec(dir)
    }
}

[test]
def test_worker(t : T?) {
    t |> run("a sampled kernel measured in a scratch root: our conversion, the stand-in's module, the functions") @(t : T?) {
        t |> with_stand_in("cmp_quality_worker") $(dir, bin) {
            let stale = path_join(dir, "perf/fib_loop/rust/extra.das")
            mkdir_rec(path_join(dir, "perf/fib_loop/rust"))
            fwrite(stale, "options gen2\n")
            let q <- measure_key("perf/fib_loop", bin, dir)
            t |> success(!fexist(stale))
            t |> equal(q.rust.files, 2)
            t |> equal(q.ours.status, "ok", q.ours.error)
            t |> equal(q.ours.counts?["c_function"] ?? 0, 1)
            t |> equal(q.rust.status, "ok", q.rust.error)
            t |> equal(q.rust.lines, 10 + 4)
            t |> equal(q.rust_c2da?["c2da_str_0"] ?? 0, 1)
            t |> equal(q.rust_c2da?["c2da_rt_helper"] ?? 0, 3)
            t |> equal(join([for (f in q.functions); f.name], " "), "fibI kernel_run")
            t |> success(q.functions[0].ours |> starts_with("def private fib_loop__fibI("), q.functions[0].ours)
            t |> equal(q.functions[0].rust, "[export, sideeffects]\ndef fibI(var n : int) : int \{\n    return n\n\}")
            t |> equal(q.functions[1].rust, "")
            t |> success(fexist(path_join(dir, "perf/fib_loop/quality.json")))
        }
    }
    t |> run("a key through a worker process: a kernel no folder has") @(t : T?) {
        t |> with_stand_in("cmp_quality_driver") $(dir, bin) {
            with_env(bin, "") {
                let entries <- drive_quality(["perf/cmp_test_no_kernel"], 1)
                entries |> get("perf/cmp_test_no_kernel") $(q) {
                    t |> equal(q.ours.status, "convert")
                    t |> equal(q.rust.error, "no input is keyed perf/cmp_test_no_kernel")
                }
                t |> equal(length(entries), 1)
            }
            rmdir_rec(quality_work("perf/cmp_test_no_kernel"))
        }
    }
    t |> run("a suite case's file by its id, a refused translation, a csmith seed csmith refuses") @(t : T?) {
        t |> with_stand_in("cmp_quality_sources") $(dir, bin) {
            var args : array<string>
            var error : string
            t |> equal(quality_source("c_testsuite/00001", dir, args, error, dir), "{C_TESTSUITE_TESTS}/00001.c")
            t |> equal(quality_source("gcc_torture/x", dir, args, error, dir), "{GCC_TORTURE_TESTS}/x.c")
            t |> equal(error, "")
            quality_source("csmith/not-a-seed", path_join(dir, "gen"), args, error, dir)
            t |> success(!empty(error))
            t |> equal(length(args), 0)
            error = ""
            let cached = path_join(dir, "cache/42/42.c")
            mkdir_rec(path_join(dir, "cache/42"))
            fwrite(cached, "int main(void) \{ return 0; \}\n")
            t |> equal(quality_source("csmith/42", path_join(dir, "gen"), args, error, path_join(dir, "cache")), cached)
            t |> equal(error, "")
            t |> success(csmith_error(CsmithProgram(timed_out = true)) |> starts_with("csmith took longer than "))
            t |> equal(csmith_error(CsmithProgram(error = "refused")), "refused")
            t |> equal(quality_source("other/fib_loop", path_join(dir, "k1"), args, error, dir), "")
            t |> equal(error, "no input is keyed other/fib_loop")
            t |> equal(length(args), 0)
            error = ""
            t |> success(quality_source("perf/fib_loop", path_join(dir, "k2"), args, error, dir) |> ends_with("fib_loop.c"))
            t |> equal(join(args, " "), METHOD_NATIVE_DEFINE)
            t |> equal(quality_translate_timeout("perf/fib_loop"), 600.0)
            t |> equal(quality_translate_timeout("c_testsuite/00001"), 300.0)
            let specs <- [SuiteSpec(name = "c_testsuite", tests_dir = path_join(dir, "absent"))]
            t |> equal(quality_missing(["perf/fib_loop"], specs), "")
            t |> equal(quality_missing(["c_testsuite/00001"], specs), "{path_join(dir, "absent")} is missing: run suites/c_testsuite/fetch.sh")
            let asm_c = path_join(dir, "asm.c")
            fwrite(asm_c, "int main(void) \{ __asm__(\"nop\"); return 0; \}\n")
            var das_path : string
            let ours <- ours_quality(asm_c, path_join(dir, "asm_out"), das_path)
            t |> equal(ours.status, "convert")
            t |> success(!empty(ours.error), ours.error)
            t |> equal(das_path, "")
            args |> clear()
            let refused = path_join(dir, "refuse.c")
            fwrite(refused, "int main(void) \{ return 0; \}\n")
            var entry : string
            var c2da : table<string; int>
            let side <- rust_quality(bin, refused, path_join(dir, "out"), args, 30.0, entry, c2da)
            t |> equal(side.status, "refused")
            t |> equal(side.error, "translation failed: unsupported external call: ldexp")
            let nomain = path_join(dir, "nomain.c")
            fwrite(nomain, "int f(void) \{ return 0; \}\n")
            let no_entry <- rust_quality(bin, nomain, path_join(dir, "out2"), args, 30.0, entry, c2da)
            t |> equal(no_entry.status, "refused")
            t |> success(no_entry.error |> ends_with("defines main"), no_entry.error)
            t |> equal(entry, "")
        }
    }
}

// `compare/run.das` run from the repository root with `args` after `--`; its exit code
def private run_compare(args : array<string>; var out : string&) : int {
    var argv <- daslang_cmd(CONVERTED_MODULES)
    argv |> push_from(["compare/run.das", "--"], args)
    return run_and_capture(argv, out, 300.0)
}

[test]
def test_quality_command_line(t : T?) {
    t |> run("--quality and --lua run alone; without the Rust translator they exit 2; a bad capture exits 1") @(t : T?) {
        var out : string
        t |> equal(run_compare(["--quality", "--lua"], out), 1, out)
        t |> success(out |> contains("--quality runs alone"), out)
        with_env("/nonexistent/c2das-rust", "") {
            t |> equal(run_compare(["--quality"], out), 2, out)
            t |> success(out |> contains("no Rust translator at /nonexistent/c2das-rust"), out)
        }
        t |> with_stand_in("cmp_quality_cli") $(dir, bin) {
            let bad = path_join(dir, "bad.json")
            fwrite(bad, "[")
            with_env(bin, "") {
                t |> equal(run_compare(["--quality", "--out", bad], out), 1, out)
                t |> success(out |> contains("cannot read {bad}"), out)
                t |> success(!(out |> contains("keys counted")), out)
            }
        }
    }
    t |> run("--quality over a one-kernel capture writes quality and keeps the rest; no --out reads the committed one") @(t : T?) {
        t |> with_stand_in("cmp_quality_run") $(dir, bin) {
            let results = path_join(dir, "results.json")
            fwrite(results, "\{\"suites\": \{\}, \"perf\": \{\"samples\": 5, \"kernels\": \{\"dasprofile/fib_loop\": \{\"rust\": \{\"status\": \"ran\"\}\}\}\}, \"lua\": \{\"status\": \"refused\"\}, \"doom\": \{\"status\": \"pending\"\}\}")
            var out : string
            var argv <- ["env", "DAS_LOG_LEVEL=info"]
            argv |> push_from(daslang_cmd(CONVERTED_MODULES), ["compare/run.das", "--", "--quality", "--out", results, "--jobs", "1"])
            with_env(bin, "") {
                t |> equal(run_and_capture(argv, out, 900.0), 0, out)
            }
            let js = json_of(t, fread(results))
            t |> equal(js?["quality"]?["keys"]?["perf/dasprofile/fib_loop"]?["rust"]?["status"] ?? "", "ok")
            t |> equal(js?["perf"]?["samples"] ?? 0, 5)
            t |> equal(js?["lua"]?["status"] ?? "", "refused")
            t |> equal(js?["doom"]?["status"] ?? "", "pending")
            t |> success(js?["suites"] != null)
            let committed = fread(CAPTURE)
            var filtered <- ["env", "DAS_LOG_LEVEL=info"]
            filtered |> push_from(daslang_cmd(CONVERTED_MODULES), ["compare/run.das", "--", "--quality", "--filter", "perf/sieve", "--jobs", "1"])
            with_env(bin, "") {
                t |> equal(run_and_capture(filtered, out, 900.0), 0, out)
            }
            t |> success(out |> contains("all: 1 of 1 keys counted"), out)
            t |> equal(fread(CAPTURE), committed)
            rmdir_rec(quality_work("perf/dasprofile/fib_loop"))
            rmdir_rec(quality_work("perf/sieve"))
        }
    }
}

let RUNTIME_MODULE = "options gen2\n\nvar c2da_rt_heap : array<uint8>\n\ndef program_first() : int \{\n    return 1\n\}\n\n[sideeffects]\ndef c2da_std_helper(x : int) : int \{\n\n    return x\n\}\ntypedef clockid_t = int\nvar c2da_str_0 : array<uint8>\n[export, sideeffects]\ndef program_second() : int \{\n    return 2\n\}\n[sideeffects]\ndef c2da_clip_uint() \{\n    pass\n\}\n"

[test]
def test_runtime_lines(t : T?) {
    t |> run("each c2da_ declaration's lines, from its annotation to the next declaration, a typedef one") @(t : T?) {
        let blocks <- c2da_blocks(RUNTIME_MODULE)
        t |> equal(blocks?["c2da_rt_heap"] ?? 0, 1)
        t |> equal(blocks?["c2da_std_helper"] ?? 0, 4)
        t |> equal(blocks?["c2da_str_0"] ?? 0, 1)
        t |> equal(blocks?["c2da_clip_uint"] ?? 0, 4)
        t |> equal(length(blocks), 4)
        t |> equal(length(c2da_blocks("options gen2\n\ndef program() \{\n\}\n")), 0)
        t |> equal(length(c2da_blocks("")), 0)
        t |> equal(c2da_blocks("def c2da_x() \{\n\}\n[export]")?["c2da_x"] ?? 0, 3)
    }
    t |> run("runtime: the heap and libc prefixes and a name every module has; the rest program code") @(t : T?) {
        var entries <- {"a" => KeyQuality(rust <- SideQuality(status = "ok"), rust_c2da <- {"c2da_rt_heap" => 1, "c2da_clip_uint" => 4, "c2da_str_0" => 2, "c2da_layout_proofs" => 3}), "b" => KeyQuality(rust <- SideQuality(status = "ok"), rust_c2da <- {"c2da_clip_uint" => 4, "c2da_ginit_g_1" => 5}), "c" => KeyQuality(rust <- SideQuality(status = "compile"), rust_c2da <- {"c2da_std_printf" => 7, "c2da_clip_uint" => 1})}
        split_runtime(entries)
        entries |> get("a") $(q) {
            t |> equal(q.rust.runtime_lines, 5)
            t |> equal(q.rust.program_c2da_lines, 5)
        }
        entries |> get("b") $(q) {
            t |> equal(q.rust.runtime_lines, 4)
            t |> equal(q.rust.program_c2da_lines, 5)
        }
        entries |> get("c") $(q) {
            t |> equal(q.rust.runtime_lines, 8)
        }
        let none : table<string>
        t |> success(is_runtime("c2da_std_x", none) && is_runtime("c2da_rt_y", none) && !is_runtime("c2da_str_1", none))
    }
}
