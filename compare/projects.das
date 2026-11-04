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
require ../metrics/readability_count.das
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
//! bench one (none when ""), relative to `dir`, the clang flags both sides and the native build
//! take (`clang_extra` after the include folders and defines, `link_flags` the native link's),
//! `ours_defines` the defines of our side's sidecar alone (a hook the Rust runtime defines), the
//! fixture the program reads from its last argument, the output it must print, the translator
//! options the Rust side's canonical case passes, and the C functions shown side by side. The
//! output it must print is the canonical case `case_id`'s `expected.stdout` in the file `cases`,
//! read by `load_expected` into `expected` with the case's `translation_units` into `units` (the
//! program is those units when there are any, `tu` the one defining `main`) and the C files of the
//! native builds into `native_sources` and `native_bench_sources`; `bench_free_keys` are the keys of the lines the bench unit
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
    ours_defines : array<string>
    clang_extra : array<string>
    c_std : string
    native_flags : array<string>
    link_flags : array<string>
    fixture : string
    cases : string
    case_id : string
    expected : string
    units : array<string>
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
    var rows <- [Project(
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
        ours_defines <- ["c2da_rt_reset(...)="],
        c_std = "c11",
        native_flags <- ["-O2"],
        fixture = "fixtures/testsrc2_320x240.m1v",
        cases = path_join(checkout, CASES_FILE),
        case_id = "plmpeg-stream-320x240-std",
        functions <- ["plm_video_idct", "plm_video_decode_block"],
        bench_omitted_keys <- ["bytes"])]
    var engines <- engine_rows(manual_dir, path_join(checkout, CASES_FILE))
    rows |> reserve(length(rows) + length(engines))
    for (row in engines) {
        rows |> emplace(row)
    }
    return <- rows
}

// the game engines among the projects under `manual_dir`, `cases` the Rust checkout's cases
def private engine_rows(manual_dir, cases : string) : array<Project> {
    return <- [Project(
        name = "doomgeneric",
        dir = path_join(manual_dir, "doomgeneric"),
        tu = "src/doom_all.c",
        bench_tu = "src/doom_bench_all.c",
        include_dirs <- ["include", "upstream/doomgeneric/doomgeneric", "src"],
        c_std = "c11",
        native_flags <- ["-O2"],
        fixture = "fixtures/doom1.wad",
        cases = cases,
        case_id = "doomgeneric-demo1-std",
        rust_flags <- ["--das-option", "stack = 4194304"],
        functions <- ["R_DrawColumn", "R_DrawSpan"],
        bench_free_keys <- ["frames", "frame["]),
    Project(
        name = "quakegeneric",
        dir = path_join(manual_dir, "quakegeneric"),
        tu = "src/quake_entry.c",
        include_dirs <- ["upstream/quakegeneric/source", "src"],
        clang_extra <- ["-include", "engine_config.h"],
        c_std = "c11",
        native_flags <- ["-O2"],
        link_flags <- ["-lm"],
        fixture = "fixtures",
        cases = cases,
        case_id = "quakegeneric-demo1-std",
        rust_flags <- ["--das-option", "stack = 4194304"],
        functions <- ["D_DrawSpans8", "D_DrawZSpans"])]
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

//! `p.expected` read from its canonical case's `expected.stdout`, `p.units` from its
//! `translation_units`, and the C files of its native builds: the unit's the case's
//! `c_reference.sources`, else the units, else `p.tu`; the bench's the same without their last
//! (the entry) and with the case's `corpus.bench_c_entry` after them, else `p.bench_tu`; none when
//! `p.bench_tu` is "" (no bench unit), whatever the case names; "", or why it cannot be.
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

// the strings of the array `value`, none when it is no array; `bad` set when an element is not a
// string
def private read_paths(value : JsonValue?; var bad : bool&) : array<string> {
    if (value == null || !(value.value is _array)) {
        return <- array<string>()
    }
    for (s in value.value as _array) {
        bad = bad || s == null || !(s.value is _string)
    }
    return <- [for (s in value.value as _array); s ?? ""]
}

// the units of `p` and the C files of its native builds from its canonical case `c`, its units
// where the case names none; "", or why a named source is not a path
def private read_native_sources(var p : Project; c : JsonValue?) : string {
    var bad_units, bad_sources : bool
    p.units <- read_paths(c?["translation_units"], bad_units)
    var sources <- read_paths(c?["c_reference"]?["sources"], bad_sources)
    if (bad_units || bad_sources) {
        return "{p.cases}: the case {p.case_id} has a {bad_units ? "translation_units" : "c_reference.sources"} entry that is not a string"
    }
    let bench_entry = c?["corpus"]?["bench_c_entry"]
    let bench_units <- empty(p.bench_tu) ? array<string>() : [p.bench_tu]
    if (empty(sources)) {
        p.native_sources <- empty(p.units) ? [p.tu] : clone_to_move(p.units)
        p.native_bench_sources := bench_units
        return ""
    }
    p.native_sources <- sources
    if (empty(p.bench_tu) || bench_entry == null || !(bench_entry.value is _string)) {
        p.native_bench_sources := bench_units
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

//! The clang arguments of `p`: the C standard, each include folder, each define, `clang_extra`.
def clang_args(p : Project) : array<string> {
    var args <- ["-std={p.c_std}"]
    args |> push_from([for (d in p.include_dirs); "-I{project_path(p, d)}"], [for (d in p.defines); "-D{d}"], p.clang_extra)
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

//! The first line of `text` naming an error, else its first non-empty line, neither a shell's
//! report of a signal death (`shell_signal_line`: `Bus error`).
def error_line(text : string) : string {
    for (ln in split(text, "\n")) {
        if (to_lower(ln) |> contains("error") && !shell_signal_line(strip(ln))) {
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
//! error line read from the stderr, then the stdout.
def judge_run(rc : int; output, errors, expected : string; timeout : float) : Verdict {
    if (rc == popen_timed_out) {
        return Verdict(status = "timeout", reason = "the run took longer than {int(timeout)} s")
    }
    if (rc != 0) {
        let text = empty(errors) ? output : "{errors}\n{output}"
        let signal = signal_text(rc)
        let how = empty(signal) ? "exit {rc}" : signal
        return Verdict(status = "exit", reason = "{how}: {error_line(text)}")
    }
    let differ = first_difference(program_output(output), expected)
    return empty(differ) ? Verdict(status = "pass") : Verdict(status = "output", reason = differ)
}

//! The seconds a lane may take under `limits`: a run, or under `exe` and `aot` each build step and
//! the run.
def lane_timeout(lane : string; limits : LaneLimits) : float => lane == "exe" || lane == "aot" ? limits.build : limits.sample

//! `reason` with every path under the folder `root` written relative to it, so a capture names the
//! same file from any checkout (the JIT's warnings quote the module's absolute path).
def path_free(reason, root : string) : string => replace(reason, root |> ends_with("/") ? root : "{root}/", "")

// a verdict as the capture holds it, its paths under `root` relative
def private verdict_json(v : Verdict; root : string) : JsonValue? => JV({"status" => JV(v.status), "reason" => JV(path_free(v.reason, root))})

//! The command of a lane of `DAS_LANES` over the module `das_path` with `module_dirs` loaded and
//! the program given `args`: daslang over the module, or the binary `lane_binary` builds in `work`
//! and runs once `guarded` under `address_space` bytes (the `aot` host's program reads its
//! arguments after `--`); empty with `error` the build's
//! failure, prefixed `timeout: ` or `<lane> build: `.
def lane_argv(das_path, lane, work : string; module_dirs, args : array<string>; timeout : float; var error : string&; address_space : int64 = 0l) : array<string> {
    var argv : array<string>
    if (lane == "exe" || lane == "aot") {
        var why : string
        let bin = lane_binary(das_path, lane, work, module_dirs, args, why, timeout, address_space)
        if (empty(bin)) {
            error = why |> starts_with("the build or its run took longer") ? "timeout: {why}" : "{lane} build: {why}"
            return <- argv
        }
        argv |> push(bin)
        if (lane == "aot") {
            argv |> push("--")
        }
    } else {
        argv <- das_lane_command(das_path, lane == "jit" ? "-jit" : "", module_dirs)
        argv |> push("--")
    }
    argv |> push_from(args)
    return <- argv
}

//! Each lane of `DAS_LANES` over the module `das_path` with `module_dirs` loaded, the program
//! given `args`: every lane `refused` with `refusal` when it is set, `compile` when the module
//! fails `-compile-only` and `timeout` when that check runs past `limits.sample`, else the run
//! judged against `expected` within `lane_timeout`; each lane builds in `<work>/<lane>`.
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
    for (lane in DAS_LANES) {
        if (!empty(common.status)) {
            lanes[lane] = common
        } else {
            to_log(LOG_INFO, "{das_path}: {lane}\n")
            var error : string
            var inscope argv <- lane_argv(das_path, lane, path_join(work, lane), module_dirs, args, lane_timeout(lane, limits), error, limits.address_space)
            if (empty(argv)) {
                let timed_out = error |> starts_with("timeout: ")
                lanes[lane] = Verdict(status = timed_out ? "timeout" : "compile", reason = timed_out ? slice(error, length("timeout: ")) : error)
            } else {
                lanes[lane] = run_judged(guarded(argv, limits.address_space), expected, lane_timeout(lane, limits))
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
//! `guarded` under `limits`, its time lines dropped, checked by `bench_disagreement` against `p`'s expected output; "" when
//! it stands, else why not.
[arch(at="ARCHITECTURE_PROJECTS.md#speed")]
def native_bench_oracle(p : Project; bin, fixture : string; var oracle : string&; limits : LaneLimits = COMPARE_LIMITS) : string {
    var out, err : string
    let rc = run_split(guarded([bin, fixture], limits.address_space), limits.sample, out, err)
    if (rc != 0) {
        let v = judge_run(rc, out, err, "", limits.sample)
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
            var inscope argv <- lane_argv(das_path, lane, path_join(work, lane), module_dirs, args, lane_timeout(lane, limits), error, limits.address_space)
            cells[lane] = empty(argv) ? error_json(error) : bench_cells(guarded(argv, limits.address_space), expected, samples, lane_timeout(lane, limits))
        }
    }
    return <- cells
}

//! The native build of `p`'s C files `sources` into `bin` by the pinned clang with the project's
//! flags, `link_flags` after the files; "" when it built, else the compiler's first line.
def native_build(p : Project; sources : array<string>; bin : string) : string {
    var argv <- [default_clang()]
    argv |> push_from(clang_args(p), p.native_flags, [for (s in sources); project_path(p, s)])
    argv |> push_from(p.link_flags, ["-o", bin])
    var out : string
    let rc = run_and_capture(argv, out, COMPARE_LIMITS.build)
    return rc == 0 ? "" : "clang exited {rc}: {first_line(out)}"
}

// the file a `-include` of `p`'s clang arguments names, made absolute: found in the first of the
// project's include folders that holds it, else under the project folder
def private absolute_include(p : Project; name : string) : string {
    for (d in p.include_dirs) {
        let candidate = path_join(project_path(p, d), name)
        if (fexist(candidate)) {
            return absolute_path(candidate)
        }
    }
    return absolute_path(project_path(p, name))
}

// our side of one unit of `p`, or of its units (`units`, a program in the source layout):
// converted under `linux` into `out_dir` with a sidecar of the project's defines and
// `ours_defines`, its include
// folders, its forced includes (`-include` in `clang_extra`) and the project folder as the program
// root, each path absolute; the entry module with
// every file written into `files`, or "" with `refusal` the converter's first line
def private ours_module(p : Project; tu, out_dir : string; units : array<string>; var refusal : string&; var files : array<string>) : string {
    mkdir_rec(out_dir)
    let sidecar = path_join(out_dir, "{p.name}.c2das")
    let include_dirs <- [for (d in p.include_dirs); absolute_path(project_path(p, d))]
    let include_files <- [for (i, a in range(length(p.clang_extra)), p.clang_extra); absolute_include(p, a); where i > 0 && p.clang_extra[i - 1] == "-include"]
    var defines := p.defines
    defines |> push_from(p.ours_defines)
    fwrite(sidecar, write_json(JV({"defines" => JV(defines), "include_dirs" => JV(include_dirs), "include_files" => JV(include_files), "program_root" => JV(absolute_path(p.dir))})))
    var res <- empty(units) ? convert(project_path(p, tu), out_dir, "linux", "", sidecar) : convert_program([for (u in units); project_path(p, u)], out_dir, "linux", "", sidecar)
    refusal = res.ok ? "" : first_line(res.error)
    delete files
    files <- empty(refusal) && !empty(res.files) ? [for (f in res.files); path_join(out_dir, f)] : [res.das_path]
    return res.das_path
}

// the units `units` of `p` translated by `bin` into `out_dir` in the source layout, through a
// compilation database in `<out_dir>_db`
def private rust_units(p : Project; bin, out_dir : string; units : array<string>) : RustTranslation {
    let db = path_join("{out_dir}_db", "compile_commands.json")
    mkdir_rec("{out_dir}_db")
    write_unit_commands(db, [for (u in units); project_path(p, u)], clang_args(p), p.dir)
    return <- translate_db(bin, db, out_dir, "", p.rust_flags, PROJECT_TRANSLATE_TIMEOUT)
}

// the Rust side of one unit of `p`, translated by `bin` into `out_dir` with the case's options,
// or of its units (`units`, `rust_units`)
def private rust_module(p : Project; bin, tu, out_dir : string; units : array<string>; var refusal : string&; var files : array<string>) : string {
    rmdir_rec(out_dir)
    var t <- empty(units) ? translate_file(bin, project_path(p, tu), out_dir, p.rust_flags, clang_args(p), PROJECT_TRANSLATE_TIMEOUT) : rust_units(p, bin, out_dir, units)
    refusal = !t.ok ? t.error : empty(t.entry) ? "no module of {out_dir} defines main" : ""
    files := t.files
    return t.entry
}

// one side's lanes as the capture holds them, their paths under `root` relative
def private lanes_json(lanes : table<string; Verdict>; root : string) : JsonValue? => JV({for (lane in DAS_LANES); lane => verdict_json(lanes?[lane] ?? Verdict(), root)})

//! The code of one side: its files, non-blank lines and the readability counters over `entry`
//! (`measure_side`), over every module of `files` when there are several (`count_program`), the
//! Rust side's runtime lines split from its `c2da_` declarations by their prefix; `refused` with
//! `refusal` set.
[arch(at="ARCHITECTURE_PROJECTS.md#code")]
def side_code(files : array<string>; entry, refusal : string; rust : bool) : SideQuality {
    if (!empty(refusal)) {
        return SideQuality(status = "refused", error = refusal)
    }
    var side <- measure_side(files, entry)
    let modules <- [for (f in files); f; where f |> ends_with(".das")]
    if (side.status == "ok" && length(modules) > 1) {
        var failed : string
        var mc <- count_program(modules, failed)
        if (!empty(mc.error)) {
            side.status = "compile"
            side.error = "{base_name(failed)}: {first_line(strip(mc.error))}"
        }
        side.counts <- mc.counts
    }
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

//! The error of every bench cell of a project without a bench unit.
let NO_BENCH = "no bench: the project has no bench unit"

//! The error of every bench cell of a run that times nothing (`samples` 0).
let NOT_TIMED = "not measured: the run timed no bench (--samples 0)"

// the text of `files`, one after another
def private files_text(files : array<string>) : string => join([for (f in files); fread(f)], "\n")

// the bench builds of a project: the native bench binary or its build's failure, and each side's
// bench module or its refusal; `has` false for a project without a bench unit
struct private BenchModules {
    has : bool
    native : string
    native_error : string
    ours : string
    ours_refusal : string
    rust : string
    rust_refusal : string
}

// `p`'s bench unit built natively into `<work>/native`, converted into `<work>/ours_bench` and
// translated by `bin` into `<work>/rust_bench`; nothing for a project without one
def private bench_modules(p : Project; bin, work : string) : BenchModules {
    var b = BenchModules(has = !empty(p.native_bench_sources), native = path_join(work, "native/{p.name}_bench"))
    if (!b.has) {
        return b
    }
    b.native_error = native_build(p, p.native_bench_sources, b.native)
    var inscope ours_files, rust_files : array<string>
    let no_units : array<string>
    b.ours = ours_module(p, p.bench_tu, path_join(work, "ours_bench"), no_units, b.ours_refusal, ours_files)
    b.rust = rust_module(p, bin, p.bench_tu, path_join(work, "rust_bench"), no_units, b.rust_refusal, rust_files)
    return b
}

// the speed section of `p`'s entry, timed in the working folder: `NOT_TIMED` in every cell when
// `samples` is 0, `NO_BENCH` without a bench, else the native bench the oracle (`native_bench_oracle`) and timed, and each side's
// bench module timed where its lane in `ours_lanes` or `rust_lanes` passes (`side_speed`)
def private project_speed(p : Project; work : string; b : BenchModules; modules, args : array<string>; ours_lanes, rust_lanes : table<string; Verdict>; samples : int; limits : LaneLimits) : JsonValue? {
    if (samples == 0 || !b.has) {
        let why = samples == 0 ? NOT_TIMED : NO_BENCH
        return JV({
            "native" => error_json(why),
            "ours" => JV({for (lane in DAS_LANES); lane => error_json(why)}),
            "rust" => JV({for (lane in DAS_LANES); lane => error_json(why)})
        })
    }
    var oracle : string
    let error = empty(b.native_error) ? native_bench_oracle(p, b.native, args[0], oracle, limits) : b.native_error
    let no_oracle = empty(error) ? "" : "no native bench result: {error}"
    let no_modules : array<string>
    var native = empty(error) ? bench_cells(guarded([b.native, args[0]], limits.address_space), oracle, samples, limits.sample) : error_json(error)
    var ours <- side_speed(b.ours, empty(b.ours_refusal) ? no_oracle : b.ours_refusal, path_join(work, "ours_bench_run"), modules, args, ours_lanes, oracle, samples, limits)
    var rust <- side_speed(b.rust, empty(b.rust_refusal) ? no_oracle : b.rust_refusal, path_join(work, "rust_bench_run"), no_modules, args, rust_lanes, oracle, samples, limits)
    return JV({
        "native" => native,
        "ours" => JV(ours),
        "rust" => JV(rust)
    })
}

//! Project `p` through both sides, built in `work` and run with the working folder `<work>/cwd`,
//! the Rust side by `bin`, each bench lane timed over `samples` runs (none built or timed when
//! `samples` is 0), every native run, lane and bench sample `guarded` under `address_space` bytes
//! (0: no cap of its own): its capture entry.
[arch(at="ARCHITECTURE_PROJECTS.md#projects")]
def project_entry(p : Project; bin, work_dir : string; samples : int; stamps : Stamps; address_space : int64 = 0l) : JsonValue? {
    let limits = LaneLimits(sample = COMPARE_LIMITS.sample, build = COMPARE_LIMITS.build, address_space = address_space)
    let work = absolute_path(work_dir)
    rmdir_rec(work)
    mkdir_rec(work)
    let modules <- [for (d in CONVERTED_MODULES); absolute_path(d)]
    let no_modules : array<string>
    let args <- [absolute_path(project_path(p, p.fixture))]
    let native_bin = path_join(work, "native/{p.name}")
    mkdir_rec(path_join(work, "native"))
    var native = Verdict(status = "native", reason = native_build(p, p.native_sources, native_bin))
    var ours_refusal, rust_refusal : string
    var ours_files, rust_files : array<string>
    let ours_das = ours_module(p, p.tu, path_join(work, "ours"), p.units, ours_refusal, ours_files)
    let rust_das = rust_module(p, bin, p.tu, path_join(work, "rust"), p.units, rust_refusal, rust_files)
    let bench = samples > 0 ? bench_modules(p, bin, work) : BenchModules()
    let back = enter_working_folder(path_join(work, "cwd"))
    if (empty(native.reason)) {
        native = run_judged(guarded([native_bin, args[0]], address_space), p.expected, limits.sample)
        native.status = native.status == "pass" ? "pass" : "native"
    }
    let no_oracle = native.status == "pass" ? "" : "no native result: {native.reason}"
    let ours_lanes <- side_lanes(ours_das, empty(no_oracle) ? ours_refusal : no_oracle, path_join(work, "ours_run"), modules, args, p.expected, limits)
    let rust_lanes <- side_lanes(rust_das, empty(no_oracle) ? rust_refusal : no_oracle, path_join(work, "rust_run"), no_modules, args, p.expected, limits)
    let speed = project_speed(p, work, bench, modules, args, ours_lanes, rust_lanes, samples, limits)
    chdir(back)
    let ours_text = empty(ours_refusal) ? files_text(ours_files) : ""
    let rust_text = empty(rust_refusal) ? files_text(rust_files) : ""
    var functions <- [for (name in p.functions); JV({"key" => JV(p.name), "name" => JV(name), "ours" => JV(function_text(ours_text, name, "ours")), "rust" => JV(function_text(rust_text, name, "rust"))})]
    var entry <- {
        "rust_commit" => JV(stamps.rust_commit),
        "rust_commit_error" => JV(stamps.rust_commit_error),
        "daslang" => JV(stamps.daslang),
        "date" => JV(stamps.date),
        "cpu" => JV(stamps.cpu),
        "box" => JV(stamps.box),
        "samples" => JV(samples),
        "lanes" => JV(DAS_LANES),
        "native" => verdict_json(native, back),
        "native_compiler" => JV(first_line(captured([default_clang(), "--version"]))),
        "address_cap" => JV(address_space > 0l ? "{address_space}" : address_cap_of(fexist("/proc/self/limits") ? fread("/proc/self/limits") : "")),
        "ours" => JV({"error" => JV(ours_refusal), "lanes" => lanes_json(ours_lanes, back), "defines" => JV(p.ours_defines)}),
        "rust" => JV({"error" => JV(rust_refusal), "lanes" => lanes_json(rust_lanes, back)}),
        "speed" => speed,
        "code" => JV({
            "ours" => JV(side_code(ours_files, ours_das, ours_refusal, false)),
            "rust" => JV(side_code(rust_files, rust_das, rust_refusal, true))
        }),
        "functions" => JV(functions)
    }
    return JV(entry)
}

//! The address-space cap of a process whose `/proc/self/limits` reads `limits` (the soft `Max
//! address space`, which every child inherits): its bytes, `unlimited`, or "" when not read.
def address_cap_of(limits : string) : string {
    for (line in split(limits, "\n")) {
        if (line |> starts_with("Max address space")) {
            var inscope fields <- [for (f in split(slice(line, length("Max address space")), " ")); f; where !empty(f)]
            return empty(fields) ? "" : fields[0]
        }
    }
    return ""
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
