options gen2

module projects public

require strings
require daslib/strings_boost
require daslib/fio
require daslib/json_boost
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

//! the folder under a Rust checkout holding its real projects
let MANUAL_DIR = "tests/manual"

//! seconds the Rust translator may take over a project
let PROJECT_TRANSLATE_TIMEOUT = 600.0

//! One project, the facts of its README in the Rust repository: the translation unit and the
//! bench one, relative to `dir`, the clang flags both sides and the native build take, the fixture
//! the program reads from its last argument, the output it must print, the translator options
//! the Rust side's canonical case passes, and the C functions shown side by side.
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
    expected : string
    rust_flags : array<string>
    functions : array<string>
}

//! A lane's verdict: `pass`, else `refused`, `compile`, `exit`, `output`, `timeout` or `skipped`,
//! with the reason.
struct Verdict {
    status : string
    reason : string
}

//! The projects of the Rust checkout's `manual_dir`.
[arch(at="ARCHITECTURE_PROJECTS.md#projects")]
def project_table(manual_dir : string) : array<Project> {
    var all : array<Project>
    all |> emplace(Project(
        name = "wasm3",
        dir = path_join(manual_dir, "wasm3"),
        tu = "src/all_host.c",
        bench_tu = "src/all_host_bench.c",
        include_dirs <- ["include", "upstream/wasm3/source", "src"],
        c_std = "c11",
        native_flags <- ["-O2"],
        fixture = "fixtures/fib32.wasm",
        expected = "bytes=62\nfib[1]=1\nfib[2]=1\nfib[5]=5\nfib[10]=55\nfib[15]=610\nfib[20]=6765\nfib[24]=46368\ncount=7\n",
        rust_flags <- ["--das-option", "stack = 4194304"],
        functions <- ["op_Call", "call_fib"]))
    return <- all
}

//! The project `name` of `manual_dir` into `p`; false when the table has none.
def find_project(manual_dir, name : string; var p : Project) : bool {
    var found = false
    for (row in project_table(manual_dir)) {
        if (row.name == name) {
            p := row
            found = true
        }
    }
    return found
}

//! `rel`, a path of project `p`, made absolute under its folder.
def project_path(p : Project; rel : string) : string => path_join(p.dir, rel)

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

//! A run judged: `timeout` past `timeout` seconds, `exit` with the code and its error line,
//! `output` with the first differing line, else `pass`; the JIT's `[I]` lines are not output.
[arch(at="ARCHITECTURE_PROJECTS.md#verdicts")]
def judge_run(rc : int; output, expected : string; timeout : float) : Verdict {
    if (rc == popen_timed_out) {
        return Verdict(status = "timeout", reason = "the run took longer than {int(timeout)} s")
    }
    if (rc != 0) {
        return Verdict(status = "exit", reason = "exit {rc}: {error_line(output)}")
    }
    let differ = first_difference(program_output(output), expected)
    return empty(differ) ? Verdict(status = "pass") : Verdict(status = "output", reason = differ)
}

//! The seconds a lane may take under `limits`: a run, or under `exe` and `aot` each build step and
//! the run.
def lane_timeout(lane : string; limits : LaneLimits) : float => lane == "exe" || lane == "aot" ? limits.build : limits.sample

// a verdict as the capture holds it
def private verdict_json(v : Verdict) : JsonValue? => JV({"status" => JV(v.status), "reason" => JV(v.reason)})

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
        } else {
            var output : string
            to_log(LOG_INFO, "{das_path}: {lane}\n")
            let rc = run_tier(das_path, lane, path_join(work, lane), output, module_dirs, lane_timeout(lane, limits), no_flags, args)
            lanes[lane] = judge_run(rc, output, expected, lane_timeout(lane, limits))
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
        var out : string
        let rc = run_and_capture(argv, out, timeout)
        let v = judge_run(rc, bench_text(out), expected, timeout)
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
        } elif (lane == "exe") {
            var error : string
            let bin = build_exe(das_path, path_join(work, lane), args, error, lane_timeout(lane, limits))
            var inscope argv <- [bin]
            argv |> push_from(args)
            cells[lane] = empty(bin) ? error_json("exe build: {error}") : bench_cells(argv, expected, samples, lane_timeout(lane, limits))
        } else {
            var inscope argv <- das_lane_command(das_path, lane == "jit" ? "-jit" : "", module_dirs)
            argv |> push("--")
            argv |> push_from(args)
            cells[lane] = bench_cells(argv, expected, samples, lane_timeout(lane, limits))
        }
    }
    return <- cells
}

//! The native build of `p`'s unit `tu` into `bin` by the pinned clang with the project's flags;
//! "" when it built, else the compiler's first line.
def native_build(p : Project; tu, bin : string) : string {
    var argv <- [default_clang()]
    argv |> push_from(clang_args(p), p.native_flags, [project_path(p, tu), "-o", bin])
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

//! Project `p` through both sides, built and run in `work`, the Rust side by `bin`, each bench
//! lane timed over `samples` runs: its capture entry.
[arch(at="ARCHITECTURE_PROJECTS.md#projects")]
def project_entry(p : Project; bin, work : string; samples : int; stamps : Stamps) : JsonValue? {
    rmdir_rec(work)
    mkdir_rec(work)
    let args <- [project_path(p, p.fixture)]
    let native_bin = path_join(work, "native/{p.name}")
    mkdir_rec(path_join(work, "native"))
    var native = Verdict(status = "native", reason = native_build(p, p.tu, native_bin))
    if (empty(native.reason)) {
        var out : string
        let rc = run_and_capture([native_bin, args[0]], out, COMPARE_LIMITS.sample)
        native = judge_run(rc, out, p.expected, COMPARE_LIMITS.sample)
        native.status = native.status == "pass" ? "pass" : "native"
    }
    let no_oracle = native.status == "pass" ? "" : "no native result: {native.reason}"
    var ours_refusal, rust_refusal, ours_bench_refusal, rust_bench_refusal : string
    let ours_das = ours_module(p, p.tu, path_join(work, "ours"), ours_refusal)
    var rust_files, rust_bench_files : array<string>
    let rust_das = rust_module(p, bin, p.tu, path_join(work, "rust"), rust_refusal, rust_files)
    let ours_lanes <- side_lanes(ours_das, empty(no_oracle) ? ours_refusal : no_oracle, path_join(work, "ours_run"), CONVERTED_MODULES, args, p.expected, COMPARE_LIMITS)
    let rust_lanes <- side_lanes(rust_das, empty(no_oracle) ? rust_refusal : no_oracle, path_join(work, "rust_run"), array<string>(), args, p.expected, COMPARE_LIMITS)
    let ours_bench = ours_module(p, p.bench_tu, path_join(work, "ours_bench"), ours_bench_refusal)
    let rust_bench = rust_module(p, bin, p.bench_tu, path_join(work, "rust_bench"), rust_bench_refusal, rust_bench_files)
    let native_bench = path_join(work, "native/{p.name}_bench")
    let native_bench_error = native_build(p, p.bench_tu, native_bench)
    var bench_native = empty(native_bench_error) ? bench_cells([native_bench, args[0]], p.expected, samples, COMPARE_LIMITS.sample) : error_json(native_bench_error)
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
        "ours" => JV({"error" => JV(ours_refusal), "lanes" => lanes_json(ours_lanes)}),
        "rust" => JV({"error" => JV(rust_refusal), "lanes" => lanes_json(rust_lanes)}),
        "speed" => JV({
            "native" => bench_native,
            "ours" => JV(side_speed(ours_bench, ours_bench_refusal, path_join(work, "ours_bench_run"), CONVERTED_MODULES, args, ours_lanes, p.expected, samples, COMPARE_LIMITS)),
            "rust" => JV(side_speed(rust_bench, rust_bench_refusal, path_join(work, "rust_bench_run"), array<string>(), args, rust_lanes, p.expected, samples, COMPARE_LIMITS))
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
