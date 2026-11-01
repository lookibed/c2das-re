options gen2

module projects public

require strings
require daslib/strings_boost
require daslib/fio
require daslib/json_boost
require ../converter/cir.das
require ../converter/tiers.das
require ../converter/dumper_a.das
require ../converter/pipeline.das
require ../suites/suite_files.das
require ../perf/perf_lanes.das
require ../perf/perf_measure.das
require rust_translator
require suite_compare
require perf_compare
require quality_compare

//! The real projects of the Rust translator's `tests/manual` through both translators: each
//! project's native build the oracle, both sides' lanes judged against the Rust side's expected
//! output, its bench entry timed, both outputs counted and sized, and a few hot functions side by
//! side (`compare/ARCHITECTURE_PROJECTS.md`).

let PROJECTS_WORK = "compare/work/projects"

//! the folder under a Rust checkout holding its real projects, and the file of its canonical cases
let MANUAL_DIR = "tests/manual"
let CASES_FILE = "tests/canonical/cases.json"

//! seconds the Rust translator may take over a project
let PROJECT_TRANSLATE_TIMEOUT = 600.0

//! One project, the facts of its README in the Rust repository: the translation unit and the
//! bench one, relative to `dir`, the clang flags both sides and the native build take, the fixture
//! the program reads from its last argument, the output it must print, the translator options
//! the Rust side's canonical case passes, and the C functions shown side by side. The output it
//! must print is the canonical case `case_id`'s `expected.stdout` in the file `cases`, read by
//! `load_expected` into `expected` with the C files of the native builds into `native_sources`
//! and `native_bench_sources`; `bench_free_keys` are the keys of the lines the bench unit
//! prints with a value of its own and the prefixes of the keys it prints beyond the expected
//! output, `bench_omitted_keys` the keys of the expected lines it does not print
//! (`bench_disagreement`).
struct Project {
    name : string
    dir : string
    tu : string
    bench_tu : string
    include_dirs : array<string>
    defines : array<string>
    c_std : string
    native_flags : array<string>
    fixture : string
    cases : string
    case_id : string
    expected : string
    native_sources : array<string>
    native_bench_sources : array<string>
    rust_flags : array<string>
    functions : array<string>
    bench_free_keys : array<string>
    bench_omitted_keys : array<string>
}

//! A lane's verdict: `pass`, else `refused`, `compile`, `exit`, `output`, `timeout` or `skipped`,
//! with the reason.
struct Verdict {
    status : string
    reason : string
}

//! The projects of the Rust checkout `checkout`, their expected output not yet read.
[arch(at="ARCHITECTURE_PROJECTS.md#projects")]
def project_table(checkout : string) : array<Project> {
    let manual_dir = path_join(checkout, MANUAL_DIR)
    return <- [Project(
        name = "wasm3",
        dir = path_join(manual_dir, "wasm3"),
        tu = "src/all_host.c",
        bench_tu = "src/all_host_bench.c",
        include_dirs <- ["include", "upstream/wasm3/source", "src"],
        c_std = "c11",
        native_flags <- ["-O2"],
        fixture = "fixtures/fib32.wasm",
        cases = path_join(checkout, CASES_FILE),
        case_id = "wasm3-fib32-std",
        rust_flags <- ["--das-option", "stack = 4194304"],
        functions <- ["op_Call", "call_fib"]),
    Project(
        name = "binjgb",
        dir = path_join(manual_dir, "binjgb"),
        tu = "src/binjgb_all.c",
        bench_tu = "src/binjgb_bench_all.c",
        include_dirs <- ["include", "upstream/binjgb/src", "src"],
        defines <- ["NDEBUG"],
        c_std = "c11",
        native_flags <- ["-O2"],
        fixture = "fixtures/cgb-acid2.gbc",
        cases = path_join(checkout, CASES_FILE),
        case_id = "binjgb-cgb-acid2-std",
        functions <- ["emulator_step_internal", "ppu_mode3_synchronize"],
        bench_free_keys <- ["frames", "frame["],
        bench_omitted_keys <- ["width", "height", "ticks"]),
    Project(
        name = "h264bsd-mp4",
        dir = path_join(manual_dir, "h264bsd-mp4"),
        tu = "src/h264_file_all.c",
        bench_tu = "src/h264_file_bench_all.c",
        include_dirs <- ["include", "upstream/h264bsd/src", "upstream/minimp4", "src"],
        c_std = "c11",
        native_flags <- ["-w", "-O2"],
        fixture = "fixtures/test_640x360.mp4",
        cases = path_join(checkout, CASES_FILE),
        case_id = "h264bsd-mp4-640x360-std",
        functions <- ["h264bsdProcessBlock", "FilterVerLumaEdge"],
        bench_omitted_keys <- ["bytes"]),
    Project(
        name = "plmpeg-stream",
        dir = path_join(manual_dir, "plmpeg-stream"),
        tu = "src/plmpeg_file_all.c",
        bench_tu = "src/plmpeg_file_bench_all.c",
        include_dirs <- ["include", "upstream", "fixtures", "src"],
        defines <- ["PLM_NO_STDIO"],
        c_std = "c11",
        native_flags <- ["-O2"],
        fixture = "fixtures/testsrc2_320x240.m1v",
        cases = path_join(checkout, CASES_FILE),
        case_id = "plmpeg-stream-320x240-std",
        functions <- ["plm_video_idct", "plm_video_decode_block"],
        bench_omitted_keys <- ["bytes"])]
}

//! The project `name` of the Rust checkout `checkout` into `p`; false when the table has none.
def find_project(checkout, name : string; var p : Project) : bool {
    var found = false
    for (row in project_table(checkout)) {
        if (row.name == name) {
            p := row
            found = true
        }
    }
    return found
}

//! `p.expected` read from its canonical case's `expected.stdout`, and the C files of its native
//! builds: the unit's the case's `c_reference.sources`, else `p.tu`; the bench's the same without
//! their last (the entry) and with the case's `corpus.bench_c_entry` after them, else
//! `p.bench_tu`; "", or why it cannot be.
[arch(at="ARCHITECTURE_PROJECTS.md#projects")]
def load_expected(var p : Project) : string {
    if (!fexist(p.cases)) {
        return "no {p.cases}: the Rust checkout lacks its canonical cases"
    }
    var error : string
    let js = read_json(fread(p.cases), error)
    if (js == null) {
        return "{p.cases} is not JSON: {error}"
    }
    let cases = js?["cases"]
    if (cases != null && cases.value is _array) {
        for (c in cases.value as _array) {
            let stdout = c?["expected"]?["stdout"]
            if ((c?["id"] ?? "") == p.case_id && stdout != null && stdout.value is _string) {
                p.expected = stdout ?? ""
                return read_native_sources(p, c)
            }
        }
    }
    return "{p.cases} has no case {p.case_id} with an expected.stdout"
}

// the C files of `p`'s native builds from its canonical case `c`, its units where the case names
// none; "", or why a named source is not a path
def private read_native_sources(var p : Project; c : JsonValue?) : string {
    let sources = c?["c_reference"]?["sources"]
    let bench_entry = c?["corpus"]?["bench_c_entry"]
    if (sources == null || !(sources.value is _array) || empty(sources.value as _array)) {
        p.native_sources <- [p.tu]
        p.native_bench_sources <- [p.bench_tu]
        return ""
    }
    for (s in sources.value as _array) {
        if (s == null || !(s.value is _string)) {
            return "{p.cases}: the case {p.case_id} has a c_reference.sources entry that is not a string"
        }
    }
    p.native_sources <- [for (s in sources.value as _array); s ?? ""]
    if (bench_entry == null || !(bench_entry.value is _string)) {
        p.native_bench_sources <- [p.bench_tu]
        return ""
    }
    p.native_bench_sources <- [for (s, i in p.native_sources, count()); s; where i + 1 < length(p.native_sources)]
    p.native_bench_sources |> push(bench_entry ?? "")
    return ""
}

//! `rel`, a path of project `p`, made absolute under its folder.
def project_path(p : Project; rel : string) : string => path_join(p.dir, rel)

//! `path` made absolute against the process's working folder.
def absolute_path(path : string) : string => path |> starts_with("/") ? path : path_join(getcwd(), path)

//! The process's working folder made `cwd`, made first: a program started after it that writes
//! into its working folder (doomgeneric's `./.savegame/`) writes there, so every path passed on
//! is absolute until the caller goes back to the folder it returns, the one before.
[arch(at="ARCHITECTURE_PROJECTS.md#projects")]
def enter_working_folder(cwd : string) : string {
    let back = getcwd()
    mkdir_rec(cwd)
    chdir(cwd)
    return back
}

//! The clang arguments of `p`: the C standard, each include folder, each define.
def clang_args(p : Project) : array<string> {
    var args <- ["-std={p.c_std}"]
    args |> push_from([for (d in p.include_dirs); "-I{project_path(p, d)}"], [for (d in p.defines); "-D{d}"])
    return <- args
}

//! The first line of `got` that differs from `expected`'s, both numbered from 1, a missing line
//! shown as `(none)`; "" when they are equal.
def first_difference(got, expected : string) : string {
    if (got == expected) {
        return ""
    }
    let a <- split(got, "\n")
    let b <- split(expected, "\n")
    var i = 0
    while (i < length(a) && i < length(b) && a[i] == b[i]) {
        i++
    }
    return "line {i + 1}: got `{i < length(a) ? a[i] : "(none)"}`, expected `{i < length(b) ? b[i] : "(none)"}`"
}

//! The first line of `text` naming an error, else its first non-empty line.
def error_line(text : string) : string {
    for (ln in split(text, "\n")) {
        if (to_lower(ln) |> contains("error")) {
            return strip(ln)
        }
    }
    return first_reported_line(text)
}

//! `argv` run within `timeout` seconds: its exit code, its stdout in `output` and its stderr in
//! `errors` (a program's oracle is its stdout: doomgeneric's engine logs to its stderr). The
//! stderr goes to a temporary file through `sh`; when none can be made, it stays in `output`.
[arch(at="ARCHITECTURE_PROJECTS.md#verdicts")]
def run_split(argv : array<string>; timeout : float; var output, errors : string&) : int {
    var error : string
    let err_file = create_temp_file("cmp_stderr", ".txt", error)
    if (!empty(error)) {
        errors = ""
        return run_and_capture(argv, output, timeout)
    }
    var full <- ["sh", "-c", "exec \"$@\" 2>\"$0\"", err_file]
    full |> push_from(argv)
    let rc = run_and_capture(full, output, timeout)
    errors = fread(err_file)
    remove(err_file)
    return rc
}

//! `argv` run within `timeout` seconds and judged against `expected` on its stdout.
def run_judged(argv : array<string>; expected : string; timeout : float) : Verdict {
    var out, err : string
    let rc = run_split(argv, timeout, out, err)
    return judge_run(rc, out, err, expected, timeout)
}

//! A run judged: `timeout` past `timeout` seconds, `exit` with the code and its error line,
//! `output` with the first differing line, else `pass`; the JIT's `[I]` lines are not output.
[arch(at="ARCHITECTURE_PROJECTS.md#verdicts")]
def judge_run(rc : int; output, expected : string; timeout : float) : Verdict => judge_run(rc, output, "", expected, timeout)

//! `judge_run` of a run whose stdout is `output` and stderr `errors`: the stdout judged, an exit's
//! error line read from the stdout, then the stderr.
def judge_run(rc : int; output, errors, expected : string; timeout : float) : Verdict {
    if (rc == popen_timed_out) {
        return Verdict(status = "timeout", reason = "the run took longer than {int(timeout)} s")
    }
    if (rc != 0) {
        let text = empty(errors) ? output : "{output}\n{errors}"
        return Verdict(status = "exit", reason = "exit {rc}: {error_line(text)}")
    }
    let differ = first_difference(program_output(output), expected)
    return empty(differ) ? Verdict(status = "pass") : Verdict(status = "output", reason = differ)
}

//! The seconds a lane may take under `limits`: a run, or under `exe` and `aot` each build step and
//! the run.
def lane_timeout(lane : string; limits : LaneLimits) : float => lane == "exe" || lane == "aot" ? limits.build : limits.sample

// a verdict as the capture holds it
def private verdict_json(v : Verdict) : JsonValue? => JV({"status" => JV(v.status), "reason" => JV(v.reason)})

//! The command of the `interp`, `jit` or `exe` lane over the module `das_path` with `module_dirs`
//! loaded and the program given `args`: daslang over the module, or the binary `exe_binary` builds
//! in `work`; empty with `error` the build's failure, prefixed `timeout: ` or `exe build: `.
def lane_argv(das_path, lane, work : string; module_dirs, args : array<string>; timeout : float; var error : string&) : array<string> {
    var argv : array<string>
    if (lane == "exe") {
        var why : string
        let bin = exe_binary(das_path, work, module_dirs, args, timeout, why)
        if (empty(bin)) {
            error = why |> starts_with("the build or its run took longer") ? "timeout: {why}" : "exe build: {why}"
            return <- argv
        }
        argv |> push(bin)
    } else {
        argv <- das_lane_command(das_path, lane == "jit" ? "-jit" : "", module_dirs)
        argv |> push("--")
    }
    argv |> push_from(args)
    return <- argv
}

//! Each lane of `DAS_LANES` over the module `das_path` with `module_dirs` loaded, the program
//! given `args`: every lane `refused` with `refusal` when it is set, `compile` when the module
//! fails `-compile-only` and `timeout` when that check runs past `limits.sample`, `aot` `skipped`
//! since its host passes no arguments, else the run judged against `expected` within
//! `lane_timeout`; each lane builds in `<work>/<lane>`.
[arch(at="ARCHITECTURE_PROJECTS.md#verdicts")]
def side_lanes(das_path, refusal, work : string; module_dirs, args : array<string>; expected : string; limits : LaneLimits) : table<string; Verdict> {
    var lanes : table<string; Verdict>
    var common = empty(refusal) ? Verdict() : Verdict(status = "refused", reason = refusal)
    if (empty(refusal)) {
        var text : string
        let rc = compile_entry(das_path, module_dirs, limits.sample, text)
        if (rc == popen_timed_out) {
            common = Verdict(status = "timeout", reason = "the compile check took longer than {limits.sample} s")
        } elif (rc != 0) {
            common = Verdict(status = "compile", reason = compile_error(text))
        }
    }
    let no_flags : array<string>
    for (lane in DAS_LANES) {
        if (!empty(common.status)) {
            lanes[lane] = common
        } elif (lane == "aot" && !empty(args)) {
            lanes[lane] = Verdict(status = "skipped", reason = "the aot host passes the program no arguments, and it reads its input from its last one")
        } elif (lane == "aot") {
            var output : string
            to_log(LOG_INFO, "{das_path}: {lane}\n")
            let rc = run_tier(das_path, lane, path_join(work, lane), output, module_dirs, lane_timeout(lane, limits), no_flags, args)
            lanes[lane] = judge_run(rc, output, expected, lane_timeout(lane, limits))
        } else {
            to_log(LOG_INFO, "{das_path}: {lane}\n")
            var error : string
            var inscope argv <- lane_argv(das_path, lane, path_join(work, lane), module_dirs, args, lane_timeout(lane, limits), error)
            if (empty(argv)) {
                lanes[lane] = Verdict(status = error |> starts_with("timeout: ") ? "timeout" : "compile", reason = error)
            } else {
                lanes[lane] = run_judged(argv, expected, lane_timeout(lane, limits))
            }
        }
    }
    return <- lanes
}

//! `setup_us=<n>` and `decode_us=<n>` of a bench run's `output`, in seconds; false without both.
def parse_bench(output : string; var setup, decode : double&) : bool {
    var have = 0
    for (ln in split(output, "\n")) {
        let line = strip(ln)
        if (line |> starts_with("setup_us=")) {
            setup = double(to_int64(slice(line, length("setup_us="))))
            setup /= 1000000.0lf
            have |= 1
        } elif (line |> starts_with("decode_us=")) {
            decode = double(to_int64(slice(line, length("decode_us="))))
            decode /= 1000000.0lf
            have |= 2
        }
    }
    return have == 3
}

//! A bench run's output without its two time lines, the text the expected output must equal.
def bench_text(output : string) : string => join(lines_without(join(lines_without(program_output(output), "setup_us="), "\n"), "decode_us="), "\n")

//! `samples` runs of `argv`, each judged against `expected` once its time lines are dropped:
//! `{setup, decode}`, each a cell of the times the program prints, or `{error}` at the first run
//! that does not pass.
[arch(at="ARCHITECTURE_PROJECTS.md#speed")]
def bench_cells(argv : array<string>; expected : string; samples : int; timeout : float) : JsonValue? {
    var setup, decode : array<double>
    setup |> reserve(samples)
    decode |> reserve(samples)
    for (_s in range(samples)) {
        var out, err : string
        let rc = run_split(argv, timeout, out, err)
        let v = judge_run(rc, bench_text(out), err, expected, timeout)
        if (v.status != "pass") {
            return error_json("{v.status}: {v.reason}")
        }
        var s, d : double
        if (!parse_bench(out, s, d)) {
            return error_json("no setup_us and decode_us lines: {first_line(out)}")
        }
        setup |> push(s)
        decode |> push(d)
    }
    return JV({"setup" => cell_json(cell_of(setup, 1l, 0)), "decode" => cell_json(cell_of(decode, 1l, 0))})
}

// a line's key: its text before the first `=` or `:`, the whole line without either
def private line_key(line : string) : string {
    let eq = find(line, "=")
    let colon = find(line, ":")
    let at = eq < 0 || (colon >= 0 && colon < eq) ? colon : eq
    return at < 0 ? line : slice(line, 0, at)
}

// whether `key` begins with an entry of `prefixes`
def private has_prefix(key : string; prefixes : array<string>) : bool {
    for (prefix in prefixes) {
        if (key |> starts_with(prefix)) {
            return true
        }
    }
    return false
}

//! Why the native bench run's text `bench` cannot be the bench's oracle: "" when it prints every
//! line of the expected output `expected` whose key is not in `omitted`, each equal to that line
//! unless its key is in `free`, and every other line it prints has a key beginning with an entry
//! of `free`.
[arch(at="ARCHITECTURE_PROJECTS.md#speed")]
def bench_disagreement(bench, expected : string; free, omitted : array<string>) : string {
    let printed <- {for (line in split(bench, "\n")); line_key(line) => line; where !empty(line)}
    let wanted <- {for (line in split(expected, "\n")); line_key(line) => line; where !empty(line)}
    for (want in split(expected, "\n")) {
        let key = line_key(want)
        if (empty(want) || has_value(omitted, key)) {
            continue
        }
        if (!key_exists(printed, key)) {
            return "the bench lacks `{want}`"
        }
        let got = printed?[key] ?? ""
        if (got != want && !has_value(free, key)) {
            return "got `{got}`, expected `{want}`"
        }
    }
    for (line in split(bench, "\n")) {
        if (!empty(line) && !key_exists(wanted, line_key(line)) && !has_prefix(line_key(line), free)) {
            return "the expected output has no `{line}`"
        }
    }
    return ""
}

//! The bench's oracle into `oracle`: the text of one run of the native bench `bin` on `fixture`,
//! its time lines dropped, checked by `bench_disagreement` against `p`'s expected output; "" when
//! it stands, else why not.
[arch(at="ARCHITECTURE_PROJECTS.md#speed")]
def native_bench_oracle(p : Project; bin, fixture : string; var oracle : string&) : string {
    var out, err : string
    let rc = run_split([bin, fixture], COMPARE_LIMITS.sample, out, err)
    if (rc != 0) {
        let v = judge_run(rc, out, err, "", COMPARE_LIMITS.sample)
        return "{v.status}: {v.reason}"
    }
    let text = bench_text(out)
    let disagreement = bench_disagreement(text, p.expected, p.bench_free_keys, p.bench_omitted_keys)
    if (!empty(disagreement)) {
        return "output: {disagreement}"
    }
    oracle = text
    return ""
}

//! The `exe` binary of `das_path` built in `work` with `module_dirs` loaded and run once with
//! `args`, as the exe lane builds it (`perf_lanes`'s `build_exe` loads `CONVERTED_MODULES` from
//! the working folder); "" with `error` set when the build leaves none.
def exe_binary(das_path, work : string; module_dirs, args : array<string>; timeout : float; var error : string&) : string {
    let bin = path_join(work, "{file_stem(das_path)}_exe")
    remove(bin)
    remove(bin + ".exe")
    var out : string
    let no_flags : array<string>
    let rc = run_tier(das_path, "exe", work, out, module_dirs, timeout, no_flags, args)
    if (rc == popen_timed_out) {
        error = "the build or its run took longer than {int(timeout)} s"
        return ""
    }
    let built = fexist(bin + ".exe") ? bin + ".exe" : bin
    if (!fexist(built)) {
        error = "the build exited {rc} and left no binary: {exe_build_line(out)}"
        return ""
    }
    return built
}

//! The bench cells of each das lane of the bench module `das_path`: `{error}` on every lane with
//! `refusal` set, and on a lane whose verdict in `lanes` is not `pass`; the interpreter and the
//! JIT run the module, `exe` its binary built once in `<work>/exe`, each within `lane_timeout`.
[arch(at="ARCHITECTURE_PROJECTS.md#speed")]
def side_speed(das_path, refusal, work : string; module_dirs, args : array<string>; lanes : table<string; Verdict>; expected : string; samples : int; limits : LaneLimits) : table<string; JsonValue?> {
    var cells : table<string; JsonValue?>
    for (lane in DAS_LANES) {
        let v = lanes?[lane] ?? Verdict(status = "skipped", reason = "not run")
        if (!empty(refusal)) {
            cells[lane] = error_json("bench: {refusal}")
        } elif (v.status != "pass") {
            cells[lane] = error_json("the lane does not pass: {v.status}")
        } else {
            var error : string
            var inscope argv <- lane_argv(das_path, lane, path_join(work, lane), module_dirs, args, lane_timeout(lane, limits), error)
            cells[lane] = empty(argv) ? error_json(error) : bench_cells(argv, expected, samples, lane_timeout(lane, limits))
        }
    }
    return <- cells
}

//! The native build of `p`'s C files `sources` into `bin` by the pinned clang with the project's
//! flags; "" when it built, else the compiler's first line.
def native_build(p : Project; sources : array<string>; bin : string) : string {
    var argv <- [default_clang()]
    argv |> push_from(clang_args(p), p.native_flags, [for (s in sources); project_path(p, s)], ["-o", bin])
    var out : string
    let rc = run_and_capture(argv, out, COMPARE_LIMITS.build)
    return rc == 0 ? "" : "clang exited {rc}: {first_line(out)}"
}

// our side of one unit of `p`: converted under `linux` into `out_dir` with a sidecar of the
// project's defines; the module, or "" with `refusal` the converter's first line
def private ours_module(p : Project; tu, out_dir : string; var refusal : string&) : string {
    mkdir_rec(out_dir)
    let sidecar = path_join(out_dir, "{p.name}.c2das")
    fwrite(sidecar, write_json(JV({"defines" => JV(p.defines)})))
    let res <- convert(project_path(p, tu), out_dir, "linux", "", sidecar)
    refusal = res.ok ? "" : first_line(res.error)
    return res.das_path
}

// the Rust side of one unit of `p`, translated by `bin` into `out_dir` with the case's options
def private rust_module(p : Project; bin, tu, out_dir : string; var refusal : string&; var files : array<string>) : string {
    rmdir_rec(out_dir)
    let t <- translate_file(bin, project_path(p, tu), out_dir, p.rust_flags, clang_args(p), PROJECT_TRANSLATE_TIMEOUT)
    refusal = !t.ok ? t.error : empty(t.entry) ? "no module of {out_dir} defines main" : ""
    files := t.files
    return t.entry
}

// one side's lanes as the capture holds them
def private lanes_json(lanes : table<string; Verdict>) : JsonValue? => JV({for (lane in DAS_LANES); lane => verdict_json(lanes?[lane] ?? Verdict())})

//! The code of one side: its files, non-blank lines and the readability counters over `entry`
//! (`measure_side`), the Rust side's runtime lines split from its `c2da_` declarations by their
//! prefix; `refused` with `refusal` set.
[arch(at="ARCHITECTURE_PROJECTS.md#code")]
def side_code(files : array<string>; entry, refusal : string; rust : bool) : SideQuality {
    if (!empty(refusal)) {
        return SideQuality(status = "refused", error = refusal)
    }
    var side <- measure_side(files, entry)
    if (rust) {
        let none : table<string>
        for (f in files) {
            var inscope blocks <- c2da_blocks(fread(f))
            for (name, lines in keys(blocks), values(blocks)) {
                if (is_runtime(name, none)) {
                    side.runtime_lines += lines
                } else {
                    side.program_c2da_lines += lines
                }
            }
        }
    }
    return <- side
}

//! Project `p` through both sides, built in `work` and run with the working folder `<work>/cwd`,
//! the Rust side by `bin`, each bench lane timed over `samples` runs: its capture entry.
[arch(at="ARCHITECTURE_PROJECTS.md#projects")]
def project_entry(p : Project; bin, work_dir : string; samples : int; stamps : Stamps) : JsonValue? {
    let work = absolute_path(work_dir)
    rmdir_rec(work)
    mkdir_rec(work)
    let modules <- [for (d in CONVERTED_MODULES); absolute_path(d)]
    let no_modules : array<string>
    let args <- [absolute_path(project_path(p, p.fixture))]
    let native_bin = path_join(work, "native/{p.name}")
    let native_bench = path_join(work, "native/{p.name}_bench")
    mkdir_rec(path_join(work, "native"))
    var native = Verdict(status = "native", reason = native_build(p, p.native_sources, native_bin))
    var native_bench_error = native_build(p, p.native_bench_sources, native_bench)
    var ours_refusal, rust_refusal, ours_bench_refusal, rust_bench_refusal : string
    let ours_das = ours_module(p, p.tu, path_join(work, "ours"), ours_refusal)
    var rust_files, rust_bench_files : array<string>
    let rust_das = rust_module(p, bin, p.tu, path_join(work, "rust"), rust_refusal, rust_files)
    let ours_bench = ours_module(p, p.bench_tu, path_join(work, "ours_bench"), ours_bench_refusal)
    let rust_bench = rust_module(p, bin, p.bench_tu, path_join(work, "rust_bench"), rust_bench_refusal, rust_bench_files)
    let back = enter_working_folder(path_join(work, "cwd"))
    if (empty(native.reason)) {
        native = run_judged([native_bin, args[0]], p.expected, COMPARE_LIMITS.sample)
        native.status = native.status == "pass" ? "pass" : "native"
    }
    let no_oracle = native.status == "pass" ? "" : "no native result: {native.reason}"
    let ours_lanes <- side_lanes(ours_das, empty(no_oracle) ? ours_refusal : no_oracle, path_join(work, "ours_run"), modules, args, p.expected, COMPARE_LIMITS)
    let rust_lanes <- side_lanes(rust_das, empty(no_oracle) ? rust_refusal : no_oracle, path_join(work, "rust_run"), no_modules, args, p.expected, COMPARE_LIMITS)
    var bench_expected : string
    if (empty(native_bench_error)) {
        native_bench_error = native_bench_oracle(p, native_bench, args[0], bench_expected)
    }
    var bench_native = empty(native_bench_error) ? bench_cells([native_bench, args[0]], bench_expected, samples, COMPARE_LIMITS.sample) : error_json(native_bench_error)
    let no_bench_oracle = empty(native_bench_error) ? "" : "no native bench result: {native_bench_error}"
    var ours_speed <- side_speed(ours_bench, empty(ours_bench_refusal) ? no_bench_oracle : ours_bench_refusal, path_join(work, "ours_bench_run"), modules, args, ours_lanes, bench_expected, samples, COMPARE_LIMITS)
    var rust_speed <- side_speed(rust_bench, empty(rust_bench_refusal) ? no_bench_oracle : rust_bench_refusal, path_join(work, "rust_bench_run"), no_modules, args, rust_lanes, bench_expected, samples, COMPARE_LIMITS)
    chdir(back)
    let ours_files <- empty(ours_refusal) ? [ours_das] : array<string>()
    let ours_text = empty(ours_refusal) ? fread(ours_das) : ""
    let rust_text = empty(rust_refusal) ? fread(rust_das) : ""
    var functions <- [for (name in p.functions); JV({"key" => JV(p.name), "name" => JV(name), "ours" => JV(function_text(ours_text, name, "ours")), "rust" => JV(function_text(rust_text, name, "rust"))})]
    var entry <- {
        "rust_commit" => JV(stamps.rust_commit),
        "rust_commit_error" => JV(stamps.rust_commit_error),
        "daslang" => JV(stamps.daslang),
        "date" => JV(stamps.date),
        "samples" => JV(samples),
        "lanes" => JV(DAS_LANES),
        "native" => verdict_json(native),
        "native_compiler" => JV(first_line(captured([default_clang(), "--version"]))),
        "ours" => JV({"error" => JV(ours_refusal), "lanes" => lanes_json(ours_lanes)}),
        "rust" => JV({"error" => JV(rust_refusal), "lanes" => lanes_json(rust_lanes)}),
        "speed" => JV({
            "native" => bench_native,
            "ours" => JV(ours_speed),
            "rust" => JV(rust_speed)
        }),
        "code" => JV({
            "ours" => JV(side_code(ours_files, ours_das, ours_refusal, false)),
            "rust" => JV(side_code(rust_files, rust_das, rust_refusal, true))
        }),
        "functions" => JV(functions)
    }
    return JV(entry)
}

//! The capture at `path` with its `projects` section's entry `name` set to `entry`, every other
//! project and section kept; "" or why the capture cannot be read.
[arch(at="ARCHITECTURE_PROJECTS.md#projects")]
def write_project(path, name : string; var entry : JsonValue?) : string {
    var error : string
    var root = capture_root(path, error)
    if (root == null) {
        return error
    }
    var section = root?["projects"]
    if (section == null || !(section.value is _object)) {
        var none : table<string; JsonValue?>
        section = JV(none)
    }
    (section.value as _object)[name] = entry
    return write_capture_section(path, "projects", section)
}

//! The lines a run logs of a project's entry: per side its lanes' verdicts, then the bench cells.
def project_lines(name : string; entry : JsonValue?) : array<string> {
    var lines : array<string>
    lines |> reserve(2 + 4 * length(DAS_LANES))
    lines |> push("{name}: native {entry?["native"]?["status"] ?? ""} {entry?["native"]?["reason"] ?? ""}")
    for (side in ["ours", "rust"]) {
        for (lane in DAS_LANES) {
            let v = entry?[side]?["lanes"]?[lane]
            lines |> push("{name}: {side} {lane}: {v?["status"] ?? ""} {v?["reason"] ?? ""}")
        }
    }
    for (side in ["native", "ours", "rust"]) {
        let cells = entry?["speed"]?[side]
        if (side == "native") {
            lines |> push("{name}: speed native decode {cells?["decode"]?["time"] ?? 0.0lf:.6f}s {cells?["error"] ?? ""}")
        } else {
            for (lane in DAS_LANES) {
                lines |> push("{name}: speed {side} {lane} decode {cells?[lane]?["decode"]?["time"] ?? 0.0lf:.6f}s {cells?[lane]?["error"] ?? ""}")
            }
        }
    }
    return <- lines
}
