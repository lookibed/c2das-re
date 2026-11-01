options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require daslib/json_boost
require ../../converter/tiers.das
require ../suite_compare.das
require ../perf_compare.das
require ../projects.das
require ../compare_render.das
require _common

//! `compare/projects.das` and its rendering without the Rust binary or a real project: the project
//! row, each verdict on stand-in runs, the bench cells over shell commands, the code of a written
//! module, the capture's `projects` section, and `--project` run to its end over a stand-in project
//! folder and translator.

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

// `text` written to the executable `path`
def private write_script(path, text : string) {
    fwrite(path, text)
    var out : string
    run_and_capture(["chmod", "+x", path], out, 30.0)
}

let EXPECTED = "bytes=62\nfib[1]=1\nfib[2]=1\nfib[5]=5\nfib[10]=55\nfib[15]=610\nfib[20]=6765\nfib[24]=46368\ncount=7\n"

[test]
def test_project_row(t : T?) {
    t |> run("wasm3 resolved under the manual folder, its clang arguments absolute") @(t : T?) {
        var p : Project
        t |> success(find_project("/m", "wasm3", p))
        t |> equal(p.dir, "/m/wasm3")
        t |> equal(project_path(p, p.fixture), "/m/wasm3/fixtures/fib32.wasm")
        t |> equal(join(clang_args(p), " "), "-std=c11 -I/m/wasm3/include -I/m/wasm3/upstream/wasm3/source -I/m/wasm3/src")
        t |> equal(p.expected, EXPECTED)
        t |> equal(join(p.rust_flags, "|"), "--das-option|stack = 4194304")
        var q : Project
        t |> success(!find_project("/m", "doom", q))
    }
}

[test]
def test_verdicts(t : T?) {
    t |> run("each class of a run: timeout, exit, output, pass") @(t : T?) {
        let timed = judge_run(popen_timed_out, "", "a\n", 9.0)
        t |> equal("{timed.status} {timed.reason}", "timeout the run took longer than 9 s")
        let exited = judge_run(3, "boom\nerror: bad thing\n", "a\n", 9.0)
        t |> equal("{exited.status} {exited.reason}", "exit exit 3: error: bad thing")
        t |> equal(judge_run(3, "\nboom\n", "a\n", 9.0).reason, "exit 3: boom")
        let wrong = judge_run(0, "a\nb\n", "a\nc\n", 9.0)
        t |> equal("{wrong.status} {wrong.reason}", "output line 2: got `b`, expected `c`")
        t |> equal(first_difference("a\n", "a\nb\n"), "line 2: got ``, expected `b`")
        t |> equal(first_difference("a\nb\nc", "a\nb"), "line 3: got `c`, expected `(none)`")
        t |> equal(first_difference("a\n", "a\n"), "")
        t |> equal(judge_run(0, "[I] jit: compiled\na\n", "a\n", 9.0).status, "pass")
    }
    t |> run("a lane's limit: a run, or a build step and its run") @(t : T?) {
        t |> equal(lane_timeout("interp"), 120.0)
        t |> equal(lane_timeout("jit"), 120.0)
        t |> equal(lane_timeout("exe"), 300.0)
        t |> equal(lane_timeout("aot"), 300.0)
    }
    t |> run("a side refused, and a module failing the compile check, on every lane") @(t : T?) {
        t |> with_scratch("cmp_projects_lanes") $(dir) {
            let none : array<string>
            let refused <- side_lanes("", "no module", dir, none, ["f"], "a\n")
            t |> equal(join([for (lane in DAS_LANES); "{(refused?[lane] ?? Verdict()).status}:{(refused?[lane] ?? Verdict()).reason}"], " "), "refused:no module refused:no module refused:no module refused:no module")
            let broken = path_join(dir, "broken.das")
            fwrite(broken, "options gen2\n[export]\ndef main() : int \{\n    return undefined_name\n\}\n")
            var compiled <- side_lanes(broken, "", dir, none, ["f"], "a\n")
            t |> equal(join([for (lane in DAS_LANES); compiled[lane].status], " "), "compile compile compile compile")
            let reason = (compiled?["interp"] ?? Verdict()).reason
            t |> success(reason |> starts_with("error["), reason)
        }
    }
}

[test]
def test_bench(t : T?) {
    t |> run("the two time lines parsed and dropped") @(t : T?) {
        var setup, decode : double
        t |> success(parse_bench("a\nsetup_us=5\ndecode_us=2500000\n", setup, decode))
        t |> equal(setup, 0.000005lf)
        t |> equal(decode, 2.5lf)
        t |> success(!parse_bench("a\nsetup_us=5\n", setup, decode))
        t |> equal(bench_text("a\nsetup_us=5\ndecode_us=7\n"), "a\n")
    }
    t |> run("cells over runs that pass, the first failing run's error otherwise") @(t : T?) {
        let cells = bench_cells(["sh", "-c", "printf 'a\\nsetup_us=4\\ndecode_us=8\\n'"], "a\n", 2, 30.0)
        t |> equal(cells?["decode"]?["time"] ?? 0.0lf, 0.000008lf)
        t |> equal(cells?["setup"]?["samples"]?[1] ?? 0.0lf, 0.000004lf)
        t |> equal(bench_cells(["sh", "-c", "printf 'b\\nsetup_us=4\\ndecode_us=8\\n'"], "a\n", 2, 30.0)?["error"] ?? "", "output: line 1: got `b`, expected `a`")
        t |> equal(bench_cells(["sh", "-c", "printf 'a\\n'"], "a\n", 2, 30.0)?["error"] ?? "", "no setup_us and decode_us lines: a")
        t |> equal(bench_cells(["sh", "-c", "sleep 5"], "a\n", 1, 1.0)?["error"] ?? "", "timeout: the run took longer than 1 s")
    }
    t |> run("a side's cells: refused, or a lane that does not pass") @(t : T?) {
        let none : array<string>
        let lanes : table<string; Verdict>
        var refused <- side_speed("", "translation failed: x", "w", none, none, lanes, "a\n", 1)
        t |> equal(refused["jit"]?["error"] ?? "", "bench: translation failed: x")
        let failing <- { "interp" => Verdict(status = "output", reason = "line 1") }
        var not_passing <- side_speed("m.das", "", "w", none, none, failing, "a\n", 1)
        t |> equal(not_passing["interp"]?["error"] ?? "", "the lane does not pass: output")
        t |> equal(not_passing["exe"]?["error"] ?? "", "the lane does not pass: skipped")
    }
}

[test]
def test_native_and_code(t : T?) {
    t |> run("the native build: built, or the compiler's first line") @(t : T?) {
        t |> with_scratch("cmp_projects_native") $(dir) {
            fwrite(path_join(dir, "ok.c"), "int main(void) \{ return 0; \}\n")
            fwrite(path_join(dir, "bad.c"), "int main(void) \{ return \}\n")
            let p = Project(name = "p", dir = dir, c_std = "c11")
            t |> equal(native_build(p, "ok.c", path_join(dir, "ok")), "")
            t |> success(native_build(p, "bad.c", path_join(dir, "bad")) |> starts_with("clang exited 1: "))
        }
    }
    t |> run("a side's code: refused, or counted, the Rust runtime split by its prefixes") @(t : T?) {
        t |> with_scratch("cmp_projects_code") $(dir) {
            let none : array<string>
            t |> equal(side_code(none, "", "no module", true).status, "refused")
            let das = path_join(dir, "m.das")
            fwrite(das, "options gen2\ndef c2da_rt_alloc(n : int) : int \{\n    return n\n\}\ndef c2da_str_1() : int \{\n    return 1\n\}\n[export]\ndef main() : int \{\n    return c2da_rt_alloc(c2da_str_1())\n\}\n")
            let rust = side_code([das], das, "", true)
            t |> equal("{rust.status} {rust.files} {rust.lines} {rust.runtime_lines} {rust.program_c2da_lines}", "ok 1 11 3 3")
            let ours = side_code([das], das, "", false)
            t |> equal("{ours.status} {ours.runtime_lines} {ours.program_c2da_lines}", "ok 0 0")
        }
    }
}

[test]
def test_capture(t : T?) {
    t |> run("a project's entry set, every other project and section kept") @(t : T?) {
        t |> with_scratch("cmp_projects_capture") $(dir) {
            let path = path_join(dir, "results.json")
            fwrite(path, "\{\"perf\": \{\"samples\": 5\}, \"projects\": \{\"a\": \{\"x\": 1\}\}\}")
            t |> equal(write_project(path, "b", JV({"y" => JV(2)})), "")
            t |> equal(write_project(path, "a", JV({"x" => JV(3)})), "")
            let js = json_of(t, fread(path))
            t |> equal(js?["perf"]?["samples"] ?? 0, 5)
            t |> equal(js?["projects"]?["a"]?["x"] ?? 0, 3)
            t |> equal(js?["projects"]?["b"]?["y"] ?? 0, 2)
            fwrite(path, "\{\"projects\": 3\}")
            t |> equal(write_project(path, "b", JV({"y" => JV(4)})), "")
            t |> equal(json_of(t, fread(path))?["projects"]?["b"]?["y"] ?? 0, 4)
            fwrite(path, "[1]")
            t |> success(!empty(write_project(path, "b", JV({"y" => JV(4)}))))
        }
    }
}

[test]
def test_project_entry(t : T?) {
    t |> run("a native build printing other than expected: every lane refused, the Rust refusal kept") @(t : T?) {
        t |> with_scratch("cmp_projects_entry") $(dir) {
            fwrite(path_join(dir, "prog.c"), "#include <stdio.h>\nint main(void) \{ printf(\"nope\\n\"); return 0; \}\n")
            fwrite(path_join(dir, "input"), "")
            let bin = path_join(dir, "rust")
            write_script(bin, "#!/bin/sh\necho \"translation failed: x\" >&2\nexit 2\n")
            let p = Project(name = "p", dir = dir, tu = "prog.c", bench_tu = "prog.c", c_std = "c11", fixture = "input", expected = "yes\n")
            let entry = project_entry(p, bin, path_join(dir, "work"), 1, Stamps(rust_commit = "abc"))
            t |> equal(entry?["native"]?["status"] ?? "", "native")
            t |> equal(entry?["ours"]?["lanes"]?["jit"]?["reason"] ?? "", "no native result: line 1: got `nope`, expected `yes`")
            t |> equal(entry?["rust"]?["lanes"]?["interp"]?["status"] ?? "", "refused")
            t |> equal(entry?["rust"]?["error"] ?? "", "translation failed: x")
            t |> equal(entry?["speed"]?["native"]?["error"] ?? "", "output: line 1: got `nope`, expected `yes`")
            t |> equal(entry?["speed"]?["ours"]?["interp"]?["error"] ?? "", "the lane does not pass: refused")
            t |> equal(entry?["speed"]?["rust"]?["exe"]?["error"] ?? "", "bench: translation failed: x")
            t |> equal(entry?["code"]?["rust"]?["status"] ?? "", "refused")
            t |> equal(entry?["code"]?["ours"]?["files"] ?? 0, 1)
            t |> equal(entry?["rust_commit"] ?? "", "abc")
            let lines <- project_lines("p", entry)
            t |> equal(lines[0], "p: native native line 1: got `nope`, expected `yes`")
            t |> success(has_value(lines, "p: rust aot: refused no native result: line 1: got `nope`, expected `yes`"), join(lines, "\n"))
        }
    }
}

[test]
def test_refusals(t : T?) {
    t |> run("a unit neither side takes, and a native build that fails") @(t : T?) {
        t |> with_scratch("cmp_projects_refusals") $(dir) {
            fwrite(path_join(dir, "prog.c"), "#include \"missing.h\"\nint main(void) \{ return 0; \}\n")
            let bin = path_join(dir, "rust")
            write_script(bin, "#!/bin/sh\nprev=\"\"\nfor a in \"$@\"; do\n    if [ \"$prev\" = \"--output-dir\" ]; then out=\"$a\"; fi\n    prev=\"$a\"\ndone\nmkdir -p \"$out\"\necho 'options gen2' > \"$out/prog.das\"\n")
            let p = Project(name = "p", dir = dir, tu = "prog.c", bench_tu = "prog.c", c_std = "c11", fixture = "input", expected = "yes\n")
            let entry = project_entry(p, bin, path_join(dir, "work"), 1, Stamps())
            t |> success((entry?["native"]?["reason"] ?? "") |> starts_with("clang exited 1: "), entry?["native"]?["reason"] ?? "")
            t |> success((entry?["ours"]?["error"] ?? "") |> contains("missing.h"), entry?["ours"]?["error"] ?? "")
            t |> equal(entry?["rust"]?["error"] ?? "", "no module of {path_join(dir, "work/rust")} defines main")
            t |> equal(entry?["code"]?["ours"]?["status"] ?? "", "refused")
        }
    }
}

// `compare/run.das` run from the repository root with `args` after `--`; its exit code
def private run_compare(args : array<string>; var out : string&) : int {
    var argv <- daslang_cmd(CONVERTED_MODULES)
    argv |> push_from(["compare/run.das", "--"], args)
    return run_and_capture(argv, out, 900.0)
}

// a stand-in wasm3 folder under `<dir>/tests/manual` and a translator `<dir>/rust` that copies a
// das program printing the expected output, the bench one for a bench unit
def private stand_in_project(dir : string) : string {
    let root = path_join(dir, "tests/manual/wasm3")
    for (sub in ["src", "include", "upstream/wasm3/source", "fixtures"]) {
        mkdir_rec(path_join(root, sub))
    }
    fwrite(path_join(root, "fixtures/fib32.wasm"), "")
    let lines = replace(EXPECTED, "\n", "\\n")
    let call = "int call_fib(int n) \{ return n; \}\n"
    fwrite(path_join(root, "src/all_host.c"), "#include <stdio.h>\n{call}int main(void) \{ printf(\"{lines}\"); return call_fib(0); \}\n")
    fwrite(path_join(root, "src/all_host_bench.c"), "#include <stdio.h>\n{call}int main(void) \{ printf(\"{lines}setup_us=3\\ndecode_us=6\\n\"); return call_fib(0); \}\n")
    let program = "options gen2\ndef call_fib(n : int) : int \{\n    return n\n\}\n[export]\ndef main() : int \{\n    print(\"{lines}%s\")\n    return call_fib(0)\n\}\n"
    fwrite(path_join(dir, "main.das"), replace(program, "%s", ""))
    fwrite(path_join(dir, "bench.das"), replace(program, "%s", "setup_us=3\\ndecode_us=6\\n"))
    let bin = path_join(dir, "rust")
    write_script(bin, "#!/bin/sh\nprev=\"\"\nfor a in \"$@\"; do\n    if [ \"$prev\" = \"--output-dir\" ]; then out=\"$a\"; fi\n    if [ \"$prev\" = \"--file\" ]; then src=\"$a\"; fi\n    prev=\"$a\"\ndone\nmkdir -p \"$out\"\ncase \"$src\" in\n    *bench*) cp {dir}/bench.das \"$out/all_host_bench.das\" ;;\n    *) cp {dir}/main.das \"$out/all_host.das\" ;;\nesac\n")
    return bin
}

[test]
def test_project_run(t : T?) {
    t |> run("--project wasm3 over a stand-in project to its end: both sides pass, aot skipped, the rest kept") @(t : T?) {
        t |> with_scratch("cmp_projects_run") $(dir) {
            let bin = stand_in_project(dir)
            let results = path_join(dir, "results.json")
            fwrite(results, "\{\"perf\": \{\"samples\": 5\}, \"projects\": \{\"other\": \{\"x\": 1\}\}\}")
            var out : string
            with_env(bin, dir) {
                t |> equal(run_compare(["--project", "wasm3", "--samples", "1", "--out", results], out), 0, out)
            }
            let js = json_of(t, fread(results))
            let entry = js?["projects"]?["wasm3"]
            t |> equal(js?["perf"]?["samples"] ?? 0, 5)
            t |> equal(js?["projects"]?["other"]?["x"] ?? 0, 1)
            t |> equal(entry?["native"]?["status"] ?? "", "pass")
            for (side in ["ours", "rust"]) {
                t |> equal(join([for (lane in DAS_LANES); entry?[side]?["lanes"]?[lane]?["status"] ?? ""], " "), "pass pass pass skipped", side)
                t |> equal(entry?["speed"]?[side]?["exe"]?["decode"]?["time"] ?? 0.0lf, 0.000006lf, side)
                t |> equal(entry?["code"]?[side]?["status"] ?? "", "ok", side)
            }
            t |> equal(entry?["speed"]?["native"]?["setup"]?["time"] ?? 0.0lf, 0.000003lf)
            t |> equal(entry?["speed"]?["rust"]?["aot"]?["error"] ?? "", "the lane does not pass: skipped")
            t |> success((entry?["functions"]?[1]?["ours"] ?? "") |> contains("call_fib"), out)
            t |> success((entry?["functions"]?[1]?["rust"] ?? "") |> starts_with("def call_fib("), out)
        }
    }
    t |> run("an unknown project, a checkout without it, and a mode beside it") @(t : T?) {
        t |> with_scratch("cmp_projects_cli") $(dir) {
            let bin = path_join(dir, "rust")
            write_script(bin, "#!/bin/sh\nexit 0\n")
            var out : string
            with_env(bin, dir) {
                t |> equal(run_compare(["--project", "doom"], out), 1, out)
                t |> success(out |> contains("--project takes one of wasm3, not `doom`"), out)
                t |> equal(run_compare(["--project", "wasm3"], out), 2, out)
                t |> success(out |> contains("the Rust checkout {dir} lacks the project"), out)
                t |> equal(run_compare(["--project", "wasm3", "--samples", "0"], out), 1, out)
                t |> equal(run_compare(["--project", "wasm3", "--perf"], out), 1, out)
                t |> success(out |> contains("--perf runs alone"), out)
            }
            with_env("/nonexistent/c2das-rust", "") {
                t |> equal(run_compare(["--project", "wasm3"], out), 2, out)
            }
        }
    }
}

let RENDER_CAPTURE = "\{\"projects\": \{\"w\": \{\"rust_commit\": \"0123456789abcdef\", \"date\": \"d\", \"samples\": 5, \"lanes\": [\"interp\", \"aot\"], \"native\": \{\"status\": \"native\", \"reason\": \"clang exited 1\"\}, \"ours\": \{\"lanes\": \{\"interp\": \{\"status\": \"refused\", \"reason\": \"r\"\}, \"aot\": \{\"status\": \"refused\", \"reason\": \"r\"\}\}\}, \"rust\": \{\"lanes\": \{\"interp\": \{\"status\": \"pass\", \"reason\": \"\"\}, \"aot\": \{\"status\": \"skipped\", \"reason\": \"no args\"\}\}\}, \"speed\": \{\"native\": \{\"decode\": \{\"time\": 0.5\}\}, \"ours\": \{\"interp\": \{\"error\": \"bench: r\"\}, \"aot\": \{\"error\": \"the lane does not pass: refused\"\}\}, \"rust\": \{\"interp\": \{\"decode\": \{\"time\": 1.0\}\}, \"aot\": \{\"error\": \"timeout: the run took longer than 1 s\"\}\}\}, \"code\": \{\"rust\": \{\"status\": \"ok\", \"files\": 1, \"lines\": 9, \"runtime_lines\": 2, \"counts\": \{\"goto\": 4\}\}\}, \"functions\": [\{\"key\": \"w\", \"name\": \"f\", \"ours\": \"\", \"rust\": \"def f() \{\\n\}\"\}]\}\}\}"

[test]
def test_rendering(t : T?) {
    t |> run("the verdicts, the bench, the code, the reasons and the functions of a project") @(t : T?) {
        let js = json_of(t, RENDER_CAPTURE)
        let verdicts = projects_table(js)
        t |> success(verdicts |> contains("| w       | Ours | native |     refused | refused |"), verdicts)
        t |> success(verdicts |> contains("| w       | Rust | native |        pass | skipped |"), verdicts)
        let speed = project_speed_table(js)
        t |> success(speed |> contains("| w       | Ours | 0.500000 |     refused | refused |"), speed)
        t |> success(speed |> contains("| w       | Rust | 0.500000 |        2.00 | timeout |"), speed)
        let code = project_code_table(js)
        t |> success(code |> contains("| w       | Rust | ok   |     1 |     9 |             2 |"), code)
        let reasons <- project_reasons(js)
        t |> equal(join(reasons, "\n"), "- w, native: clang exited 1\n- w, Ours, interpreter AOT: refused: r\n- w, Rust, AOT: skipped: no args")
        let text = projects_text(js)
        t |> success(text |> contains("Captured: w (Rust `0123456789ab`, d)."), text)
        t |> success(text |> contains("#### `w`: `f`") && text |> contains("Ours: not found"), text)
        t |> success(has_value(rust_ahead(js), "- project w: Rust passes interpreter, ours does not."))
    }
    t |> run("a bench cell without a cell or a native time, and a capture without projects") @(t : T?) {
        let native = json_of(t, "\{\"decode\": \{\"time\": 0.5\}\}")
        t |> equal(bench_text_of(null, native), "n/a")
        t |> equal(bench_text_of(json_of(t, "\{\"decode\": \{\"time\": 1.0\}\}"), null), "n/a")
        t |> equal(bench_text_of(json_of(t, "\{\"error\": \"odd\"\}"), native), "odd")
        let none = json_of(t, "\{\}")
        t |> equal(projects_text(none), "No project is captured yet.\n")
        t |> equal(project_speed_table(none), "")
        t |> equal(project_code_table(none), "")
    }
}
