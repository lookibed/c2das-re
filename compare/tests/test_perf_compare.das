options gen2
require dastest/testing_boost public
require math
require strings
require daslib/fio
require daslib/strings_boost
require daslib/json_boost
require ../../perf/perf_compose.das
require ../../perf/perf_lanes.das
require ../../perf/perf_measure.das
require ../rust_translator.das
require ../suite_compare.das
require ../perf_compare.das
require ../../converter/tiers.das
require _common

//! `compare/perf_compare.das` without the Rust binary: the composition over a kernel folder the
//! test writes, the geometric means over hand-written cells, the capture's `perf` section, the Rust
//! side of a refused or failed translation, and one lane timed on the real daslang over a das
//! program that prints a kernel's line.

// a scratch folder passed to `body` and removed after it; a failure when none can be made
def private with_scratch(t : T?; name : string; body : block<(dir : string) : void>) {
    var dir_error : string
    let dir = create_temp_directory(name, dir_error)
    if (!empty(dir_error)) {
        t |> failure("no scratch folder: {dir_error}")
        return
    }
    invoke(body, dir)
    rmdir_rec(dir)
}

// a JSON text read back, a failure when it is not JSON
def private json_of(t : T?; text : string) : JsonValue? {
    var error : string
    var js = read_json(text, error)
    t |> equal(error, "")
    return js
}

[test]
def test_kernels_and_composition(t : T?) {
    t |> run("both kernel folders, the method ones keyed under dasprofile/, a filter on the key") @(t : T?) {
        let all <- perf_kernels("")
        let keys <- [for (k in all); k.key]
        t |> success(has_value(keys, "fib_loop") && has_value(keys, "dasprofile/fib_loop"), join(keys, " "))
        t |> equal(length(all), length(kernel_ids("default", "")) + length(kernel_ids("dasprofile", "")))
        let method <- perf_kernels("dasprofile/")
        t |> equal(join([for (k in method); "{k.key}={k.dir}/{k.name}"], " "), "dasprofile/fib_loop=perf/kernels/dasprofile/fib_loop dasprofile/fib_recursive=perf/kernels/dasprofile/fib_recursive dasprofile/primes=perf/kernels/dasprofile/primes")
    }
    t |> run("a kernel of any folder composed by the method, its work folder created") @(t : T?) {
        t |> with_scratch("cmp_perf_compose") $(dir) {
            let kernel = "static void kernel_run(void) \{\}\nstatic int kernel_result(void) \{ return 4; \}\n"
            fwrite(path_join(dir, "tiny.c"), kernel)
            let work = path_join(dir, "w/tiny")
            let c_path = write_method_composed(dir, "tiny", work)
            t |> equal(c_path, path_join(work, "tiny.c"))
            t |> equal(fread(c_path), composed_method_source(kernel))
        }
    }
}

let GEOMEAN_KERNELS = "\{\"a\": \{\"native\": \{\"time\": 1.0\}, \"ours\": \{\"jit\": \{\"time\": 2.0\}\}, \"rust\": \{\"lanes\": \{\"jit\": \{\"time\": 1.0\}\}\}\}, \"b\": \{\"native\": \{\"time\": 0.5\}, \"ours\": \{\"jit\": \{\"time\": 4.0\}, \"aot\": \{\"time\": 1.0\}\}, \"rust\": \{\"lanes\": \{\"jit\": \{\"time\": 2.0\}, \"aot\": \{\"error\": \"not built\"\}\}\}\}, \"c\": \{\"native\": \{\"error\": \"exited 1\"\}, \"ours\": \{\"jit\": \{\"time\": 9.0\}\}, \"rust\": \{\"lanes\": \{\"jit\": \{\"time\": 9.0\}\}\}\}, \"d\": \{\"native\": \{\"time\": 1.0\}, \"ours\": \{\"jit\": \{\"time\": 9.0\}\}, \"rust\": \{\"status\": \"refused\", \"error\": \"translation failed: x\"\}\}, \"e\": \{\"native\": \{\"time\": 1.0\}, \"ours\": \{\"jit\": \{\"error\": \"exited 1\"\}\}, \"rust\": \{\"lanes\": \{\"jit\": \{\"time\": 3.0\}\}\}\}\}"

[test]
def test_geomean(t : T?) {
    t |> run("over the kernels where native and both sides stand, each a ratio to native") @(t : T?) {
        let kernels = json_of(t, GEOMEAN_KERNELS)
        var ours, rust : double
        var count : int
        lane_geomean(kernels, "jit", ours, rust, count)
        t |> equal(count, 2)
        t |> success(abs(ours - 4.0lf) < 1e-9lf, "ours {ours}")
        t |> success(abs(rust - 2.0lf) < 1e-9lf, "rust {rust}")
    }
    t |> run("a lane one side lacks everywhere, and no kernels at all, give no mean") @(t : T?) {
        let kernels = json_of(t, GEOMEAN_KERNELS)
        var ours, rust : double
        var count : int
        lane_geomean(kernels, "aot", ours, rust, count)
        t |> equal(count, 0)
        t |> equal(ours, 0.0lf)
        t |> equal(rust, 0.0lf)
        lane_geomean(null, "jit", ours, rust, count)
        t |> equal(count, 0)
        lane_geomean(JV(1), "jit", ours, rust, count)
        t |> equal(count, 0)
        t |> equal(ours, 0.0lf)
        t |> equal(rust, 0.0lf)
        var by_lane = geomeans(kernels)
        t |> equal(by_lane?["jit"]?["kernels"] ?? 0, 2)
        t |> equal(by_lane?["interp"]?["kernels"] ?? -1, 0)
        let lines <- geomean_lines(JV({"geomean" => by_lane}))
        t |> equal(length(lines), length(DAS_LANES))
        t |> equal(lines[1], "jit: ours 4.000, rust 2.000 times native over 2 kernels")
    }
}

[test]
def test_perf_section_capture(t : T?) {
    t |> run("the perf section replaces the old one whole and keeps suites") @(t : T?) {
        t |> with_scratch("cmp_perf_capture") $(dir) {
            let path = path_join(dir, "results.json")
            fwrite(path, "\{\"suites\": \{\"csmith\": \{\"ids\": 9\}\}, \"perf\": \{\"kernels\": \{\"old\": 1\}, \"samples\": 3\}\}")
            var kernels : table<string; JsonValue?>
            kernels["k"] = JV(1)
            let stamps = Stamps(rust_commit = "abc", daslang = "daslang 0.6", date = "2026-11-01 00:00 UTC", cpu = "C", box = "bench")
            var section = perf_section(stamps, 5, kernels)
            t |> equal(write_capture_section(path, "perf", section), "")
            let js = json_of(t, fread(path))
            t |> equal(js?["suites"]?["csmith"]?["ids"] ?? 0, 9)
            t |> equal(js?["perf"]?["kernels"]?["old"] ?? 0, 0)
            t |> equal(js?["perf"]?["kernels"]?["k"] ?? 0, 1)
            t |> equal(js?["perf"]?["samples"] ?? 0, 5)
            t |> equal(js?["perf"]?["rust_commit"] ?? "", "abc")
            t |> equal(js?["perf"]?["timestamp"] ?? "", "2026-11-01 00:00 UTC")
            t |> success(!empty(js?["perf"]?["versions"]?["clang"] ?? ""))
            t |> equal(js?["perf"]?["cpu"] ?? "", "C")
            t |> equal(js?["perf"]?["box"] ?? "", "bench")
            let lanes = js?["perf"]?["lanes"]
            t |> equal(lanes?[0] ?? "", "native")
            t |> equal(lanes?[4] ?? "", "aot")
            t |> equal(js?["perf"]?["geomean"]?["jit"]?["kernels"] ?? -1, 0)
        }
    }
    t |> run("a fresh file gets the section; a file that is no JSON object is left alone") @(t : T?) {
        t |> with_scratch("cmp_perf_capture_new") $(dir) {
            let fresh = path_join(dir, "fresh.json")
            t |> equal(write_capture_section(fresh, "perf", JV(7)), "")
            t |> equal(json_of(t, fread(fresh))?["perf"] ?? 0, 7)
            let bad = path_join(dir, "bad.json")
            fwrite(bad, "[1]")
            t |> success(write_capture_section(bad, "perf", JV(7)) |> starts_with("cannot read"))
            t |> equal(fread(bad), "[1]")
        }
    }
    t |> run("a filtered run writes nothing; a capture that cannot be read exits 1") @(t : T?) {
        t |> with_scratch("cmp_perf_record") $(dir) {
            let path = path_join(dir, "out.json")
            t |> equal(record_run(path, "fib") $(p) => write_capture_section(p, "perf", JV(1)), 0)
            t |> success(!fexist(path))
            fwrite(path, "nope")
            t |> equal(record_run(path, "") $(p) => write_capture_section(p, "perf", JV(1)), 1)
            t |> equal(fread(path), "nope")
        }
    }
}

[test]
def test_lane_entries(t : T?) {
    t |> run("a cell stands as perf writes it; a lane without one is \{error\}, its own line first") @(t : T?) {
        var inscope cells : table<string; Cell>
        cells["interp"] <- cell_of([0.5lf, 1.0lf, 2.0lf], 10l, 3)
        let errors <- ["rust/jit: exited 1: boom", "rust/convert: unsupported", "other/exe: elsewhere", "rust/aot: the build exited 1 and left no binary: ld"]
        let entries = JV(lane_entries(cells, errors, "rust", DAS_LANES))
        let interp = entries?["interp"]
        t |> equal(interp?["time"] ?? 0.0lf, 1.0lf)
        t |> equal(interp?["spread"] ?? 0.0lf, 0.75lf)
        t |> equal(interp?["count"] ?? 0, 10)
        t |> equal(interp?["result"] ?? 0, 3)
        t |> equal(interp?["samples"]?[2] ?? 0.0lf, 2.0lf)
        t |> equal(entries?["jit"]?["error"] ?? "", "exited 1: boom")
        t |> equal(entries?["exe"]?["error"] ?? "", "convert: unsupported")
        t |> equal(entries?["aot"]?["error"] ?? "", "the build exited 1 and left no binary: ld")
        t |> equal(lane_error(errors, "nobody", "aot"), "not measured")
        let failed = JV(failed_lanes("no native result: exited 1"))
        t |> equal(join([for (lane in DAS_LANES); failed?[lane]?["error"] ?? ""], "|"), "no native result: exited 1|no native result: exited 1|no native result: exited 1|no native result: exited 1")
    }
}

[test]
def test_rust_entry(t : T?) {
    t |> run("a refused translation is refused with its error and no lanes") @(t : T?) {
        let refused = RustTranslation(ok = false, error = "translation failed: unsupported external call: qsort", exit_code = 2)
        let entry = rust_entry(refused, "unused", 1, 0, "")
        t |> equal(entry?["status"] ?? "", "refused")
        t |> equal(entry?["error"] ?? "", "translation failed: unsupported external call: qsort")
        t |> success(!key_exists(entry.value as _object, "lanes"))
        let no_main = RustTranslation(ok = true, out_dir = "o")
        let none = rust_entry(no_main, "unused", 1, 0, "")
        t |> equal(none?["status"] ?? "", "refused")
        t |> equal(none?["error"] ?? "", "the translation defines no main in o")
    }
    t |> run("a translation that ran without an oracle carries the reason on every lane") @(t : T?) {
        let ran = RustTranslation(ok = true, entry = "o/k.das", out_dir = "o")
        let entry = rust_entry(ran, "unused", 1, 0, "no native result: exited 1")
        t |> equal(entry?["status"] ?? "", "ran")
        t |> equal(entry?["lanes"]?["aot"]?["error"] ?? "", "no native result: exited 1")
        t |> equal(entry?["lanes"]?["interp"]?["error"] ?? "", "no native result: exited 1")
    }
}

// a das program that prints a kernel's line, `<seconds> <runs> <result>`
let KERNEL_LINE_DAS = "options gen2\n[export]\ndef main() : int \{\n    print(\"0.001000000 10 7\\n\")\n    return 0\n\}\n"

[test]
def test_lane_against_oracle(t : T?) {
    t |> run("a lane whose result is the oracle's stands; another result is an error cell") @(t : T?) {
        t |> with_scratch("cmp_perf_lane") $(dir) {
            let das_path = path_join(dir, "k.das")
            fwrite(das_path, KERNEL_LINE_DAS)
            let no_modules : array<string>
            let argv <- das_lane_command(das_path, "", no_modules)
            var inscope cells : table<string; Cell>
            var errors : array<string>
            measure_lane(cells, errors, "rust", "interp", argv, 1, 7)
            let matching = JV(lane_entries(cells, errors, "rust", ["interp"]))
            t |> equal(matching?["interp"]?["time"] ?? 0.0lf, 0.001lf)
            t |> equal(matching?["interp"]?["result"] ?? 0, 7)
            var inscope wrong_cells : table<string; Cell>
            var wrong_errors : array<string>
            measure_lane(wrong_cells, wrong_errors, "rust", "interp", argv, 1, 8)
            let wrong = JV(lane_entries(wrong_cells, wrong_errors, "rust", ["interp"]))
            t |> equal(wrong?["interp"]?["error"] ?? "", "result 7 differs from the native 8")
            t |> equal(wrong?["interp"]?["time"] ?? -1.0lf, -1.0lf)
        }
    }
}

[test]
def test_kernel_line(t : T?) {
    t |> run("the log line: native, our lanes, then the Rust lanes or why it did not run") @(t : T?) {
        let ran = json_of(t, "\{\"native\": \{\"time\": 0.5\}, \"ours\": \{\"interp\": \{\"time\": 1.0\}, \"jit\": \{\"error\": \"x\"\}\}, \"rust\": \{\"status\": \"ran\", \"lanes\": \{\"aot\": \{\"time\": 0.25\}\}\}\}")
        t |> equal(kernel_line("k", ran), "k: native 0.500000s; ours interp 1.000000s, jit error, exe error, aot error; rust interp error, jit error, exe error, aot 0.250000s")
        let refused = json_of(t, "\{\"native\": \{\"error\": \"exited 1\"\}, \"ours\": \{\}, \"rust\": \{\"status\": \"refused\", \"error\": \"translation failed: y\"\}\}")
        t |> equal(kernel_line("k", refused), "k: native error; ours interp error, jit error, exe error, aot error; rust refused: translation failed: y")
    }
}

// a stand-in Rust translator: it writes the module `<stem>.das` defining `main` into its output folder
let STAND_IN = "#!/bin/sh\nout=\"\"\nprev=\"\"\nfor a in \"$@\"; do\n    if [ \"$prev\" = \"--output-dir\" ]; then out=\"$a\"; fi\n    prev=\"$a\"\ndone\nstem=$(basename \"$2\" .c)\necho \"c2dascript-transpile v0.1.0\" >&2\nmkdir -p \"$out\"\nprintf '[export]\\ndef main() : int \{\\n    return 0\\n\}\\n' > \"$out/$stem.das\"\n"

[test]
def test_compare_kernel_without_oracle(t : T?) {
    t |> run("a kernel the native build refuses: native is its error, and every lane of both sides says so") @(t : T?) {
        t |> with_scratch("cmp_perf_kernel") $(dir) {
            fwrite(path_join(dir, "cmp_broken.c"), "static void kernel_run(void) \{ this is not C \}\n")
            let bin = path_join(dir, "rust")
            fwrite(bin, STAND_IN)
            var out : string
            run_and_capture(["chmod", "+x", bin], out, 30.0)
            let entry = compare_kernel(PerfKernel(key = "cmp_test/cmp_broken", name = "cmp_broken", dir = dir), bin, 1)
            let native_error = entry?["native"]?["error"] ?? ""
            t |> success(!empty(native_error), "the native build failed")
            t |> equal(entry?["native"]?["time"] ?? -1.0lf, -1.0lf)
            t |> equal(entry?["ours"]?["interp"]?["error"] ?? "", "no native result: {native_error}")
            t |> equal(entry?["rust"]?["status"] ?? "", "ran")
            t |> equal(entry?["rust"]?["lanes"]?["exe"]?["error"] ?? "", "no native result: {native_error}")
            t |> success(fexist("compare/work/perf/cmp_test/cmp_broken/cmp_broken.c"))
            rmdir_rec("compare/work/perf/cmp_test")
        }
    }
}

// a stand-in Rust translator that writes, as its translation of `<stem>.c`, the das program beside
// it, `<stem>.das.src`
let COPYING_STAND_IN = "#!/bin/sh\nout=\"\"\nprev=\"\"\nfor a in \"$@\"; do\n    if [ \"$prev\" = \"--output-dir\" ]; then out=\"$a\"; fi\n    prev=\"$a\"\ndone\nstem=$(basename \"$2\" .c)\nmkdir -p \"$out\"\ncp \"$(dirname \"$0\")/$stem.das.src\" \"$out/$stem.das\"\n"

[test]
def test_compare_kernel(t : T?) {
    t |> run("a kernel through native, our four lanes and the Rust side's four, one sample each") @(t : T?) {
        t |> with_scratch("cmp_perf_kernel_ran") $(dir) {
            fwrite(path_join(dir, "cmp_tiny.c"), "static volatile int n = 1000;\nstatic int sum;\nstatic void kernel_run(void) \{ sum = 0; for (int i = 0; i < n; i++) sum += i & 3; sum = sum / 375; \}\nstatic int kernel_result(void) \{ return sum; \}\n")
            fwrite(path_join(dir, "cmp_tiny.das.src"), "options gen2\n[export]\ndef main() : int \{\n    print(\"0.000001000 10 4\\n\")\n    return 0\n\}\n")
            let bin = path_join(dir, "rust")
            fwrite(bin, COPYING_STAND_IN)
            var out : string
            run_and_capture(["chmod", "+x", bin], out, 30.0)
            let entry = compare_kernel(PerfKernel(key = "cmp_test/cmp_tiny", name = "cmp_tiny", dir = dir), bin, 1)
            t |> equal(entry?["native"]?["result"] ?? 0, 4)
            for (lane in DAS_LANES) {
                t |> equal(entry?["ours"]?[lane]?["result"] ?? 0, 4, "ours {lane}: {entry?["ours"]?[lane]?["error"] ?? ""}")
                t |> equal(entry?["rust"]?["lanes"]?[lane]?["time"] ?? 0.0lf, 0.000001lf, "rust {lane}: {entry?["rust"]?["lanes"]?[lane]?["error"] ?? ""}")
            }
            t |> equal(entry?["rust"]?["status"] ?? "", "ran")
            rmdir_rec("compare/work/perf/cmp_test")
        }
    }
}

// a stand-in Rust translator that refuses every input
let REFUSING_STAND_IN = "#!/bin/sh\necho \"c2dascript-transpile v0.1.0\" >&2\necho \"translation failed: unsupported external call: qsort\" >&2\nexit 2\n"

[test]
def test_compare_kernel_refused(t : T?) {
    t |> run("a kernel our converter refuses and the Rust side refuses: native stands, our lanes say convert, Rust is refused") @(t : T?) {
        t |> with_scratch("cmp_perf_kernel_refused") $(dir) {
            fwrite(path_join(dir, "cmp_asm.c"), "static volatile int n = 1000;\nstatic int sum;\nstatic void kernel_run(void) \{ __asm__ volatile(\"nop\"); sum = 0; for (int i = 0; i < n; i++) sum += i & 3; sum = sum / 375; \}\nstatic int kernel_result(void) \{ return sum; \}\n")
            let bin = path_join(dir, "rust")
            fwrite(bin, REFUSING_STAND_IN)
            var out : string
            run_and_capture(["chmod", "+x", bin], out, 30.0)
            let entry = compare_kernel(PerfKernel(key = "cmp_test/cmp_asm", name = "cmp_asm", dir = dir), bin, 1)
            t |> equal(entry?["native"]?["result"] ?? 0, 4)
            let convert_error = entry?["ours"]?["jit"]?["error"] ?? ""
            t |> success(convert_error |> starts_with("convert: ") && convert_error |> contains("inline asm"), convert_error)
            t |> equal(entry?["rust"]?["status"] ?? "", "refused")
            t |> equal(entry?["rust"]?["error"] ?? "", "translation failed: unsupported external call: qsort")
            rmdir_rec("compare/work/perf/cmp_test")
        }
    }
}

// a cell as a capture holds it, its spread one the JSON writer must keep digit for digit
def private fixture_cell() : JsonValue? => JV({"time" => JV(0.5lf), "spread" => JV(0.007192701757091496lf), "samples" => JV([0.5lf])})

// a capture's `perf` section of box `box`, Rust commit `commit`, `samples`, the `clang` and
// `daslang` version lines and, unless `stamped` is false (a capture before the rule), the spread rule
// of `samples` and no pin, holding `sieve` and an old `dasprofile/fib_loop`
def private rerun_fixture(box, commit : string; samples : int; clang, daslang : string; stamped : bool = true) : JsonValue? {
    var kernels = JV({"sieve" => JV({"native" => fixture_cell(), "ours" => JV({"jit" => fixture_cell()})}), "dasprofile/fib_loop" => JV({"native" => JV({"error" => JV("old")})})})
    var section = JV({"box" => JV(box), "rust_commit" => JV(commit), "samples" => JV(samples), "versions" => JV({"clang" => JV(clang), "daslang" => JV(daslang)}), "timestamp" => JV("first"), "kernels" => kernels})
    if (stamped) {
        (section.value as _object)["spread_rule"] = JV(spread_rule_of(samples))
        (section.value as _object)["pinned_core"] = JV(-1)
    }
    return section
}

[test]
def test_perf_rerun(t : T?) {
    t |> run("a re-run merges its kernels, keeps the others and the first run's stamps, and records itself") @(t : T?) {
        t |> with_scratch("cmp_perf_rerun") $(dir) {
            let path = path_join(dir, "results.json")
            fwrite(path, write_json(JV({"perf" => rerun_fixture("PC", "abc", 5, "c1", "d1")})))
            var entries : table<string; JsonValue?>
            entries["dasprofile/fib_loop"] = JV({"native" => JV({"error" => JV("new")})})
            t |> equal(merge_perf_rerun(path, Stamps(box = "PC", rust_commit = "abc", daslang = "d1", date = "d2"), 5, "c1", entries), "")
            let js = json_of(t, fread(path))
            t |> equal(js?["perf"]?["kernels"]?["dasprofile/fib_loop"]?["native"]?["error"] ?? "", "new")
            t |> equal(js?["perf"]?["kernels"]?["sieve"]?["native"]?["spread"] ?? 0.0lf, 0.007192701757091496lf)
            t |> equal(js?["perf"]?["timestamp"] ?? "", "first")
            let rerun = js?["perf"]?["reruns"]?[0]
            t |> equal("{rerun?["timestamp"] ?? ""} {rerun?["kernels"]?[0] ?? ""} {rerun?["box"] ?? ""} {rerun?["rust_commit"] ?? ""} {rerun?["versions"]?["clang"] ?? ""} {rerun?["versions"]?["daslang"] ?? ""}", "d2 dasprofile/fib_loop PC abc c1 d1")
            t |> equal(js?["perf"]?["geomean"]?["jit"]?["kernels"] ?? -1, 0)
        }
    }
    t |> run("a re-run refuses another box, Rust commit, sample count, spread rule, clang or daslang, and a capture without perf, the file untouched") @(t : T?) {
        t |> with_scratch("cmp_perf_rerun_refused") $(dir) {
            let path = path_join(dir, "results.json")
            let text = write_json(JV({"perf" => rerun_fixture("PC", "abc", 5, "c1", "d1")}))
            fwrite(path, text)
            var entries : table<string; JsonValue?>
            entries["sieve"] = JV(1)
            let runs = [Stamps(box = "fx", rust_commit = "abc", daslang = "d1"), Stamps(box = "PC", rust_commit = "def", daslang = "d1"), Stamps(box = "PC", rust_commit = "abc", daslang = "d1"), Stamps(box = "PC", rust_commit = "abc", daslang = "d1"), Stamps(box = "PC", rust_commit = "abc", daslang = "d2")]
            for (stamps, samples, clang, field in runs, [5, 5, 3, 5, 5], ["c1", "c1", "c1", "c2", "c1"], ["box `PC` against this run's `fx`", "rust_commit `abc` against this run's `def`", "samples `5` against this run's `3`, spread_rule `trimmed` against this run's `range`", "clang `c1` against this run's `c2`", "daslang `d1` against this run's `d2`"]) {
                let error = merge_perf_rerun(path, stamps, samples, clang, entries)
                t |> equal(error, "{path} holds {field}: a re-run joins only a capture of its own box, translator, toolchain, samples, spread rule and pin")
            }
            t |> equal(fread(path), text)
            let old = path_join(dir, "old.json")
            let old_text = write_json(JV({"perf" => rerun_fixture("PC", "abc", 5, "c1", "d1", false)}))
            fwrite(old, old_text)
            let refused = merge_perf_rerun(old, Stamps(box = "PC", rust_commit = "abc", daslang = "d1"), 5, "c1", entries)
            t |> equal(refused, "{old} holds spread_rule `range` against this run's `trimmed`: a re-run joins only a capture of its own box, translator, toolchain, samples, spread rule and pin")
            t |> equal(fread(old), old_text)
            let other = path_join(dir, "other.json")
            fwrite(other, "\{\"suites\": \{\}\}")
            t |> equal(merge_perf_rerun(other, Stamps(), 5, "", entries), "no perf section in {other} to re-measure kernels into")
            let none = path_join(dir, "none.json")
            t |> equal(merge_perf_rerun(none, Stamps(), 5, "", entries), "no perf section in {none} to re-measure kernels into")
        }
    }
    t |> run("a second re-run appends to reruns; a capture that is no JSON is the read error") @(t : T?) {
        t |> with_scratch("cmp_perf_rerun_twice") $(dir) {
            let path = path_join(dir, "results.json")
            fwrite(path, write_json(JV({"perf" => rerun_fixture("PC", "abc", 5, "c1", "d1")})))
            for (date in ["d2", "d3"]) {
                var entries : table<string; JsonValue?>
                entries["sieve"] = JV({"native" => JV({"error" => JV(date)})})
                t |> equal(merge_perf_rerun(path, Stamps(box = "PC", rust_commit = "abc", daslang = "d1", date = date), 5, "c1", entries), "")
            }
            let js = json_of(t, fread(path))
            t |> equal("{js?["perf"]?["reruns"]?[0]?["timestamp"] ?? ""} {js?["perf"]?["reruns"]?[1]?["timestamp"] ?? ""}", "d2 d3")
            let bad = path_join(dir, "bad.json")
            fwrite(bad, "nope")
            var no_entries : table<string; JsonValue?>
            t |> success(merge_perf_rerun(bad, Stamps(), 5, "", no_entries) |> starts_with("cannot read {bad}"))
        }
    }
    t |> run("the filter is a comma-separated list, each part a text a key holds, an empty part none") @(t : T?) {
        t |> equal(join([for (k in perf_kernels("sieve,dasprofile/primes")); k.key], " "), "sieve dasprofile/primes")
        t |> equal(join([for (k in perf_kernels("sieve,")); k.key], " "), "sieve")
    }
}

[test]
def test_perf_command_line(t : T?) {
    t |> run("--perf with a suite or under one sample exits 1; --perf without the Rust translator exits 2") @(t : T?) {
        var out : string
        var argv <- daslang_cmd(CONVERTED_MODULES)
        argv |> push_from(["compare/run.das", "--", "--perf", "--suites"])
        t |> equal(run_and_capture(argv, out, 300.0), 1, out)
        t |> success(out |> contains("--perf runs alone"), out)
        var with_suite <- daslang_cmd(CONVERTED_MODULES)
        with_suite |> push_from(["compare/run.das", "--", "--perf", "--suite", "csmith"])
        t |> equal(run_and_capture(with_suite, out, 300.0), 1, out)
        t |> success(out |> contains("--perf runs alone"), out)
        var no_samples <- daslang_cmd(CONVERTED_MODULES)
        no_samples |> push_from(["compare/run.das", "--", "--perf", "--samples", "0"])
        t |> equal(run_and_capture(no_samples, out, 300.0), 1, out)
        t |> success(out |> contains("--samples takes a count of at least 1, not 0"), out)
        with_env("/nonexistent/c2das-rust", "") {
            var perf_only <- daslang_cmd(CONVERTED_MODULES)
            perf_only |> push_from(["compare/run.das", "--", "--perf"])
            t |> equal(run_and_capture(perf_only, out, 300.0), 2, out)
            t |> success(out |> contains("no Rust translator at /nonexistent/c2das-rust"), out)
        }
    }
}

[test]
def test_compare_limits(t : T?) {
    t |> run("both sides' lanes: 120 s a sample, 300 s a build with its run") @(t : T?) {
        t |> equal(COMPARE_LIMITS.sample, 120.0)
        t |> equal(COMPARE_LIMITS.build, 300.0)
    }
    t |> run("a program that never ends: every lane is an error naming its limit") @(t : T?) {
        let work = "compare/work/perf/cmp_test/forever"
        mkdir_rec(work)
        let das_path = path_join(work, "forever.das")
        fwrite(das_path, "options gen2\n[export]\ndef main() : int \{\n    var i = 0\n    while (i >= 0) \{\n        i = (i + 1) % 7\n    \}\n    return i\n\}\n")
        let no_modules : array<string>
        let lanes = JV(das_lane_entries("rust", das_path, work, no_modules, 1, 0, LaneLimits(sample = 1.0, build = 15.0)))
        t |> equal(lanes?["interp"]?["error"] ?? "", "a sample took longer than 1 s")
        t |> equal(lanes?["jit"]?["error"] ?? "", "a sample took longer than 1 s")
        t |> equal(lanes?["exe"]?["error"] ?? "", "the build or its run took longer than 15 s")
        t |> equal(lanes?["aot"]?["error"] ?? "", "the build or its run took longer than 15 s")
        rmdir_rec("compare/work/perf/cmp_test")
    }
}

[test]
def test_perf_run(t : T?) {
    t |> run("one kernel, one sample, a stand-in translator: the kernel line, the kernel merged into the capture, the rest kept") @(t : T?) {
        t |> with_scratch("cmp_perf_run") $(dir) {
            let bin = path_join(dir, "rust")
            fwrite(bin, STAND_IN)
            var out : string
            run_and_capture(["chmod", "+x", bin], out, 30.0)
            let results = path_join(dir, "results.json")
            var clang, daslang : string
            tool_versions(clang, daslang)
            fwrite(results, write_json(JV({"suites" => JV({"csmith" => JV({"ids" => JV(9)})}), "perf" => rerun_fixture("fx", "", 1, clang, daslang)})) + "\n")
            let before = json_of(t, fread(results))
            // a CPU no box names, so only `--box` can make the run's box the capture's
            var argv <- ["env", "DAS_LOG_LEVEL=info", "C2DAS_CPU_NAME=stand-in cpu"]
            argv |> push_from(daslang_cmd(CONVERTED_MODULES), ["compare/run.das", "--", "--perf", "--filter", "nope,dasprofile/fib_loop", "--samples", "1", "--out", results, "--box", "fx"])
            with_env(bin, "") {
                t |> equal(run_and_capture(argv, out, 900.0), 0, out)
            }
            let lines <- split(out, "\n")
            t |> equal(length([for (ln in lines); ln; where ln |> contains("dasprofile/fib_loop: native ")]), 1, out)
            t |> success(out |> contains("re-measured 1 kernels into {results}"), out)
            t |> success(!(out |> contains("dasprofile/fib_recursive: native")), out)
            let after = json_of(t, fread(results))
            t |> equal(write_json(after?["suites"]), write_json(before?["suites"]))
            t |> equal(write_json(after?["perf"]?["kernels"]?["sieve"]), write_json(before?["perf"]?["kernels"]?["sieve"]))
            t |> success((after?["perf"]?["kernels"]?["dasprofile/fib_loop"]?["native"]?["time"] ?? 0.0lf) > 0.0lf, out)
            t |> equal(after?["perf"]?["reruns"]?[0]?["kernels"]?[0] ?? "", "dasprofile/fib_loop")
            t |> equal(after?["perf"]?["timestamp"] ?? "", "first")
            t |> equal(after?["perf"]?["box"] ?? "", "fx")
        }
    }
    t |> run("a re-run refused before any kernel is measured: a filter naming no kernel, a capture of another box") @(t : T?) {
        t |> with_scratch("cmp_perf_rerun_cli") $(dir) {
            let bin = path_join(dir, "rust")
            fwrite(bin, STAND_IN)
            var out : string
            run_and_capture(["chmod", "+x", bin], out, 30.0)
            let results = path_join(dir, "results.json")
            let text = write_json(JV({"perf" => rerun_fixture("bench", "", 1, "", "")}))
            fwrite(results, text)
            let missing = path_join(dir, "missing.json")
            for (filter, at, why in ["no_such_kernel", "sieve", "sieve"], [results, results, missing], ["--filter `no_such_kernel` names no kernel", "box `bench` against this run's `fx`", "no perf section in {missing}"]) {
                var inscope argv <- ["env", "C2DAS_CPU_NAME=stand-in cpu"]
                argv |> push_from(daslang_cmd(CONVERTED_MODULES), ["compare/run.das", "--", "--perf", "--filter", filter, "--samples", "1", "--out", at, "--box", "fx"])
                with_env(bin, "") {
                    t |> equal(run_and_capture(argv, out, 300.0), 1, out)
                }
                t |> success(out |> contains(why) && !(out |> contains(": native ")), out)
            }
            t |> equal(fread(results), text)
            t |> success(!fexist(missing))
        }
    }
}
