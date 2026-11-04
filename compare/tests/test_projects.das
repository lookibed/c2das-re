options gen2
// the project tests convert in this process: the emitter walks a program's statements below its own
// frames, and they overflow the default 16 KB context stack
options stack = 1048576
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require daslib/json_boost
require ../../converter/tiers.das
require ../suite_compare.das
require ../../perf/perf_measure.das
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
    t |> run("wasm3 resolved under the checkout's manual folder, its clang arguments absolute") @(t : T?) {
        var p : Project
        t |> success(find_project("/m", "wasm3", p))
        t |> equal(p.dir, "/m/tests/manual/wasm3")
        t |> equal(project_path(p, p.fixture), "/m/tests/manual/wasm3/fixtures/fib32.wasm")
        t |> equal(join(clang_args(p), " "), "-std=c11 -I/m/tests/manual/wasm3/include -I/m/tests/manual/wasm3/upstream/wasm3/source -I/m/tests/manual/wasm3/src")
        t |> equal("{p.cases} {p.case_id} {p.expected}", "/m/tests/canonical/cases.json wasm3-fib32-std ")
        t |> equal(join(p.rust_flags, "|"), "--das-option|stack = 4194304")
        var q : Project
        t |> success(!find_project("/m", "doom", q))
    }
    t |> run("binjgb with its define, its case and the bench's own frame count") @(t : T?) {
        var p : Project
        t |> success(find_project("/m", "binjgb", p))
        t |> equal("{p.tu} {p.bench_tu} {p.fixture} {p.case_id}", "src/binjgb_all.c src/binjgb_bench_all.c fixtures/cgb-acid2.gbc binjgb-cgb-acid2-std")
        t |> equal(join(clang_args(p), " "), "-std=c11 -I/m/tests/manual/binjgb/include -I/m/tests/manual/binjgb/upstream/binjgb/src -I/m/tests/manual/binjgb/src -DNDEBUG")
        t |> equal(join(p.bench_free_keys, " "), "frames frame[")
        t |> equal(join(p.bench_omitted_keys, " "), "width height ticks")
        t |> equal(join(p.functions, " "), "emulator_step_internal ppu_mode3_synchronize")
    }
    t |> run("h264bsd-mp4 with four include folders, warnings off natively, its bench without `bytes=`") @(t : T?) {
        var p : Project
        t |> success(find_project("/m", "h264bsd-mp4", p))
        t |> equal("{p.tu} {p.bench_tu} {p.fixture} {p.case_id}", "src/h264_file_all.c src/h264_file_bench_all.c fixtures/test_640x360.mp4 h264bsd-mp4-640x360-std")
        t |> equal(join(clang_args(p), " "), "-std=c11 -I/m/tests/manual/h264bsd-mp4/include -I/m/tests/manual/h264bsd-mp4/upstream/h264bsd/src -I/m/tests/manual/h264bsd-mp4/upstream/minimp4 -I/m/tests/manual/h264bsd-mp4/src")
        t |> equal(join(p.native_flags, " "), "-w -O2")
        t |> equal("{length(p.rust_flags)} {length(p.bench_free_keys)} {join(p.bench_omitted_keys, " ")}", "0 0 bytes")
        t |> equal(join(p.functions, " "), "h264bsdProcessBlock FilterVerLumaEdge")
    }
    t |> run("plmpeg-stream with its define, our side's hook define, the whole upstream folder included, its bench without `bytes=`") @(t : T?) {
        var p : Project
        t |> success(find_project("/m", "plmpeg-stream", p))
        t |> equal("{p.tu} {p.bench_tu} {p.fixture} {p.case_id}", "src/plmpeg_file_all.c src/plmpeg_file_bench_all.c fixtures/testsrc2_320x240.m1v plmpeg-stream-320x240-std")
        t |> equal(join(clang_args(p), " "), "-std=c11 -I/m/tests/manual/plmpeg-stream/include -I/m/tests/manual/plmpeg-stream/upstream -I/m/tests/manual/plmpeg-stream/fixtures -I/m/tests/manual/plmpeg-stream/src -DPLM_NO_STDIO")
        t |> equal(join(p.native_flags, " "), "-O2")
        t |> equal("{length(p.rust_flags)} {length(p.bench_free_keys)} {join(p.bench_omitted_keys, " ")}", "0 0 bytes")
        t |> equal("{join(p.functions, " ")} | {join(p.ours_defines, " ")}", "plm_video_idct plm_video_decode_block | c2da_rt_reset(...)=")
    }
    t |> run("doomgeneric with the engine's folder included, the stack the case asks for, its bench's 1000 frames") @(t : T?) {
        var p : Project
        t |> success(find_project("/m", "doomgeneric", p))
        t |> equal("{p.tu} {p.bench_tu} {p.fixture} {p.case_id}", "src/doom_all.c src/doom_bench_all.c fixtures/doom1.wad doomgeneric-demo1-std")
        t |> equal(join(clang_args(p), " "), "-std=c11 -I/m/tests/manual/doomgeneric/include -I/m/tests/manual/doomgeneric/upstream/doomgeneric/doomgeneric -I/m/tests/manual/doomgeneric/src")
        t |> equal(join(p.native_flags, " "), "-O2")
        t |> equal(join(p.rust_flags, "|"), "--das-option|stack = 4194304")
        t |> equal("{join(p.bench_free_keys, " ")} {length(p.bench_omitted_keys)}", "frames frame[ 0")
        t |> equal(join(p.functions, " "), "R_DrawColumn R_DrawSpan")
    }
    t |> run("the native build's C files: the case's reference sources and bench entry, else the units") @(t : T?) {
        t |> with_scratch("cmp_projects_sources") $(dir) {
            var p = Project(tu = "u.c", bench_tu = "b.c", cases = path_join(dir, "cases.json"), case_id = "c")
            let stdout = "\"expected\": \{\"stdout\": \"a\\n\"\}"
            fwrite(p.cases, "\{\"cases\": [\{\"id\": \"c\", {stdout}, \"c_reference\": \{\"sources\": [\"g.c\", \"e.c\"]\}, \"corpus\": \{\"bench_c_entry\": \"be.c\"\}\}]\}")
            t |> equal(load_expected(p), "")
            t |> equal("{join(p.native_sources, " ")} | {join(p.native_bench_sources, " ")}", "g.c e.c | g.c be.c")
            fwrite(p.cases, "\{\"cases\": [\{\"id\": \"c\", {stdout}, \"c_reference\": \{\"sources\": [\"g.c\", \"e.c\"]\}\}]\}")
            t |> equal(load_expected(p), "")
            t |> equal("{join(p.native_sources, " ")} | {join(p.native_bench_sources, " ")}", "g.c e.c | b.c")
            fwrite(p.cases, "\{\"cases\": [\{\"id\": \"c\", {stdout}, \"c_reference\": \{\"entrypoint\": \"main\"\}\}]\}")
            t |> equal(load_expected(p), "")
            t |> equal("{join(p.native_sources, " ")} | {join(p.native_bench_sources, " ")}", "u.c | b.c")
            fwrite(p.cases, "\{\"cases\": [\{\"id\": \"c\", {stdout}, \"c_reference\": \{\"sources\": [\"g.c\", 3]\}\}]\}")
            t |> equal(load_expected(p), "{p.cases}: the case c has a c_reference.sources entry that is not a string")
        }
    }
    t |> run("the expected output read from the canonical case, or why not") @(t : T?) {
        t |> with_scratch("cmp_projects_cases") $(dir) {
            var p = Project(cases = path_join(dir, "cases.json"), case_id = "c")
            t |> equal(load_expected(p), "no {p.cases}: the Rust checkout lacks its canonical cases")
            fwrite(p.cases, "\{")
            t |> success(load_expected(p) |> starts_with("{p.cases} is not JSON: "))
            fwrite(p.cases, "\{\"cases\": [\{\"id\": \"c\"\}, \{\"id\": \"d\", \"expected\": \{\"stdout\": \"x\"\}\}]\}")
            t |> equal(load_expected(p), "{p.cases} has no case c with an expected.stdout")
            fwrite(p.cases, "\{\"cases\": [\{\"id\": \"d\"\}, \{\"id\": \"c\", \"expected\": \{\"stdout\": \"a\\nb\\n\"\}\}]\}")
            t |> equal(load_expected(p), "")
            t |> equal(p.expected, "a\nb\n")
        }
    }
}

[test]
def test_project_units_row(t : T?) {
    t |> run("quakegeneric with its forced include, libm linked natively, no bench unit") @(t : T?) {
        var p : Project
        t |> success(find_project("/m", "quakegeneric", p))
        t |> equal("{p.tu} [{p.bench_tu}] {p.fixture} {p.case_id}", "src/quake_entry.c [] fixtures quakegeneric-demo1-std")
        t |> equal(join(clang_args(p), " "), "-std=c11 -I/m/tests/manual/quakegeneric/upstream/quakegeneric/source -I/m/tests/manual/quakegeneric/src -include engine_config.h")
        t |> equal("{join(p.native_flags, " ")} {join(p.link_flags, " ")}", "-O2 -lm")
        t |> equal(join(p.rust_flags, "|"), "--das-option|stack = 4194304")
        t |> equal(join(p.functions, " "), "D_DrawSpans8 D_DrawZSpans")
    }
    t |> run("a case's translation units: the program, and the native build's C files when it names no reference") @(t : T?) {
        t |> with_scratch("cmp_projects_units") $(dir) {
            var p = Project(tu = "e.c", cases = path_join(dir, "cases.json"), case_id = "c")
            let stdout = "\"expected\": \{\"stdout\": \"a\\n\"\}"
            fwrite(p.cases, "\{\"cases\": [\{\"id\": \"c\", {stdout}, \"translation_units\": [\"g.c\", \"e.c\"]\}]\}")
            t |> equal(load_expected(p), "")
            t |> equal("{join(p.units, " ")} | {join(p.native_sources, " ")} | {length(p.native_bench_sources)}", "g.c e.c | g.c e.c | 0")
            fwrite(p.cases, "\{\"cases\": [\{\"id\": \"c\", {stdout}, \"translation_units\": [\"g.c\", \"e.c\"], \"c_reference\": \{\"sources\": [\"r.c\"]\}\}]\}")
            t |> equal(load_expected(p), "")
            t |> equal("{join(p.units, " ")} | {join(p.native_sources, " ")}", "g.c e.c | r.c")
            fwrite(p.cases, "\{\"cases\": [\{\"id\": \"c\", {stdout}, \"c_reference\": \{\"sources\": [\"r.c\"]\}, \"corpus\": \{\"bench_c_entry\": \"be.c\"\}\}]\}")
            t |> equal(load_expected(p), "")
            t |> equal("{join(p.native_sources, " ")} | {length(p.native_bench_sources)}", "r.c | 0")
            fwrite(p.cases, "\{\"cases\": [\{\"id\": \"c\", {stdout}, \"translation_units\": [\"g.c\", 1]\}]\}")
            t |> equal(load_expected(p), "{p.cases}: the case c has a translation_units entry that is not a string")
        }
    }
}

[test]
def test_path_free(t : T?) {
    t |> run("a reason's paths under the root made relative, any other path kept") @(t : T?) {
        let warn = "[W] LLVM JIT: return inside try/recover leaves the try arm. at /r/wt/compare/work/p/rust/host.das.inc:664:12"
        t |> equal(path_free(warn, "/r/wt"), "[W] LLVM JIT: return inside try/recover leaves the try arm. at compare/work/p/rust/host.das.inc:664:12")
        t |> equal(path_free(warn, "/r/wt/"), path_free(warn, "/r/wt"))
        t |> equal(path_free("dumper: /c/src/a.c:1:1: x", "/r/wt"), "dumper: /c/src/a.c:1:1: x")
        t |> equal(path_free("at /r/wtx/a.das", "/r/wt"), "at /r/wtx/a.das")
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
    t |> run("a run's stdout judged, its stderr apart and read for an exit's error line") @(t : T?) {
        var out, err : string
        t |> equal(run_split(["sh", "-c", "echo a; echo log >&2"], 30.0, out, err), 0)
        t |> equal("{out}|{err}", "a\n|log\n")
        t |> equal(run_judged(["sh", "-c", "echo a; echo log >&2"], "a\n", 30.0).status, "pass")
        let failed = run_judged(["sh", "-c", "echo a; echo 'error: x' >&2; exit 4"], "a\n", 30.0)
        t |> equal("{failed.status} {failed.reason}", "exit exit 4: error: x")
        t |> equal(judge_run(4, "a\n", "", "a\n", 9.0).reason, "exit 4: a")
        let died = run_judged(["sh", "-c", "echo 'frame[0]=1'; echo 'segmentation fault' >&2; exit 1"], "a\n", 30.0)
        t |> equal("{died.status} {died.reason}", "exit exit 1: segmentation fault")
    }
    t |> run("a lane's command: daslang over the module, or the exe or aot binary, the program's arguments last") @(t : T?) {
        t |> with_scratch("cmp_projects_lane_argv") $(dir) {
            let none : array<string>
            var error : string
            let jit <- lane_argv("m.das", "jit", dir, none, ["f"], 9.0, error)
            t |> equal(join([for (i in range(length(jit) - 4, length(jit))); jit[i]], " "), "-jit m.das -- f")
            let das = path_join(dir, "m.das")
            fwrite(das, "options gen2\n[export]\ndef main() : int \{\n    return 0\n\}\n")
            let exe <- lane_argv(das, "exe", path_join(dir, "w"), none, ["f"], 300.0, error)
            t |> equal(length(exe), 2, error)
            t |> success(fexist(exe[0]) && exe[1] == "f", join(exe, " "))
            let aot <- lane_argv(das, "aot", path_join(dir, "a"), none, ["f"], 300.0, error)
            t |> equal(join([for (i in range(1, length(aot))); aot[i]], " "), "-- f", error)
            t |> success(length(aot) == 3 && aot[0] == aot_binary(das, path_join(dir, "a")) && fexist(aot[0]), join(aot, " "))
            let slow <- lane_argv(das, "exe", path_join(dir, "w"), none, ["f"], 1.0, error)
            t |> equal("{length(slow)} {error}", "0 timeout: the build or its run took longer than 1 s")
            let lanes <- side_lanes(das, "", path_join(dir, "lanes"), none, ["f"], "", LaneLimits(sample = 60.0, build = 1.0))
            let exe_lane = lanes?["exe"] ?? Verdict()
            t |> equal("{exe_lane.status} {exe_lane.reason}", "timeout the build or its run took longer than 1 s")
            fwrite(das, "options gen2\n[export]\ndef main() : int \{\n    return undefined_name\n\}\n")
            let broken <- lane_argv(das, "exe", path_join(dir, "w"), none, ["f"], 300.0, error)
            t |> success(empty(broken) && error |> starts_with("exe build: the build exited "), error)
            let broken_aot <- lane_argv(das, "aot", path_join(dir, "a"), none, ["f"], 300.0, error)
            t |> success(empty(broken_aot) && error |> starts_with("aot build: the build exited ") && error |> contains("error["), error)
        }
    }
    t |> run("a lane's limit: a run, or a build step and its run") @(t : T?) {
        t |> equal(lane_timeout("interp", COMPARE_LIMITS), 120.0)
        t |> equal(lane_timeout("jit", COMPARE_LIMITS), 120.0)
        t |> equal(lane_timeout("exe", COMPARE_LIMITS), 300.0)
        t |> equal(lane_timeout("aot", LaneLimits(sample = 1.0, build = 2.0)), 2.0)
    }
    t |> run("a side refused, and a module failing the compile check, on every lane") @(t : T?) {
        t |> with_scratch("cmp_projects_lanes") $(dir) {
            let none : array<string>
            let refused <- side_lanes("", "no module", dir, none, ["f"], "a\n", COMPARE_LIMITS)
            t |> equal(join([for (lane in DAS_LANES); "{(refused?[lane] ?? Verdict()).status}:{(refused?[lane] ?? Verdict()).reason}"], " "), "refused:no module refused:no module refused:no module refused:no module")
            let broken = path_join(dir, "broken.das")
            fwrite(broken, "options gen2\n[export]\ndef main() : int \{\n    return undefined_name\n\}\n")
            var compiled <- side_lanes(broken, "", dir, none, ["f"], "a\n", COMPARE_LIMITS)
            t |> equal(join([for (lane in DAS_LANES); compiled[lane].status], " "), "compile compile compile compile")
            let reason = (compiled?["interp"] ?? Verdict()).reason
            t |> success(reason |> starts_with("error["), reason)
            let fifo = path_join(dir, "blocked.das")
            var made : string
            run_and_capture(["mkfifo", fifo], made, 30.0)
            let slow <- side_lanes(fifo, "", dir, none, ["f"], "a\n", LaneLimits(sample = 0.5, build = 0.5))
            t |> equal(join([for (lane in DAS_LANES); (slow?[lane] ?? Verdict()).status], " "), "timeout timeout timeout timeout")
            t |> equal((slow?["jit"] ?? Verdict()).reason, "the compile check took longer than 0.5 s")
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
    t |> run("the native bench's text as the oracle: agreeing on the lines it shares with the output") @(t : T?) {
        let none : array<string>
        let expected = "a=1\nw=2\nf[0]=5\nn=1\n"
        t |> equal(bench_disagreement("a=1\nf[0]=5\nf[1]=5\nn=3\n", expected, ["n", "f["], ["w"]), "")
        t |> equal(bench_disagreement("a=1\nn=0\n", expected, ["n", "f["], ["w"]), "the bench lacks `f[0]=5`")
        t |> equal(bench_disagreement("a=1\nf[0]=5\nn=3\n", expected, ["n", "f["], none), "the bench lacks `w=2`")
        t |> equal(bench_disagreement("a=1\nf[0]=4\n", "a=1\nf[0]=5\n", none, none), "got `f[0]=4`, expected `f[0]=5`")
        t |> equal(bench_disagreement("title: X\nend\n", "title: Y\nend\n", none, none), "got `title: X`, expected `title: Y`")
        t |> equal(bench_disagreement("a=1\n", "a=1\n", none, none), "")
        t |> equal(bench_disagreement("a=1\nx=2\n", "a=1\n", none, none), "the expected output has no `x=2`")
        t |> equal(bench_disagreement("a=1\nx=2\n", "a=1\n", ["x"], none), "")
        t |> with_scratch("cmp_projects_oracle") $(dir) {
            let p = Project(expected = "a=1\nn=1\n", bench_free_keys <- ["n"])
            let bin = path_join(dir, "bench")
            var oracle : string
            write_script(bin, "#!/bin/sh\nprintf 'a=1\\nn=3\\nsetup_us=4\\ndecode_us=8\\n'\n")
            t |> equal(native_bench_oracle(p, bin, "f", oracle), "")
            t |> equal(oracle, "a=1\nn=3\n")
            write_script(bin, "#!/bin/sh\nprintf 'a=2\\n'\n")
            t |> equal(native_bench_oracle(p, bin, "f", oracle), "output: got `a=2`, expected `a=1`")
            write_script(bin, "#!/bin/sh\necho 'error: no rom'\nexit 2\n")
            t |> equal(native_bench_oracle(p, bin, "f", oracle), "exit: exit 2: error: no rom")
        }
    }
    t |> run("a side's cells: refused, or a lane that does not pass") @(t : T?) {
        let none : array<string>
        let lanes : table<string; Verdict>
        var refused <- side_speed("", "translation failed: x", "w", none, none, lanes, "a\n", 1, COMPARE_LIMITS)
        t |> equal(refused["jit"]?["error"] ?? "", "bench: translation failed: x")
        let failing <- { "interp" => Verdict(status = "output", reason = "line 1") }
        var not_passing <- side_speed("m.das", "", "w", none, none, failing, "a\n", 1, COMPARE_LIMITS)
        t |> equal(not_passing["interp"]?["error"] ?? "", "the lane does not pass: output")
        t |> equal(not_passing["exe"]?["error"] ?? "", "the lane does not pass: skipped")
    }
    t |> run("an exe lane whose bench module does not build") @(t : T?) {
        t |> with_scratch("cmp_projects_exe_build") $(dir) {
            let none : array<string>
            let broken = path_join(dir, "bench.das")
            fwrite(broken, "options gen2\n[export]\ndef main() : int \{\n    return undefined_name\n\}\n")
            let passing <- { "exe" => Verdict(status = "pass") }
            var cells <- side_speed(broken, "", path_join(dir, "w"), none, ["f"], passing, "a\n", 1, COMPARE_LIMITS)
            let error = cells["exe"]?["error"] ?? ""
            t |> success(error |> starts_with("exe build: "), error)
        }
    }
}

[test]
def test_native_and_code(t : T?) {
    t |> run("the native build: built, or the compiler's first line") @(t : T?) {
        t |> with_scratch("cmp_projects_native") $(dir) {
            fwrite(path_join(dir, "ok.c"), "int main(void) \{ return 0; \}\n")
            fwrite(path_join(dir, "bad.c"), "int main(void) \{ return \}\n")
            let p = Project(name = "p", dir = dir, c_std = "c11")
            t |> equal(native_build(p, ["ok.c"], path_join(dir, "ok")), "")
            t |> success(native_build(p, ["bad.c"], path_join(dir, "bad")) |> starts_with("clang exited 1: "))
            fwrite(path_join(dir, "graph.c"), "int seven(void) \{ return 7; \}\n")
            fwrite(path_join(dir, "entry.c"), "int seven(void);\nint main(void) \{ return seven() - 7; \}\n")
            t |> equal(native_build(p, ["graph.c", "entry.c"], path_join(dir, "two")), "")
            var out : string
            t |> equal(run_and_capture([path_join(dir, "two")], out, 30.0), 0, out)
        }
    }
    t |> run("the native build: the forced include, the link flags after the files") @(t : T?) {
        t |> with_scratch("cmp_projects_link") $(dir) {
            fwrite(path_join(dir, "cfg.h"), "#define ROOT cbrt\n")
            fwrite(path_join(dir, "m.c"), "#include <math.h>\nvolatile double v = 8.0;\nint main(void) \{ return (int)ROOT(v) - 2; \}\n")
            var p = Project(name = "p", dir = dir, include_dirs <- ["."], clang_extra <- ["-include", "cfg.h"], c_std = "c11")
            t |> success(native_build(p, ["m.c"], path_join(dir, "m")) |> starts_with("clang exited 1: "))
            p.link_flags <- ["-lm"]
            t |> equal(native_build(p, ["m.c"], path_join(dir, "m")), "")
            var out : string
            t |> equal(run_and_capture([path_join(dir, "m")], out, 30.0), 0, out)
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
    t |> run("a side of several modules: every module counted, or the first that fails named") @(t : T?) {
        t |> with_scratch("cmp_projects_modules") $(dir) {
            let lib = path_join(dir, "lib.das")
            let entry = path_join(dir, "entry.das")
            fwrite(lib, "options gen2\nmodule lib public\ndef seven() : int \{\n    var p : int?\n    unsafe \{\n        p = reinterpret<int?>(0l)\n    \}\n    return 7\n\}\n")
            fwrite(entry, "options gen2\nrequire lib\n[export]\ndef main() : int \{\n    return seven()\n\}\n")
            let alone = side_code([entry], entry, "", false)
            let both = side_code([entry, lib], entry, "", false)
            t |> equal("{alone.counts?["reinterpret"] ?? -1} {both.status} {both.files} {both.counts?["reinterpret"] ?? -1}", "0 ok 2 1")
            let bad = path_join(dir, "bad.das")
            fwrite(bad, "options gen2\nmodule bad public\ndef f() : int \{\n    return x\n\}\n")
            let broken = side_code([entry, bad], entry, "", false)
            t |> success("{broken.status} {broken.error}" |> starts_with("compile bad.das: "), broken.error)
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
            let p = Project(name = "p", dir = dir, tu = "prog.c", bench_tu = "prog.c", native_sources <- ["prog.c"], native_bench_sources <- ["prog.c"], c_std = "c11", fixture = "input", expected = "yes\n")
            let entry = project_entry(p, bin, path_join(dir, "work"), 1, Stamps(rust_commit = "abc", cpu = "C", box = "fx"))
            t |> equal(entry?["native"]?["status"] ?? "", "native")
            t |> equal(entry?["ours"]?["lanes"]?["jit"]?["reason"] ?? "", "no native result: line 1: got `nope`, expected `yes`")
            t |> equal(entry?["rust"]?["lanes"]?["interp"]?["status"] ?? "", "refused")
            t |> equal(entry?["rust"]?["error"] ?? "", "translation failed: x")
            t |> equal(entry?["speed"]?["native"]?["error"] ?? "", "output: the bench lacks `yes`")
            t |> equal(entry?["speed"]?["ours"]?["interp"]?["error"] ?? "", "bench: no native bench result: output: the bench lacks `yes`")
            t |> equal(entry?["speed"]?["rust"]?["exe"]?["error"] ?? "", "bench: translation failed: x")
            t |> equal(entry?["code"]?["rust"]?["status"] ?? "", "refused")
            t |> equal(entry?["code"]?["ours"]?["files"] ?? 0, 1)
            t |> equal(entry?["rust_commit"] ?? "", "abc")
            t |> equal(entry?["cpu"] ?? "", "C")
            t |> equal(entry?["box"] ?? "", "fx")
            let lines <- project_lines("p", entry)
            t |> equal(lines[0], "p: native native line 1: got `nope`, expected `yes`")
            t |> success(has_value(lines, "p: rust aot: refused no native result: line 1: got `nope`, expected `yes`"), join(lines, "\n"))
        }
    }
    t |> run("0 samples: no bench built or timed, every speed cell not measured; our side's own define in its sidecar alone, recorded, the cap recorded") @(t : T?) {
        t |> with_scratch("cmp_projects_untimed") $(dir) {
            fwrite(path_join(dir, "prog.c"), "#include <stdio.h>\nint main(void) \{ HOOK(1); printf(\"yes\\n\"); return 0; \}\n")
            fwrite(path_join(dir, "input"), "")
            fwrite(path_join(dir, "prog.das"), "options gen2\n[export]\ndef main() : int \{\n    return 0\n\}\n")
            let bin = path_join(dir, "rust")
            // the Rust stand-in translates only when no argument carries the define
            write_script(bin, "#!/bin/sh\ncase \"$*\" in *HOOK*) echo \"got the define\" >&2; exit 2 ;; esac\nprev=\"\"\nfor a in \"$@\"; do\n    if [ \"$prev\" = \"--output-dir\" ]; then out=\"$a\"; fi\n    prev=\"$a\"\ndone\nmkdir -p \"$out\"\ncp {dir}/prog.das \"$out/prog.das\"\n")
            let p = Project(name = "p", dir = dir, tu = "prog.c", bench_tu = "prog.c", ours_defines <- ["HOOK(...)="], native_sources <- ["prog.c"], native_bench_sources <- ["prog.c"], c_std = "c11", fixture = "input", expected = "yes\n")
            let entry = project_entry(p, bin, path_join(dir, "work"), 0, Stamps())
            t |> equal(entry?["ours"]?["error"] ?? "", "")
            t |> equal(entry?["rust"]?["error"] ?? "", "")
            t |> equal(entry?["ours"]?["defines"]?[0] ?? "", "HOOK(...)=")
            t |> equal(entry?["address_cap"] ?? "", address_cap_of(fread("/proc/self/limits")))
            t |> success((entry?["native"]?["reason"] ?? "") |> starts_with("clang exited 1: "), entry?["native"]?["reason"] ?? "")
            t |> equal(entry?["speed"]?["native"]?["error"] ?? "", NOT_TIMED)
            for (lane in DAS_LANES) {
                t |> equal(entry?["speed"]?["ours"]?[lane]?["error"] ?? "", NOT_TIMED, lane)
            }
            t |> equal(entry?["speed"]?["rust"]?["exe"]?["error"] ?? "", NOT_TIMED)
            t |> success(!fexist(path_join(dir, "work/ours_bench")) && !fexist(path_join(dir, "work/native/p_bench")))
        }
    }
}

[test]
def test_address_cap(t : T?) {
    t |> run("the soft address-space limit of /proc/self/limits, or nothing") @(t : T?) {
        let limits = "Limit                     Soft Limit           Hard Limit           Units\nMax address space         4294967296           unlimited            bytes\n"
        t |> equal(address_cap_of(limits), "4294967296")
        t |> equal(address_cap_of(replace(limits, "4294967296  ", "unlimited   ")), "unlimited")
        t |> equal(address_cap_of(""), "")
        t |> success(!empty(address_cap_of(fread("/proc/self/limits"))))
    }
}

[test]
def test_project_units(t : T?) {
    t |> run("a project of several units without a bench: ours converts the program, Rust gets a database, no bench cell") @(t : T?) {
        t |> with_scratch("cmp_projects_program") $(dir) {
            mkdir_rec(path_join(dir, "src"))
            fwrite(path_join(dir, "src/graph.c"), "int call_fib(int n) \{ return n; \}\n")
            fwrite(path_join(dir, "src/entry.c"), "#include <stdio.h>\nint call_fib(int n);\nint main(void) \{\n    printf(\"{escaped(EXPECTED)}\");\n    return call_fib(0);\n\}\n")
            fwrite(path_join(dir, "input"), "")
            fwrite(path_join(dir, "graph.das"), "options gen2\nmodule graph public\ndef call_fib(n : int) : int \{\n    return n\n\}\n")
            fwrite(path_join(dir, "entry.das"), "options gen2\nrequire graph\n[export]\ndef main() : int \{\n    print(\"{escaped(EXPECTED)}\")\n    return call_fib(0)\n\}\n")
            let bin = path_join(dir, "rust")
            write_script(bin, "#!/bin/sh\nprintf '%s\\n' \"$@\" > {dir}/argv.txt\nprev=\"\"\nfor a in \"$@\"; do\n    if [ \"$prev\" = \"--output-dir\" ]; then out=\"$a\"; fi\n    prev=\"$a\"\ndone\nmkdir -p \"$out\"\ncp {dir}/graph.das {dir}/entry.das \"$out/\"\n")
            let p = Project(name = "p", dir = dir, tu = "src/entry.c", units <- ["src/graph.c", "src/entry.c"], native_sources <- ["src/graph.c", "src/entry.c"], c_std = "c11", fixture = "input", expected = EXPECTED, functions <- ["call_fib"])
            let entry = project_entry(p, bin, path_join(dir, "work"), 1, Stamps())
            t |> equal(entry?["native"]?["status"] ?? "", "pass")
            for (side in ["ours", "rust"]) {
                t |> equal(join([for (lane in ["interp", "jit"]); entry?[side]?["lanes"]?[lane]?["status"] ?? ""], " "), "pass pass", side)
                t |> equal(entry?["speed"]?[side]?["interp"]?["error"] ?? "", "no bench: the project has no bench unit", side)
                t |> equal(entry?["code"]?[side]?["status"] ?? "", "ok", side)
                t |> success((entry?["functions"]?[0]?[side] ?? "") |> contains("call_fib"), side)
            }
            t |> equal(entry?["speed"]?["native"]?["error"] ?? "", "no bench: the project has no bench unit")
            t |> equal(entry?["code"]?["rust"]?["files"] ?? 0, 2)
            let argv = fread(path_join(dir, "argv.txt"))
            t |> success(argv |> starts_with(path_join(dir, "work/rust_db/compile_commands.json")) && argv |> contains("--module-layout\nsource\n"), argv)
            let db = fread(path_join(dir, "work/rust_db/compile_commands.json"))
            t |> success(db |> contains(path_join(dir, "src/graph.c")) && !(db |> contains("bench")), db)
        }
    }
}

[test]
def test_working_folder(t : T?) {
    t |> run("a path made absolute, and a working folder made and entered, the one before returned") @(t : T?) {
        t |> equal(absolute_path("/a/b"), "/a/b")
        t |> equal(absolute_path("a/b"), path_join(getcwd(), "a/b"))
        t |> with_scratch("cmp_projects_cwd") $(dir) {
            let before = getcwd()
            let back = enter_working_folder(path_join(dir, "new/cwd"))
            let inside = getcwd()
            fwrite("mark", "x")
            chdir(back)
            t |> equal(back, before)
            t |> equal(inside, path_join(dir, "new/cwd"))
            t |> success(fexist(path_join(dir, "new/cwd/mark")))
        }
    }
    t |> run("every program of a project, native and each lane of both sides, runs in <work>/cwd, judged on its stdout") @(t : T?) {
        t |> with_scratch("cmp_projects_entry_cwd") $(dir) {
            let mark = "#include <stdio.h>\nint main(void) \{\n    FILE *f = fopen(\"c_mark\", \"w\");\n    if (f) fclose(f);\n    fprintf(stderr, \"log\\n\");\n    printf(\"yes\\n%s\");\n    return 0;\n\}\n"
            fwrite(path_join(dir, "prog.c"), replace(mark, "%s", ""))
            fwrite(path_join(dir, "bench.c"), replace(mark, "%s", "setup_us=3\\ndecode_us=6\\n"))
            fwrite(path_join(dir, "input"), "")
            let program = "options gen2\nrequire daslib/fio\n[export]\ndef main() : int \{\n    fwrite(\"das_mark\", \"x\")\n    print(\"yes\\n%s\")\n    return 0\n\}\n"
            fwrite(path_join(dir, "prog.das"), replace(program, "%s", ""))
            fwrite(path_join(dir, "bench.das"), replace(program, "%s", "setup_us=3\\ndecode_us=6\\n"))
            let bin = path_join(dir, "rust")
            write_script(bin, "#!/bin/sh\nprev=\"\"\nfor a in \"$@\"; do\n    if [ \"$prev\" = \"--output-dir\" ]; then out=\"$a\"; fi\n    if [ \"$prev\" = \"--file\" ]; then src=\"$a\"; fi\n    prev=\"$a\"\ndone\nmkdir -p \"$out\"\ncp {dir}/$(basename \"$src\" .c).das \"$out/prog.das\"\n")
            let p = Project(name = "p", dir = dir, tu = "prog.c", bench_tu = "bench.c", native_sources <- ["prog.c"], native_bench_sources <- ["bench.c"], c_std = "c11", fixture = "input", expected = "yes\n", bench_free_keys <- ["setup_us", "decode_us"])
            let entry = project_entry(p, bin, path_join(dir, "work"), 1, Stamps())
            t |> equal(entry?["native"]?["status"] ?? "", "pass")
            for (side in ["ours", "rust"]) {
                t |> equal(join([for (lane in DAS_LANES); entry?[side]?["lanes"]?[lane]?["status"] ?? ""], " "), "pass pass pass pass", side)
                t |> equal(entry?["speed"]?[side]?["exe"]?["decode"]?["time"] ?? 0.0lf, 0.000006lf, side)
            }
            t |> equal(entry?["speed"]?["native"]?["decode"]?["time"] ?? 0.0lf, 0.000006lf)
            t |> success(fexist(path_join(dir, "work/cwd/c_mark")) && fexist(path_join(dir, "work/cwd/das_mark")))
            t |> success(!fexist("c_mark") && !fexist("das_mark"))
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
            let p = Project(name = "p", dir = dir, tu = "prog.c", bench_tu = "prog.c", native_sources <- ["prog.c"], native_bench_sources <- ["prog.c"], c_std = "c11", fixture = "input", expected = "yes\n")
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

// `text` with each newline written as the escape a C or das string literal reads
def private escaped(text : string) : string => replace(text, "\n", "\\n")

// a stand-in project's facts: its units, fixture and case, the output it prints, the native
// build's own C files when its case names them, and the text its converted unit prints instead
struct private StandIn {
    unit : string
    bench_unit : string
    fixture : string
    case_id : string
    head : string
    body : string
    bench_body : string
    guarded : bool
    unit_body : string
}

// the facts of the stand-in `name`
def private stand_in_facts(name : string) : StandIn {
    if (name == "wasm3") {
        return StandIn(unit = "all_host", bench_unit = "all_host_bench", fixture = "fixtures/fib32.wasm", case_id = "wasm3-fib32-std", body = EXPECTED, bench_body = EXPECTED)
    } elif (name == "binjgb") {
        return StandIn(unit = "binjgb_all", bench_unit = "binjgb_bench_all", fixture = "fixtures/cgb-acid2.gbc", case_id = "binjgb-cgb-acid2-std",
            head = "rom=1\n", body = "frame[0]=5\nframes=1\nticks=7\n", bench_body = "frame[0]=5\nframe[1]=5\nframes=2\n", guarded = true)
    }
    return StandIn(unit = "h264_file_all", bench_unit = "h264_file_bench_all", fixture = "fixtures/test_640x360.mp4", case_id = "h264bsd-mp4-640x360-std",
        body = "bytes=4\nframe[0]=5\nwidth=2\nframes=1\n", bench_body = "frame[0]=5\nframes=1\nwidth=2\n", unit_body = "bytes=3\n")
}

// a stand-in folder of the project `name` (wasm3, binjgb or h264bsd-mp4) under
// `<dir>/tests/manual` and a translator `<dir>/rust` that copies a das program printing the
// expected output, the bench one for a bench unit; binjgb's units print their first line only
// under its define, and its bench prints one frame more than its unit, a count of its own and no
// `ticks=`; h264bsd-mp4's case names the native build's own C files, a graph and an entry, its
// unit prints `bytes=3` alone, and its bench prints its lines in another order and no `bytes=`
def private stand_in_project(dir, name : string) : string {
    let f = stand_in_facts(name)
    let root = path_join(dir, "tests/manual/{name}")
    let times = escaped("setup_us=3\ndecode_us=6\n")
    for (sub in ["src", "fixtures"]) {
        mkdir_rec(path_join(root, sub))
    }
    mkdir_rec(path_join(dir, "tests/canonical"))
    fwrite(path_join(root, f.fixture), "")
    var canonical <- {"id" => JV(f.case_id), "expected" => JV({"stdout" => JV(f.head + f.body)})}
    let guarded = f.guarded ? "#ifdef NDEBUG\n    printf(\"{escaped(f.head)}\");\n#endif\n" : ""
    let c_unit = "#include <stdio.h>\nint call_fib(int n) \{ return n; \}\nint main(void) \{\n{guarded}    printf(\"%s\");\n    return call_fib(0);\n\}\n"
    if (!empty(f.unit_body)) {
        canonical["c_reference"] = JV({"sources" => JV(["src/graph.c", "src/entry.c"])})
        canonical["corpus"] = JV({"bench_c_entry" => JV("src/bench_entry.c")})
        fwrite(path_join(root, "src/graph.c"), "int call_fib(int n) \{ return n; \}\n")
        let entry = "#include <stdio.h>\nint call_fib(int n);\nint main(void) \{\n    printf(\"%s\");\n    return call_fib(0);\n\}\n"
        fwrite(path_join(root, "src/entry.c"), replace(entry, "%s", escaped(f.body)))
        fwrite(path_join(root, "src/bench_entry.c"), replace(entry, "%s", escaped(f.bench_body) + times))
    }
    fwrite(path_join(dir, "tests/canonical/cases.json"), write_json(JV({"cases" => JV([JV(canonical)])})))
    fwrite(path_join(root, "src/{f.unit}.c"), replace(c_unit, "%s", escaped(empty(f.unit_body) ? f.body : f.unit_body)))
    fwrite(path_join(root, "src/{f.bench_unit}.c"), replace(c_unit, "%s", escaped(f.bench_body) + times))
    let program = "options gen2\ndef call_fib(n : int) : int \{\n    return n\n\}\n[export]\ndef main() : int \{\n    print(\"%s\")\n    return call_fib(0)\n\}\n"
    fwrite(path_join(dir, "main.das"), replace(program, "%s", escaped(f.head + f.body)))
    fwrite(path_join(dir, "bench.das"), replace(program, "%s", escaped(f.head + f.bench_body) + times))
    let bin = path_join(dir, "rust")
    write_script(bin, "#!/bin/sh\nprev=\"\"\nfor a in \"$@\"; do\n    if [ \"$prev\" = \"--output-dir\" ]; then out=\"$a\"; fi\n    if [ \"$prev\" = \"--file\" ]; then src=\"$a\"; fi\n    prev=\"$a\"\ndone\nmkdir -p \"$out\"\ncase \"$src\" in\n    *bench*) cp {dir}/bench.das \"$out/{f.bench_unit}.das\" ;;\n    *) cp {dir}/main.das \"$out/{f.unit}.das\" ;;\nesac\n")
    return bin
}

// the real work folder of the project `name` as found: each entry with its size and modification
// time, "" without the folder
def private real_work(name : string) : string {
    let at = path_join(PROJECTS_WORK, name)
    if (!fexist(at)) {
        return ""
    }
    var lines : array<string>
    dir(at) $(entry) {
        if (entry != "." && entry != "..") {
            let st = stat(path_join(at, entry))
            lines |> push("{entry} {st.size} {st.mtime}")
        }
    }
    sort(lines)
    return join(lines, "\n")
}

[test]
def test_project_run(t : T?) {
    t |> run("--project wasm3 over a stand-in project to its end: both sides pass every lane, the rest kept, the work in the folder --work names") @(t : T?) {
        t |> with_scratch("cmp_projects_run") $(dir) {
            let real = real_work("wasm3")
            let bin = stand_in_project(dir, "wasm3")
            let results = path_join(dir, "results.json")
            fwrite(results, "\{\"perf\": \{\"samples\": 5\}, \"projects\": \{\"other\": \{\"x\": 1\}\}\}")
            var out : string
            with_env(bin, dir) {
                t |> equal(run_compare(["--project", "wasm3", "--samples", "1", "--out", results, "--work", path_join(dir, "work"), "--box", flag_box()], out), 0, out)
            }
            let js = json_of(t, fread(results))
            let entry = js?["projects"]?["wasm3"]
            t |> equal(js?["perf"]?["samples"] ?? 0, 5)
            t |> equal(js?["projects"]?["other"]?["x"] ?? 0, 1)
            t |> equal(entry?["native"]?["status"] ?? "", "pass")
            t |> equal(entry?["box"] ?? "", flag_box(), "--box reaches the project entry")
            for (side in ["ours", "rust"]) {
                t |> equal(join([for (lane in DAS_LANES); entry?[side]?["lanes"]?[lane]?["status"] ?? ""], " "), "pass pass pass pass", side)
                t |> equal(entry?["speed"]?[side]?["exe"]?["decode"]?["time"] ?? 0.0lf, 0.000006lf, side)
                t |> equal(entry?["code"]?[side]?["status"] ?? "", "ok", side)
            }
            t |> equal(entry?["speed"]?["native"]?["setup"]?["time"] ?? 0.0lf, 0.000003lf)
            t |> equal(entry?["speed"]?["rust"]?["aot"]?["decode"]?["time"] ?? 0.0lf, 0.000006lf)
            t |> success((entry?["functions"]?[1]?["ours"] ?? "") |> contains("call_fib"), out)
            t |> success((entry?["functions"]?[1]?["rust"] ?? "") |> starts_with("def call_fib("), out)
            t |> success(stat(path_join(dir, "work/wasm3")).is_dir, "no work folder under {dir}")
            t |> equal(real_work("wasm3"), real, "the real wasm3 work folder changed")
        }
    }
    t |> run("--project binjgb over a stand-in: its define reaches both builds, the bench timed against the native bench") @(t : T?) {
        t |> with_scratch("cmp_projects_binjgb") $(dir) {
            let bin = stand_in_project(dir, "binjgb")
            let results = path_join(dir, "results.json")
            fwrite(results, "\{\"projects\": \{\"wasm3\": \{\"x\": 1\}\}\}")
            var out : string
            with_env(bin, dir) {
                t |> equal(run_compare(["--project", "binjgb", "--samples", "1", "--out", results, "--work", path_join(dir, "work")], out), 0, out)
            }
            let js = json_of(t, fread(results))
            let entry = js?["projects"]?["binjgb"]
            t |> equal(js?["projects"]?["wasm3"]?["x"] ?? 0, 1)
            t |> equal(entry?["native"]?["status"] ?? "", "pass", out)
            t |> equal(entry?["speed"]?["native"]?["decode"]?["time"] ?? 0.0lf, 0.000006lf, out)
            for (side in ["ours", "rust"]) {
                t |> equal(join([for (lane in ["interp", "jit"]); entry?[side]?["lanes"]?[lane]?["status"] ?? ""], " "), "pass pass", side)
                t |> equal(entry?["speed"]?[side]?["interp"]?["decode"]?["time"] ?? 0.0lf, 0.000006lf, side)
            }
        }
    }
    t |> run("an unknown project, a checkout without it, and a mode beside it") @(t : T?) {
        t |> with_scratch("cmp_projects_cli") $(dir) {
            let bin = path_join(dir, "rust")
            write_script(bin, "#!/bin/sh\nexit 0\n")
            var out : string
            with_env(bin, dir) {
                t |> equal(run_compare(["--project", "doom"], out), 1, out)
                t |> success(out |> contains("--project takes one of wasm3, binjgb, h264bsd-mp4, plmpeg-stream, doomgeneric, quakegeneric, not `doom`"), out)
                t |> equal(run_compare(["--project", "wasm3"], out), 2, out)
                t |> success(out |> contains("the Rust checkout {dir} lacks the project"), out)
                mkdir_rec(path_join(dir, "tests/manual/wasm3/src"))
                fwrite(path_join(dir, "tests/manual/wasm3/src/all_host.c"), "int main(void) \{ return 0; \}\n")
                t |> equal(run_compare(["--project", "wasm3"], out), 2, out)
                t |> success(out |> contains("the Rust checkout lacks its canonical cases"), out)
                t |> equal(run_compare(["--project", "wasm3", "--samples", "-1"], out), 1, out)
                t |> success(out |> contains("--samples takes a count of at least 0, not -1"), out)
                t |> equal(run_compare(["--project", "wasm3", "--perf"], out), 1, out)
                t |> success(out |> contains("--perf runs alone"), out)
            }
            with_env("/nonexistent/c2das-rust", "") {
                t |> equal(run_compare(["--project", "wasm3"], out), 2, out)
            }
        }
    }
}

[test]
def test_project_run_native_sources(t : T?) {
    t |> run("--project h264bsd-mp4 over a stand-in: the native build from the case's own C files, not the unit") @(t : T?) {
        t |> with_scratch("cmp_projects_h264") $(dir) {
            let bin = stand_in_project(dir, "h264bsd-mp4")
            let results = path_join(dir, "results.json")
            fwrite(results, "\{\"projects\": \{\"wasm3\": \{\"x\": 1\}\}\}")
            var out : string
            with_env(bin, dir) {
                t |> equal(run_compare(["--project", "h264bsd-mp4", "--samples", "1", "--out", results, "--work", path_join(dir, "work")], out), 0, out)
            }
            let js = json_of(t, fread(results))
            let entry = js?["projects"]?["h264bsd-mp4"]
            t |> equal(js?["projects"]?["wasm3"]?["x"] ?? 0, 1)
            t |> equal(entry?["native"]?["status"] ?? "", "pass", out)
            t |> equal(entry?["speed"]?["native"]?["decode"]?["time"] ?? 0.0lf, 0.000006lf, out)
            t |> equal(join([for (lane in ["interp", "jit"]); entry?["rust"]?["lanes"]?[lane]?["status"] ?? ""], " "), "pass pass", out)
            t |> equal(entry?["speed"]?["rust"]?["interp"]?["decode"]?["time"] ?? 0.0lf, 0.000006lf, out)
            t |> equal(entry?["ours"]?["lanes"]?["interp"]?["reason"] ?? "", "line 1: got `bytes=3`, expected `bytes=4`", out)
        }
    }
}

let RENDER_CAPTURE = "\{\"projects\": \{\"w\": \{\"rust_commit\": \"0123456789abcdef\", \"date\": \"d\", \"samples\": 5, \"native_compiler\": \"clang 22\", \"lanes\": [\"interp\", \"aot\"], \"native\": \{\"status\": \"native\", \"reason\": \"clang exited 1\"\}, \"ours\": \{\"lanes\": \{\"interp\": \{\"status\": \"refused\", \"reason\": \"r\"\}, \"aot\": \{\"status\": \"refused\", \"reason\": \"r\"\}\}\}, \"rust\": \{\"lanes\": \{\"interp\": \{\"status\": \"pass\", \"reason\": \"\"\}, \"aot\": \{\"status\": \"skipped\", \"reason\": \"no args\"\}\}\}, \"speed\": \{\"native\": \{\"decode\": \{\"time\": 0.5\}\}, \"ours\": \{\"interp\": \{\"error\": \"bench: r\"\}, \"aot\": \{\"error\": \"the lane does not pass: refused\"\}\}, \"rust\": \{\"interp\": \{\"decode\": \{\"time\": 1.0\}\}, \"aot\": \{\"error\": \"timeout: the run took longer than 1 s\"\}\}\}, \"code\": \{\"rust\": \{\"status\": \"ok\", \"files\": 1, \"lines\": 9, \"runtime_lines\": 2, \"counts\": \{\"goto\": 4\}\}\}, \"functions\": [\{\"key\": \"w\", \"name\": \"f\", \"ours\": \"\", \"rust\": \"def f() \{\\n\}\"\}]\}\}\}"

[test]
def test_rendering(t : T?) {
    t |> run("the verdicts, the bench, the code, the reasons and the functions of a project") @(t : T?) {
        let js = json_of(t, RENDER_CAPTURE)
        let verdicts = projects_table(js)
        t |> success(verdicts |> contains("| w       | Ours | native |     refused | refused |"), verdicts)
        t |> success(verdicts |> contains("| w       | Rust | native |        pass | skipped |"), verdicts)
        let speed = project_speed_table(js)
        t |> success(speed |> contains("| w       | Ours | clang 22        | 0.500000 |     refused | refused |"), speed)
        t |> success(speed |> contains("| w       | Rust | clang 22        | 0.500000 |        2.00 | timeout |"), speed)
        let code = project_code_table(js)
        t |> success(code |> contains("| w       | Rust | ok   |     1 |     9 |             2 |"), code)
        t |> success(code |> contains("| w       | Ours |      |     - |     - |             - |          - |"), code)
        let reasons <- project_reasons(js)
        t |> equal(join(reasons, "\n"), "- w, native: clang exited 1\n- w, Ours, interpreter AOT: refused: r\n- w, Rust, AOT: skipped: no args")
        let text = projects_text(js)
        t |> success(text |> contains("Captured: w (Rust `0123456789ab`, d, unlabelled box)."), text)
        t |> success(text |> contains("lower is faster), 5 samples a cell:"), text)
        let untimed = projects_text(json_of(t, replace(RENDER_CAPTURE, "\"samples\": 5", "\"samples\": 0")))
        t |> success(untimed |> contains("lower is faster), not measured in this capture (`--samples 0`):"), untimed)
    }
    t |> run("a project's cap in its stamp, our side's own defines listed, the samples per project when they differ, the native cell's reason") @(t : T?) {
        let marked = replace(RENDER_CAPTURE, "\"samples\": 5,", "\"samples\": 5, \"address_cap\": \"4294967296\",")
        var js = json_of(t, replace(marked, "\"ours\": \{\"lanes\"", "\"ours\": \{\"defines\": [\"HOOK(...)=\", \"B=1\"], \"lanes\""))
        var projects = js?["projects"]
        var other = json_of(t, replace(RENDER_CAPTURE, "\"samples\": 5", "\"samples\": 0"))
        (projects.value as _object)["b"] = other?["projects"]?["w"]
        let text = projects_text(js)
        t |> success(text |> contains("Captured: b (Rust `0123456789ab`, d, unlabelled box); w (Rust `0123456789ab`, d, unlabelled box, 4 GiB address-space cap)."), text)
        t |> success(text |> contains("Defines of our side's sidecar alone") && text |> contains("\n- w, Ours: `-DHOOK(...)=` `-DB=1`\n") && !(text |> contains("- b, Ours: `")), text)
        t |> equal(samples_text(js), "samples a cell per project: b not measured, w 5")
        t |> equal("{cap_text("unlimited")}|{cap_text("")}|{cap_text("3221225472")}|{cap_text("1048576000")}|{cap_text("4G")}", "no address-space cap||3 GiB address-space cap|1000 MiB address-space cap|address-space cap 4G")
        let untimed = json_of(t, replace(RENDER_CAPTURE, "\"native\": \{\"decode\": \{\"time\": 0.5\}\}", "\"native\": \{\"error\": \"{NOT_TIMED}\"\}"))
        let speed = project_speed_table(untimed)
        t |> success(speed |> contains("| clang 22        | not measured |"), speed)
        t |> success(text |> contains("checked against the `expected.stdout` of its canonical case"), text)
        t |> success(text |> contains("#### `w`: `f`") && text |> contains("Ours: not found"), text)
        t |> success(has_value(rust_ahead(js), "- project w: Rust passes interpreter, ours does not."))
    }
    t |> run("a second project: its rows, its stamp and its functions beside the first's") @(t : T?) {
        var js = json_of(t, RENDER_CAPTURE)
        var projects = js?["projects"]
        (projects.value as _object)["b"] = json_of(t, write_json(projects?["w"]))
        let text = projects_text(js)
        t |> success(text |> contains("Captured: b (Rust `0123456789ab`, d, unlabelled box); w (Rust `0123456789ab`, d, unlabelled box)."), text)
        t |> success(text |> contains("| b       | Rust | native |        pass | skipped |") && text |> contains("| w       | Rust | native |        pass | skipped |"), text)
        t |> success(text |> contains("- b, Rust, AOT: skipped: no args") && text |> contains("| b       | Rust | ok   |     1 |"), text)
        t |> success(has_value(rust_ahead(js), "- project b: Rust passes interpreter, ours does not."))
    }
    t |> run("a bench cell without a cell or a native time, and a capture without projects") @(t : T?) {
        let native = json_of(t, "\{\"decode\": \{\"time\": 0.5\}\}")
        t |> equal(compiler_name("clang version 22.1.8 (https://x y)"), "clang version 22.1.8")
        t |> equal(compiler_name("gcc 14"), "gcc 14")
        t |> equal(bench_text_of(null, native), "n/a")
        t |> equal(bench_text_of(json_of(t, "\{\"decode\": \{\"time\": 1.0\}\}"), null), "n/a")
        t |> equal(bench_text_of(json_of(t, "\{\"error\": \"odd\"\}"), native), "odd")
        t |> equal(bench_text_of(JV({"error" => JV(NOT_TIMED)}), native), "not measured")
        let none = json_of(t, "\{\}")
        t |> equal(projects_text(none), "No project is captured yet.\n")
        t |> equal(project_speed_table(none), "")
        t |> equal(project_code_table(none), "")
    }
}
