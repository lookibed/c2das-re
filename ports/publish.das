options gen2
// a compare project converts in this process: the pipeline parses clang's JSON dump below its own
// frames, and a deep expression tree overflows the default 16 KB context stack
options stack = 1048576

require strings
require daslib/strings_boost
require daslib/fio
require daslib/strings_convert
require daslib/clargs
require daslib/json_boost
require ../converter/pipeline.das
require ../converter/tiers.das
require ../converter/dumper_a.das
require ../perf/perf_lanes.das
require ports_render
require math
require ../perf/boxes.das
require ../converter/sidecar.das
require ../compare/compare_render.das
require ../metrics/criteria_file.das
require ../compare/projects.das
require ../compare/quality_compare.das
require variants
require ../compare/rust_translator.das
require puredoom
require ../doom/harness.das
require ../doom/fps.das

//! The publisher of the ports repository (`lookibed/c2das-ports`): for each program it knows,
//! the converted modules, the sidecar, the upstream license and a README with the release, the
//! generating commit, how to run it, which upstream tests pass and the perf tables of a capture it
//! measures; then the top-level README's projects table, and with `--commit` a commit in the
//! clone. Run from the repository root through `scripts/publish_ports.sh`. Beside Lua it publishes
//! every real project of compare's `project_table`, converted as compare converts our side, then
//! PureDOOM from the `doom/` harness.

//! one workload of a program: its name, its program arguments, the arguments as the README shows
//! them, whether it runs in the release's test-suite folder (else in the repository root), whether
//! a das lane's output must equal the native build's (else the exit code alone is compared), the
//! line every run, the native oracle's too, must print ("" for none), since a test suite that stops
//! early can exit 0, whether it is the startup row (no work: the program's load alone), and
//! whether it runs under `TIMED_LUA`, whose `c2das_work_s=` line every run must print
struct WorkloadSpec {
    name : string
    args : array<string>
    shown : string
    in_tests : bool
    compare_output : bool
    closing_line : string
    startup : bool
    timed : bool
}

//! one program the publisher knows: its harness folder, the composed modules it publishes, the
//! module the workloads run, the libraries its native build links, its upstream-test claims with
//! the c2das-re item that recorded them, and its workloads
struct Port {
    name : string
    title : string
    harness : string
    modules : array<tuple<stem : string; role : string>>
    runs : string
    libs : array<string>
    license_header : string
    claims : array<string>
    claims_item : string
    workloads : array<WorkloadSpec>
}

//! the lanes: the native build, each tier over the `readable` variant's modules, then each over the
//! `fast` variant's (`-fast`)
let ALL_LANES <- ["native", "interp", "jit", "exe", "aot", "interp-fast", "jit-fast", "exe-fast", "aot-fast"]
let STARTUP_ARGS <- ["-e", "print(1)"]
let WARM_UP_TIMEOUT = 3600.0
//! the wrapper that times a workload inside its process, and the line it reports the seconds on
let TIMED_LUA = "ports/lua/bench/timed.lua"
let WORK_MARK = "c2das_work_s="
let IDENTITY <- ["-c", "user.name=lookibed", "-c", "user.email=93531352+lookibed@users.noreply.github.com"]

def private bench(name : string) : WorkloadSpec => <- WorkloadSpec(name = name, args <- [get_full_file_name(TIMED_LUA), get_full_file_name("ports/lua/bench/{name}.lua")], shown = "bench/timed.lua bench/{name}.lua", compare_output = true, timed = true)

def private lua_port : Port => <- Port(
    name = "lua", title = "Lua", harness = "lua", runs = "lua", license_header = "lua.h", claims_item = "P5.1",
    modules <- [
        (stem = "lua", role = "the interpreter `lua`: the core, the standard libraries and `lua.c`"),
        (stem = "luac", role = "the compiler `luac`: the core, the auxiliary library and `luac.c`")
    ],
    libs <- ["-lm"],
    claims <- [
        "`lua -e \"print(1+1)\"` and a script over string, table and math print what the native build prints, under the interpreter and the JIT.",
        "`luac -o` writes the native build's bytecode byte for byte for every file of the release's test suite.",
        "A Lua error is caught as the native build catches it under the interpreter (`pcall`, `xpcall`, nested protected calls, errors in coroutines); under the JIT a protected call reports success and an uncaught error exits 0 with no message (c2das-re's `docs/probe-findings.md` F75, lookibed/daScript#30). Lua's own test suite passes under the interpreter, file by file and as one process (c2das-re's P5.3 and P5.4)."
    ],
    workloads <- [
        WorkloadSpec(name = "startup", args <- clone_to_move(STARTUP_ARGS), shown = "-e \"print(1)\"", compare_output = true, startup = true),
        bench("fib"),
        bench("binary_trees"),
        bench("nbody"),
        bench("spectral_norm"),
        WorkloadSpec(name = "test suite", args <- ["-e", "_port=true", get_full_file_name(TIMED_LUA), "all.lua"], shown = "-e \"_port=true\" bench/timed.lua all.lua", in_tests = true, closing_line = "final OK !!!", timed = true)
    ])

[CommandLineArgs]
struct Args {
    @clarg_doc = "the clone of the ports repository (default: $C2DAS_PORTS, else ../c2das-ports beside this repository)"
    repo : string = ""
    @clarg_doc = "publish only this program (default: every program the publisher knows: lua, the compare projects and puredoom)"
    program : string = ""
    @clarg_name = "no-convert"
    @clarg_doc = "skip the fetch and the conversion: publish what the harness's work/ folder holds"
    no_convert : bool
    @clarg_doc = "measure the workloads into a new capture and render the perf tables (default off: the perf method audit comes first)"
    perf : bool
    @clarg_doc = "samples per workload and lane, each its own process (default 5)"
    samples : int = 5
    @clarg_doc = "the das lanes to measure, comma-separated, out of interp,jit,exe,aot,interp-fast,jit-fast,exe-fast,aot-fast (default all): a lane runs the readable variant's modules, a -fast lane the fast variant's"
    lanes : string = "interp,jit,exe,aot,interp-fast,jit-fast,exe-fast,aot-fast"
    @clarg_doc = "seconds one sample may run before its cell fails (default 1800)"
    timeout : int = 1800
    @clarg_name = "allow-stale"
    @clarg_doc = "with --no-convert, publish a work/ folder whose conversion stamp is missing or names another commit than HEAD"
    allow_stale : bool
    @clarg_name = "allow-dirty"
    @clarg_doc = "publish from a c2das-re tree with uncommitted changes (the README names the commit -dirty)"
    allow_dirty : bool
    @clarg_doc = "the box the capture measures on, bench, PC or fx (default: the box of the CPU model, none for another CPU)"
    box : string = ""
    @clarg_doc = "commit the program's folder and the top-level README in the clone"
    commit : bool
    @clarg_doc = "push the clone's HEAD to origin after the commit (needs --commit)"
    push : bool
    @clarg_doc = "set by the publisher on the process it runs one program in: the file that process writes its outcome to, a line `published` or `failed <why>` each; the push and the failure line of the top-level README stay with the publisher that ran it"
    results : string = ""
    @clarg_name = "convert-variant"
    @clarg_doc = "set by the publisher on the process it converts one variant of the --program project in: the conversion, into the project's work folder, written to --results as JSON"
    convert_variant : string = ""
    @clarg_short = "?"
    @clarg_name = "show-help"
    @clarg_doc = "show this help and exit"
    show_help : bool
}

//! the c2das-re commit a conversion ran at, as `git describe --tags --always --dirty`, the full
//! sha and the commit date answered then; `recorded` false for a `--allow-stale` publish of a
//! work/ folder without a stamp, which names the tree's commit instead
struct Generation {
    describe : string
    sha : string
    date : string
    recorded : bool
}

def private git_in(dir : string; argv : array<string>; var out : string&) : int {
    var full <- ["git", "-C", dir]
    full |> push_from(argv)
    return run_and_capture(full, out, 600.0)
}

def private git_line(dir : string; argv : array<string>) : string {
    var out : string
    return git_in(dir, argv, out) == 0 ? strip(out) : ""
}

// a clone is a git work tree whose top level is the directory itself
def private is_clone(repo : string) : bool => git_line(repo, ["rev-parse", "--show-toplevel"]) == strip(captured(["realpath", repo]))

def private tree_generation : Generation => Generation(describe = git_line(".", ["describe", "--tags", "--always", "--dirty"]), sha = git_line(".", ["rev-parse", "HEAD"]), date = git_line(".", ["log", "-1", "--format=%cs"]), recorded = true)

// the command a reader runs to reproduce the publish, every flag that shapes the output named
def private publish_command(args : Args; port : Port) : string {
    var command = "scripts/publish_ports.sh --program {port.name}"
    if (args.no_convert) {
        command += " --no-convert"
    }
    if (args.allow_stale) {
        command += " --allow-stale"
    }
    if (args.perf) {
        command += " --perf --samples {args.samples} --lanes {args.lanes} --timeout {args.timeout}"
    }
    return command
}

// the program's fetched release: `fetch/<release tarball>/src` and `fetch/<tests tarball>`
def private sources_of(port : Port; release : Release) : string => path_join(port.harness, "fetch/{trim_suffix(base_name(release.tarballs[0].url), ".tar.gz")}/src")
def private tests_of(port : Port; release : Release) : string => path_join(port.harness, "fetch/{trim_suffix(base_name(release.tarballs[1].url), ".tar.gz")}")
def private log_of(port : Port) : string => path_join(port.harness, "work/publish_run.log")
// the folder the harness converts the variant `name` in, and the log of that conversion
def private variant_work(port : Port; name : string) : string => path_join(port.harness, "work/variants/{name}")
def private variant_log_of(port : Port; name : string) : string => path_join(variant_work(port, name), "publish_run.log")
def private stamp_of(port : Port) : string => path_join(port.harness, "work/publish.generation")
// the empty script the warm-up runs under `TIMED_LUA`
def private empty_script_of(port : Port) : string => get_full_file_name(path_join(port.harness, "work/bench/empty.lua"))
// the entry module of `stem` in the variant `v`'s conversion, in the layout its knob names
def private module_of(port : Port; v : Variant; stem : string) : string => path_join(layout_dir(variant_work(port, v.name), stem, layout_of(v)), "{stem}.das")

// the layout the variant `v` converts in: its `layout` knob, else the converter's default
def private layout_of(v : Variant) : string {
    for (k in v.knobs) {
        if (k.key == "layout") {
            return trim_suffix(trim_prefix(k.value, "\""), "\"")
        }
    }
    return "source"
}

// the variant a das lane runs (`fast` for a `-fast` lane, else `readable`) and its tier
def private lane_variant(lane : string) : string => lane |> ends_with("-fast") ? "fast" : "readable"
def private lane_tier(lane : string) : string => trim_suffix(lane, "-fast")

// the entry module of the program the workloads run in the conversion of `lane`'s variant
def private lane_module(port : Port; variants : array<Variant>; lane : string) : string {
    for (v in variants) {
        if (v.name == lane_variant(lane)) {
            return get_full_file_name(module_of(port, v, port.runs))
        }
    }
    return ""
}

// whether daslang runs `lane` over a converted module, which it caches in the folder it runs in;
// the exe and AOT lanes run a binary, the native lane the C build
def private runs_module(lane : string) : bool => lane != "native" && lane_tier(lane) != "exe" && lane_tier(lane) != "aot"

// the das files of a program's source or source-cut layout under `dir` (its modules and fragments), each
// relative to `dir`: the ones the conversion's `program.modules.txt` lists, so a file an earlier
// conversion left there stays out; none when the list is missing, and in the single layout, which
// writes no list, its one module `single`
def private tree_files(dir : string; single : string = "") : array<string> {
    if (!empty(single)) {
        return <- [single]
    }
    var files <- [for (ln in split(fread(path_join(dir, "program.modules.txt")), "\n")); strip(ln); where !empty(strip(ln))]
    sort(files)
    return <- files
}

// every file under `into` that `kept` (paths relative to it) does not name removed, so a layout's
// folder in the clone mirrors the conversion's module list; false when a removal fails
def private drop_unlisted(into : string; kept : array<string>) : bool {
    var stale : array<string>
    dir_rec(into) $(name, is_dir) {
        if (!is_dir && !has_value(kept, name)) {
            stale |> push(name)
        }
    }
    var ok = true
    for (rel in stale) {
        ok = remove(path_join(into, rel)) && ok
    }
    return ok
}

def private sidecar_of(port : Port) : string => path_join(port.harness, "{port.name}.c2das")

// the stamp a conversion leaves beside its output: the sha, the describe and the date, one a line
def private read_stamp(port : Port; var gen : Generation) : bool {
    let lines <- split(fread(stamp_of(port)), "\n")
    if (length(lines) < 3 || empty(lines[0])) {
        return false
    }
    gen = Generation(sha = lines[0], describe = lines[1], date = lines[2], recorded = true)
    return true
}

// the commit the published work/ folder was converted at: the stamp's, which under --no-convert
// must name the tree's HEAD unless --allow-stale
def private generation_for(args : Args; port : Port; var gen : Generation) : bool {
    let tree = tree_generation()
    if (read_stamp(port, gen)) {
        if (gen.sha == tree.sha || args.allow_stale) {
            return true
        }
        to_log(LOG_ERROR, "{port.name}: {stamp_of(port)} names the conversion at {gen.sha}, the tree is at {tree.sha}; run without --no-convert, or pass --allow-stale\n")
        return false
    }
    if (!args.allow_stale) {
        to_log(LOG_ERROR, "{port.name}: no {stamp_of(port)}, so no conversion of this tree is recorded; run without --no-convert, or pass --allow-stale\n")
        return false
    }
    gen = tree
    gen.recorded = false
    return true
}

// the fetch, then the harness's conversion of each variant in its layout with the native oracle and
// its run, each log kept beside the converted output for the README
def private run_harness(port : Port; variants : array<Variant>) : bool {
    // a stamp an earlier conversion left would name this HEAD over a work folder this run leaves
    // half written
    remove(stamp_of(port))
    var out : string
    if (run_and_capture(["bash", path_join(port.harness, "fetch.sh")], out, 3600.0) != 0) {
        to_log(LOG_ERROR, "{port.name}: {port.harness}/fetch.sh failed: {last_line(out)}\n")
        return false
    }
    for (v in variants) {
        var inscope argv <- daslang_cmd(CONVERTED_MODULES)
        argv |> push_from([path_join(port.harness, "run.das"), "--", "--native", "--run", "--variant", variant_path(port.name, v.name), "--layout", layout_of(v)])
        to_log(LOG_INFO, "{port.name}: " + join(argv, " ") + "\n")
        let rc = run_and_capture(argv, out, 7200.0)
        mkdir_rec(variant_work(port, v.name))
        fwrite(variant_log_of(port, v.name), out)
        if (rc != 0) {
            to_log(LOG_ERROR, "{port.name}: the conversion of the {v.name} variant exited {rc}; {variant_log_of(port, v.name)} holds its log\n")
            return false
        }
    }
    let gen = tree_generation()
    return write_or_log(stamp_of(port), "{gen.sha}\n{gen.describe}\n{gen.date}\n")
}

def private clipped(text : string) : string => length(text) > 160 ? slice(text, 0, 157) + "..." : text

//! the native lane's first sample: what every other sample and every das lane must reproduce
struct Oracle {
    rc : int
    output : string
}

// one unmeasured run of `TIMED_LUA` over the empty script `script`: the interpreter and the JIT
// compile the module on its first run in a folder and cache it there, so the run keeps the
// compile out of the cells, and under every lane it shows that the wrapper's clock and stderr
// work there; "" or why it failed
def private warm_up(argv : array<string>; cwd, script : string) : string {
    var warm <- clone_to_move(argv)
    warm |> push_from([get_full_file_name(TIMED_LUA), script])
    var out : string
    let rc = run_and_capture(in_folder(cwd, warm), out, WARM_UP_TIMEOUT)
    if (rc == popen_timed_out) {
        return "the warm-up run timed out after {int(WARM_UP_TIMEOUT)} s"
    }
    if (rc != 0) {
        return clipped(with_line("the warm-up run exited {rc}", first_reported_line(out)))
    }
    var rest : string
    var seconds = 0.0lf
    let missing = take_work_seconds(out, rest, seconds)
    return empty(missing) ? "" : clipped(with_line("the warm-up run of bench/timed.lua over an empty script printed {missing}", last_line(program_output(rest))))
}

// the work seconds `TIMED_LUA` reports in `text` into `seconds`, its `WORK_MARK` line taken out
// into `rest` wherever the merged streams put it; "" when exactly one line holds seconds, else
// what was printed instead (a program that prints the mark itself makes more than one)
def private take_work_seconds(text : string; var rest : string&; var seconds : double&) : string {
    let at = find(text, WORK_MARK)
    var marks = 0
    var next = at
    while (next >= 0) {
        marks++
        next = find(text, WORK_MARK, next + length(WORK_MARK))
    }
    if (marks != 1) {
        rest = text
        return marks == 0 ? "no `{WORK_MARK}` line" : "{marks} `{WORK_MARK}` lines"
    }
    let stop = find(text, "\n", at)
    let value_end = stop < 0 ? length(text) : stop
    let value = slice(text, at + length(WORK_MARK), value_end)
    rest = slice(text, 0, at) + slice(text, stop < 0 ? value_end : stop + 1)
    seconds = try_to_double(value) ?? -1.0lf
    return seconds >= 0.0lf ? "" : "`{WORK_MARK}{value}`, no seconds"
}

def private with_line(text, line : string) : string => empty(line) ? text : "{text}: {line}"

// the first line where a sample's output and the native build's part
def private output_parting(output, native : string) : string {
    let lines <- split(output, "\n")
    let expected <- split(native, "\n")
    var idx = 0
    while (idx < length(lines) && idx < length(expected) && lines[idx] == expected[idx]) {
        idx++
    }
    let got = idx < length(lines) ? "`{lines[idx]}`" : "nothing"
    let want = idx < length(expected) ? "`{expected[idx]}`" : "nothing"
    return "line {idx + 1} prints {got} where the native build prints {want}"
}

// one run of the command `full`, timed as a whole process and, for a workload under `TIMED_LUA`,
// inside it by the wrapper's line, which the comparison does not see, into `cell`; a run that
// differs from `oracle` (the native lane's first, when `oracle.rc` is not -1), that leaves out the
// closing line `spec` names, or that prints no work seconds under the wrapper, fails the cell, which
// keeps the samples taken, the failing one last; false when the cell failed
[arch(at="ARCHITECTURE.md#measurement")]
def private measure_sample(full : array<string>; timeout : int; spec : WorkloadSpec; var oracle : Oracle; var cell : LaneCell) : bool {
    var out : string
    var seconds = 0.0lf
    let started = ref_time_ticks()
    // the clock stops at the end of the child's output, which it closes on exit: popen's
    // timeout watchdog wakes every 100 ms, so the return itself lags the exit by up to that
    let rc = unsafe(popen_argv(full, float(timeout), $(f) {
        if (f != null) {
            out = fread(f)
        }
        seconds = double(get_time_nsec(started)) / 1000000000.0lf
    }))
    var rest = out
    var work = 0.0lf
    let missing = spec.timed ? take_work_seconds(out, rest, work) : ""
    if (spec.timed && empty(missing)) {
        cell.work_samples |> push(work)
    }
    let output = program_output(rest)
    cell.samples |> push(seconds)
    if (rc == popen_timed_out) {
        cell.error = "timed out after {timeout} s"
    } elif (oracle.rc == -1 && rc != 0) {
        cell.error = clipped(with_line("exited {rc}", first_reported_line(output)))
    } elif (oracle.rc != -1 && rc != oracle.rc) {
        cell.error = clipped(with_line("exited {rc} where the native build exits {oracle.rc}", first_reported_line(output)))
    } elif (oracle.rc != -1 && spec.compare_output && output != oracle.output) {
        cell.error = clipped(output_parting(output, oracle.output))
    } elif (!empty(spec.closing_line) && !has_value(split(output, "\n"), spec.closing_line)) {
        cell.error = clipped(with_line("exited {rc} without the line `{spec.closing_line}`; its last line", last_line(output)))
    } elif (!empty(missing)) {
        cell.error = clipped(with_line("exited {rc} under bench/timed.lua with {missing}; its last line", last_line(output)))
    } elif (oracle.rc == -1) {
        oracle = Oracle(rc = rc, output = output)
    }
    return empty(cell.error)
}

// a standing cell's median and spread over its samples, and under the wrapper its work time's
def private settle_cell(spec : WorkloadSpec; var cell : LaneCell) {
    cell.time = median_of(cell.samples)
    cell.spread = spread_of(cell.samples, cell.time)
    if (spec.timed) {
        cell.work_time = median_of(cell.work_samples)
        cell.work_time_spread = spread_of(cell.work_samples, cell.work_time)
    }
}

// a key line of `path`: its size, then its mtime when `stamped`, else its text's hash
def private key_line(path : string; stamped : bool) : string {
    let st = stat(path)
    let mark = stamped ? "{st.mtime}" : "{hash(fread(path))}"
    return "{path} {int64(st.size)} {mark}"
}

// the key of the native build `command` of `c_paths`: the command, then every `.c` and `.h` file of
// the C files' folders with its size and its text's hash, so an edited source or header builds again
[arch(at="ARCHITECTURE.md#measurement")]
def private native_build_key(command, c_paths : array<string>) : string {
    var lines <- ["command {join(command, " ")}"]
    var dirs <- [for (c_path in c_paths); dir_name(c_path)]
    sort(dirs)
    var seen = ""
    for (d in dirs) {
        if (d == seen) {
            continue
        }
        seen = d
        var names : array<string>
        dir(d) $(name) {
            if ((name |> ends_with(".c") || name |> ends_with(".h")) && stat(path_join(d, name)).is_reg) {
                names |> push(name)
            }
        }
        sort(names)
        lines |> push_from([for (name in names); key_line(path_join(d, name), false)])
    }
    return join(lines, "\n") + "\n"
}

// the native lane's build of `c_paths` with `libs` into `bin`: the binary an earlier build left is
// reused while `<bin>.key` holds this build's `native_build_key` and the binary's own size and
// mtime, else it is built again and the key written once the build succeeds; the build's exit code,
// 0 for a reused binary, its output into `out`
def private native_build(c_paths : array<string>; bin : string; libs : array<string>; var out : string&) : int {
    let command <- native_build_command(c_paths, bin, libs)
    let key = native_build_key(command, c_paths)
    let key_path = bin + ".key"
    if (stat(bin).is_reg && fexist(key_path) && fread(key_path) == key + key_line(bin, true)) {
        to_log(LOG_INFO, "native build reused: {bin}\n")
        return 0
    }
    remove(key_path)
    remove(bin)
    let rc = run_and_capture(command, out, 3600.0)
    if (rc == 0 && stat(bin).is_reg) {
        fwrite(key_path, key + key_line(bin, true))
    }
    return rc
}

//! one lane ready to measure: the argv the program's arguments follow, or the reason it is not
struct LaneRun {
    argv : array<string>
    error : string
}

// the cell of `run`'s lane readied for its samples of `spec`: the lane's error, `no native run to
// compare with` for a das lane once native's first sample left no oracle, `no <shown>` for a suite
// row without the folder `tests` (`shown` as the README names it), the warm-up's error in that
// folder for a lane with a module cache; else `argv` the command a sample runs
def private ready_cell(run : LaneRun; spec : WorkloadSpec; oracle : Oracle; tests, shown, empty_script : string; var cell : LaneCell; var argv : array<string>) {
    if (!empty(run.error)) {
        cell.error = run.error
    } elif (cell.lane != "native" && oracle.rc == -1) {
        cell.error = "no native run to compare with"
    } elif (spec.in_tests && !stat(tests).is_dir) {
        cell.error = "no {shown}"
    } else {
        // the test-suite folder has a module cache of its own to warm
        if (spec.in_tests && runs_module(cell.lane)) {
            cell.error = warm_up(run.argv, tests, empty_script)
        }
        var inscope full <- clone_to_move(run.argv)
        full |> push_from(spec.args)
        argv <- in_folder(spec.in_tests ? tests : "", full)
    }
}

// every lane of `lanes` built once: native from the sources the harness's program manifest lists,
// the das lanes over the converted module, the program's arguments after `--` for the interpreter
// and the JIT
def private build_lanes(port : Port; variants : array<Variant>; lanes : array<string>; var into : Capture) : table<string; LaneRun> {
    var runs : table<string; LaneRun>
    let work = path_join(port.harness, "work")
    let bench_work = path_join(work, "bench")
    mkdir_rec(bench_work)
    let empty_script = empty_script_of(port)
    fwrite(empty_script, "")
    let manifest = path_join(work, "{port.runs}.program.json")
    let modules <- [for (dir in CONVERTED_MODULES); get_full_file_name(dir)]
    into.lanes |> reserve(length(lanes))
    for (lane in lanes) {
        var run : LaneRun
        var shown : string
        if (lane == "native") {
            let bin = path_join(bench_work, "{port.runs}_native")
            var error : string
            let input <- read_program_input(manifest, "linux", error)
            var out : string
            if (!empty(error)) {
                run.error = clipped(error)
            } elif (native_build(input.c_paths, bin, port.libs, out) != 0) {
                run.error = clipped(with_line("the build failed", first_reported_line(out)))
            }
            run.argv <- [get_full_file_name(bin)]
            var inscope listed <- empty(error) ? [for (c_path in input.c_paths); base_name(c_path)] : ["<the C files of {manifest}>"]
            shown = join(native_build_command(listed, "{port.runs}_native", port.libs), " ")
        } elif (runs_module(lane)) {
            let flag = lane_tier(lane) == "jit" ? "-jit" : ""
            run.argv <- das_lane_command(lane_module(port, variants, lane), flag, modules)
            run.argv |> push("--")
            shown = join(["daslang -load_module <c2das-re>/dasCRuntime -load_module <c2das-re>/c_runtime", flag, "{lane_variant(lane)}/{port.runs}/{port.runs}.das --"], " ") |> replace("  ", " ")
            run.error = warm_up(run.argv, "", empty_script)
        } else {
            var error : string
            // each variant's binaries in a folder of their own, so the two lanes of a tier do not share one
            let das_path = lane_module(port, variants, lane)
            let lane_work = path_join(bench_work, lane_variant(lane))
            mkdir_rec(lane_work)
            let bin = lane_tier(lane) == "exe" ? build_exe(das_path, lane_work, STARTUP_ARGS, error) : build_aot(das_path, lane_work, STARTUP_ARGS, error)
            run.error = clipped(error)
            if (!empty(bin)) {
                run.argv <- [get_full_file_name(bin)]
                // the AOT host is no standalone exe: the program's arguments follow `--`, as under daslang
                if (lane_tier(lane) == "aot") {
                    run.argv |> push("--")
                }
                if (empty(run.error)) {
                    run.error = warm_up(run.argv, "", empty_script)
                }
            }
            shown = lane_tier(lane) == "exe" ? "daslang -exe {lane_variant(lane)}/{port.runs}/{port.runs}.das, the binary run" : "the -ctx context of {lane_variant(lane)}/{port.runs}/{port.runs}.das and its host compiled by clang++ -O3 (c2das-re converter/tiers.das), the binary run with `--`"
        }
        into.lanes |> push(Lane(name = lane, command = shown, error = run.error))
        let reported = empty(run.error) ? join(run.argv, " ") : "not yet: {run.error}"
        to_log(LOG_INFO, "{port.name}/{lane}: {reported}\n")
        runs[lane] <- run
    }
    return <- runs
}

// a capture of every workload under every lane of `lanes`, written into the clone
def private measure_program(args : Args; port : Port; variants : array<Variant>; release : Release; lanes : array<string>; repo_dir : string; gen : Generation) : bool {
    var measured = Capture(program = port.name, commit = gen.sha, command = publish_command(args, port), samples = args.samples, timeout = args.timeout)
    let cpu = cpu_name()
    measured.machine = Machine(arch = strip(captured(["uname", "-m"])), cpu = cpu, box = capture_box(args.box, cpu), clang_path = default_clang())
    tool_versions(measured.machine.clang, measured.machine.daslang)
    var runs <- build_lanes(port, variants, lanes, measured)
    let tests = get_full_file_name(tests_of(port, release))
    measured.workloads |> reserve(length(port.workloads))
    measured.cells |> reserve(length(port.workloads) * length(lanes))
    for (spec in port.workloads) {
        measured.workloads |> push(Workload(name = spec.name, args = spec.shown, startup = spec.startup))
        var oracle = Oracle(rc = -1)
        var inscope cells : array<LaneCell>
        var inscope argvs : array<array<string>>
        cells |> reserve(length(lanes))
        argvs |> reserve(length(lanes))
        for (lane in lanes) {
            var cell = LaneCell(workload = spec.name, lane = lane)
            cell.samples |> reserve(args.samples)
            cell.work_samples |> reserve(spec.timed ? args.samples : 0)
            cells |> emplace(cell)
            argvs |> emplace(array<string>())
        }
        // the samples interleave: each round takes one sample of every standing lane, a lane
        // readied at its turn in the first round, after native's first sample
        for (round in range(args.samples)) {
            for (i in sample_order(length(lanes), round)) {
                if (round == 0) {
                    runs |> get(lanes[i]) $(run) {
                        ready_cell(run, spec, oracle, tests, tests_of(port, release), empty_script_of(port), cells[i], argvs[i])
                    }
                }
                if (empty(cells[i].error)) {
                    measure_sample(argvs[i], args.timeout, spec, oracle, cells[i])
                }
            }
        }
        for (cell in cells) {
            if (empty(cell.error)) {
                settle_cell(spec, cell)
            }
            let reported = empty(cell.error) ? "{cell.time:.3f} s" : "not yet: {cell.error}"
            to_log(LOG_INFO, "{port.name}/{spec.name}/{cell.lane}: {reported}\n")
            measured.cells |> emplace(cell)
        }
    }
    // the timestamp and the file name both name the end of the run
    let ended <- split(strip(captured(["date", "-u", "+%Y-%m-%d %H:%M UTC|%Y-%m-%dT%H%M%SZ"])), "|")
    if (length(ended) != 2) {
        to_log(LOG_ERROR, "ports: `date -u` answered {join(ended, "|")}\n")
        return false
    }
    measured.timestamp = ended[0]
    let perf_dir = path_join(repo_dir, "perf")
    mkdir_rec(perf_dir)
    return write_or_log(path_join(perf_dir, "capture_{ended[1]}.json"), write_json(JV(measured)) + "\n")
}

// the latest capture under `<dir>/perf/`, by its name's timestamp, into `into` with `found`;
// false when that capture is not JSON
def private latest_capture(dir : string; var into : Capture; var found : bool&) : bool {
    var latest = ""
    let perf_dir = path_join(dir, "perf")
    if (stat(perf_dir).is_dir) {
        dir(perf_dir) $(name) {
            if (name |> starts_with("capture_") && name |> ends_with(".json") && name > latest) {
                latest = name
            }
        }
    }
    found = !empty(latest)
    if (!found) {
        return true
    }
    var error : string
    let js = read_json(fread(path_join(perf_dir, latest)), error)
    if (js == null) {
        to_log(LOG_ERROR, "ports: {perf_dir}/{latest} is not JSON: {error}\n")
        return false
    }
    delete into
    into <- from_JV(js, type<Capture>)
    return true
}

def private generation_line(gen : Generation) : string {
    let commit = "`{gen.describe}` (`{gen.sha}`, committed {gen.date})"
    return gen.recorded ? "Generated by c2das-re {commit}" : "Generated by c2das-re at an unrecorded commit: published with `--allow-stale` from {commit}"
}

// the program's README; `captured` when its directory holds a capture the perf section renders
def private readme_text(port : Port; variants : array<Variant>; release : Release; gen : Generation; command, variants_text, perf_text, harness_log : string; captured : bool) : string {
    return build_string() $(var w) {
        w |> write("# {port.name}\n\n")
        w |> write("{port.title} {release.version} converted to daslang by [c2das-re](https://github.com/lookibed/c2das-re). ")
        w |> write("Everything in this directory is generated by `{command}` in c2das-re; never edit it, a fix belongs in c2das-re.\n\n")
        w |> write("## Variants\n\n{variants_text}\n")
        w |> write("## Files\n\n")
        for (v in variants) {
            for (m in port.modules) {
                w |> write("- `{v.name}/{m.stem}/` - {m.role}, the {v.name} variant, {LAYOUT_WORDS?[layout_of(v)] ?? layout_of(v)}; `{v.name}/{m.stem}/{m.stem}.das` holds `main`.\n")
            }
            w |> write("- `{v.name}/{port.name}.c2das` - the sidecar the {v.name} variant was converted under, `{v.name}/variant.json` - its knobs with the reason and the numbers behind each.\n")
        }
        w |> write("- `LICENSE` - {port.title}'s license, from `src/{port.license_header}` of the release; the conversion is a derived work.\n")
        if (captured) {
            w |> write("- `bench/` - the benchmark scripts the tables below run, and `timed.lua`, which runs each and reports its work seconds measured inside the process.\n")
            w |> write("- `perf/capture_*.json` - every capture the tables were rendered from, every sample of every lane.\n\n")
        } else {
            w |> write("- `bench/` - the benchmark scripts the perf tables will run, and `timed.lua`, which runs each and reports its work seconds measured inside the process.\n\n")
        }
        w |> write("## Source\n\n")
        w |> write("- Upstream: {port.title} {release.version}\n")
        for (t in release.tarballs) {
            w |> write("  - {t.url} (sha256 `{t.sha256}`)\n")
        }
        w |> write("- {generation_line(gen)}\n\n")
        w |> write("## Running\n\n")
        w |> write("The modules require c2das-re's `crt` and `c_runtime` modules: a c2das-re checkout at the commit above, ")
        w |> write("with the daScript its `VERSIONS.md` pins built and `scripts/build_crt.sh` run. With `<c2das-re>` that checkout:\n\n```\n")
        let load = "daslang -load_module <c2das-re>/dasCRuntime -load_module <c2das-re>/c_runtime"
        w |> write("{load} readable/lua/lua.das -- -e \"print(1+1)\"\n")
        w |> write("{load} -jit fast/lua/lua.das -- bench/fib.lua\n")
        w |> write("{load} -exe fast/lua/lua.das -output lua && ./lua bench/fib.lua\n")
        w |> write("{load} readable/luac/luac.das -- -o out.luac script.lua\n```\n\n")
        w |> write("Everything after `--` is the program's own command line; daslang writes the `-exe` binary at the `-output` path as given.\n\n")
        w |> write("## Upstream tests\n\n")
        w |> write("The results c2das-re's {port.claims_item} recorded for this program, not results of this publish's run; ")
        w |> write("the perf section's test-suite row runs the release's test suite once the perf tables are on:\n\n")
        for (claim in port.claims) {
            w |> write("- {claim}\n")
        }
        if (empty(harness_log)) {
            w |> write("\nThis publish reused a conversion that left no harness log.\n\n")
        } else {
            w |> write("\nThe harness's report of each variant's conversion (`{port.harness}/run.das --native --run --variant <file> --layout <its layout>`: the native binaries' sizes, the JSON bytes, ")
            w |> write("the das line counts and `[c_function]` counts, and `lua -e \"print(1+1)\"` under the interpreter against the native build; ")
            w |> write("its seconds stay in its log, so an unchanged tree publishes an unchanged README):\n\n```\n{harness_log}```\n\n")
        }
        w |> write("## Performance\n\n{perf_text}")
    }
}

// a harness log line without its seconds: every `, `-separated clause that is `<what> <number> s`
// dropped, "" when nothing else is left
def private clock_free(line : string) : string {
    var head = ""
    var kept : array<string>
    for (clause in split(line, ", ")) {
        if (!is_seconds(clause)) {
            kept |> push(clause)
            continue
        }
        // the line's first clause carries its `<program>: <stem>: ` prefix
        let colon = rfind(clause, ": ")
        if (empty(kept) && colon >= 0) {
            head = slice(clause, 0, colon + 2)
        }
    }
    return empty(kept) ? "" : head + join(kept, ", ")
}

def private is_seconds(clause : string) : bool {
    if (!(clause |> ends_with(" s"))) {
        return false
    }
    let body = slice(clause, 0, length(clause) - 2)
    var digits = 0
    for (ch in slice(body, rfind(body, " ") + 1)) {
        if (is_number(ch)) {
            digits++
        } elif (ch != '.') {
            return false
        }
    }
    return digits > 0
}

// the lines of the harness's log `log` that report the conversion, without their seconds
def private harness_report(port : Port; log : string) : string {
    var lines : array<string>
    for (ln in split(fread(log), "\n")) {
        let line = clock_free(strip(ln))
        if (ln |> contains("{port.name}: ") && !empty(line)) {
            lines |> push(line)
        }
    }
    return empty(lines) ? "" : join(lines, "\n") + "\n"
}

// the report of each variant's conversion, its lines under a `<variant>:` line; "" when no log
// reports one
def private variants_report(port : Port; variants : array<Variant>) : string {
    var parts : array<string>
    for (v in variants) {
        let report = harness_report(port, variant_log_of(port, v.name))
        if (!empty(report)) {
            parts |> push("{v.name}:\n{report}")
        }
    }
    return join(parts, "")
}

//! how the README names each layout a variant converts in
let LAYOUT_WORDS <- {"source" => "a module per C file, every cycle of files one module of `.das.inc` fragments (c2das-re's source layout; its `program.layout.txt` lists the modules)", "source-cut" => "a module per C file, the cycles among files cut by late binding through `<stem>_link.das` (c2das-re's source-cut layout; its `program.layout.txt` lists the cut)", "single" => "the program as one module (c2das-re's single layout)"}

def private write_or_log(path, text : string) : bool {
    if (!fwrite(path, text)) {
        to_log(LOG_ERROR, "ports: cannot write {path}\n")
        return false
    }
    return true
}

// every file of the conversion the publish reads: each variant's entry module of each program, with
// its module list outside the single layout; false with the first missing one logged
def private converted_files_exist(port : Port; variants : array<Variant>) : bool {
    var paths : array<string>
    paths |> reserve(2 * length(variants) * length(port.modules))
    for (v in variants) {
        for (m in port.modules) {
            paths |> push(module_of(port, v, m.stem))
            if (layout_of(v) != "single") {
                paths |> push(path_join(dir_name(module_of(port, v, m.stem)), "program.modules.txt"))
            }
        }
    }
    for (path in paths) {
        if (!fexist(path)) {
            to_log(LOG_ERROR, "{port.name}: no {path}; run without --no-convert\n")
            return false
        }
    }
    return true
}

// the variant files of `program`, `VARIANT_NAMES` in order, into `into`; false with the first that
// does not read logged
def private variants_of(program : string; var into : array<Variant>) : bool {
    into |> reserve(length(VARIANT_NAMES))
    for (name in VARIANT_NAMES) {
        var error : string
        into |> emplace(read_variant(variant_path(program, name), error))
        if (!empty(error)) {
            to_log(LOG_ERROR, "{program}: {error}\n")
            return false
        }
    }
    return true
}

// the lines of every file of `files` under `dir` ("" for paths as they are)
def private lines_of(dir : string; files : array<string>) : int {
    var lines = 0
    for (rel in files) {
        lines += count(fread(empty(dir) ? rel : path_join(dir, rel)), "\n")
    }
    return lines
}

// the lines of the C function `c_name` in the first file of `files` under `dir` that defines it, 0
// when none does
def private function_lines(dir : string; files : array<string>; c_name : string) : int {
    for (rel in files) {
        let text = function_text(fread(path_join(dir, rel)), c_name, "ours")
        if (!empty(text)) {
            return length(split(text, "\n"))
        }
    }
    return 0
}

// the criteria total of the row `row` of `CRITERIA_CAPTURE`, 0 without the capture or the row
def private criteria_total(row : string) : double {
    var error : string
    if (!fexist(CRITERIA_CAPTURE)) {
        return 0.0lf
    }
    let cap <- capture_at(CRITERIA_CAPTURE, error)
    if (!empty(error)) {
        return 0.0lf
    }
    let compliance <- compliance_table(cap)
    var total = 0.0lf
    compliance |> get(row) $(column) {
        total = column_total(column)
    }
    return max(total, 0.0lf)
}

//! the criteria row of a program a variants table falls back to for `readable`: the converter's
//! default conversion of it, which no variant's search measured
def criteria_fallback_label(row : string) : string => "the row `{row}` of c2das-re's `{CRITERIA_CAPTURE}`, the converter's default flags"

// the fallback speed of the variant `name` from the latest capture `c`: per tier the geometric
// mean of the lane's work time over native's, the `-fast` lanes for `fast`
def private capture_speed(c : Capture; name : string; var into : table<string; double>) {
    for (tier in SPEED_TIERS) {
        let lane = name == "fast" ? "{tier}-fast" : tier
        var count = 0
        let mean = has_lane(c, lane) ? geomean_ratio(c, lane, count) : 0.0lf
        if (mean > 0.0lf) {
            into[tier] = mean
        }
    }
}

// the variant `v`'s folder `<v>/` of the program's directory `dir` in the clone: each program's tree
// mirrored from its conversion with the layout report, the variant's sidecar text `sidecar` and its
// file; `column` takes the line counts and, for `readable`, the criteria row it falls back to
def private publish_variant(port : Port; v : Variant; sidecar, dir : string; var column : VariantColumn) : bool {
    var ok = true
    for (m in port.modules) {
        let tree = dir_name(module_of(port, v, m.stem))
        let into = path_join(dir, "{v.name}/{m.stem}")
        var inscope files <- tree_files(tree, layout_of(v) == "single" ? "{m.stem}.das" : "")
        var inscope kept := files
        kept |> push(LAYOUT_REPORT)
        if (!drop_unlisted(into, kept)) {
            to_log(LOG_ERROR, "{port.name}: cannot remove a stale file under {into}\n")
            ok = false
        }
        for (rel in files) {
            let target = path_join(into, rel)
            mkdir_rec(dir_name(target))
            ok = ok && write_or_log(target, fread(path_join(tree, rel)))
        }
        let report = path_join(tree, LAYOUT_REPORT)
        if (fexist(report)) {
            ok = ok && write_or_log(path_join(into, LAYOUT_REPORT), fread(report))
        }
        if (m.stem == port.runs) {
            column.das_lines = lines_of(tree, files)
            column.execute_lines = function_lines(tree, files, "luaV_execute")
        }
    }
    ok = ok && write_or_log(path_join(dir, "{v.name}/{port.name}.c2das"), sidecar)
    ok = ok && write_or_log(path_join(dir, "{v.name}/variant.json"), fread(variant_path(port.name, v.name)))
    if (v.name == "readable") {
        column.criteria_fallback = criteria_total(LUA_PROGRAM_ROW)
        column.criteria_from = criteria_fallback_label(LUA_PROGRAM_ROW)
    }
    return ok
}

// the program's directory in the clone: each variant's tree, sidecar and file, and the files
// beside them replaced whole, every input checked before the first write; `gen` the commit the
// published conversion ran at
def private publish_program(args : Args; port : Port; lanes : array<string>; repo : string; var gen : Generation) : bool {
    var release : Release
    if (!release_of(fread("VERSIONS.md"), port.name, release) || length(release.tarballs) != 2) {
        to_log(LOG_ERROR, "{port.name}: VERSIONS.md names no `{port.name}:` line with the release and the test-suite tarballs\n")
        return false
    }
    var variants : array<Variant>
    if (!variants_of(port.name, variants) || (!args.no_convert && !run_harness(port, variants)) || !generation_for(args, port, gen) || !converted_files_exist(port, variants)) {
        return false
    }
    let license = license_block(fread(path_join(sources_of(port, release), port.license_header)))
    if (empty(license)) {
        to_log(LOG_ERROR, "{port.name}: {sources_of(port, release)}/{port.license_header} holds no license block\n")
        return false
    }
    if (!fexist(sidecar_of(port))) {
        to_log(LOG_ERROR, "{port.name}: no {sidecar_of(port)}\n")
        return false
    }
    var sidecars : array<string>
    sidecars |> reserve(length(variants))
    for (v in variants) {
        var error : string
        sidecars |> push(published_sidecar(v, fread(sidecar_of(port)), error))
        if (!empty(error)) {
            to_log(LOG_ERROR, "{port.name}: {sidecar_of(port)}: {error}\n")
            return false
        }
    }
    let dir = path_join(repo, port.name)
    mkdir_rec(path_join(dir, "bench"))
    var ok = true
    var columns : array<VariantColumn>
    columns |> reserve(length(variants))
    for (v, sidecar in variants, sidecars) {
        var column = VariantColumn(file := v)
        ok = publish_variant(port, v, sidecar, dir, column) && ok
        columns |> emplace(column)
    }
    ok = ok && write_or_log(path_join(dir, "LICENSE"), license)
    ok = ok && write_or_log(path_join(dir, "bench/{base_name(TIMED_LUA)}"), fread(TIMED_LUA))
    for (spec in port.workloads) {
        if (!spec.startup && !spec.in_tests) {
            let script = spec.args[length(spec.args) - 1]
            ok = ok && write_or_log(path_join(dir, "bench/{base_name(script)}"), fread(script))
        }
    }
    if (ok && args.perf) {
        ok = measure_program(args, port, variants, release, lanes, dir, gen)
    }
    // the tables render from the latest capture, this publish's or an earlier one's
    var latest : Capture
    var found = false
    ok = ok && latest_capture(dir, latest, found)
    if (found) {
        let from = "the latest capture of this directory's `perf/`, {latest.timestamp} on {machine_label(latest.machine)}, c2das-re `{slice(latest.commit, 0, 12)}`"
        for (column in columns) {
            capture_speed(latest, column.file.name, column.speed_fallback)
            column.speed_from = column.file.name == "fast" ? "{from}, its `-fast` lanes" : from
        }
    }
    let perf_text = found ? measured_note(latest.commit, "", gen) + render_perf(latest) : "{PERF_NOT_YET}\n"
    let variants_text = render_variants(columns, true)
    return ok && write_or_log(path_join(dir, "README.md"), readme_text(port, variants, release, gen, publish_command(args, port), variants_text, perf_text, variants_report(port, variants), found))
}

// the top-level README: the charter kept above the marker, the projects table of every program's
// latest capture (or the perf method line when no program has one) below it with the raw
// captures it copies beside it, then the criteria and the head-to-head when their captures exist
def private publish_top_readme(repo : string; failures : array<string>) : bool {
    var captures : array<Capture>
    var names : array<string>
    dir(repo) $(name) {
        if (!(name |> starts_with(".")) && stat(path_join(repo, name)).is_dir) {
            names |> push(name)
        }
    }
    names |> sort()
    for (name in names) {
        var latest : Capture
        var found = false
        if (!latest_capture(path_join(repo, name), latest, found)) {
            return false
        }
        if (found) {
            captures |> emplace(latest)
        }
    }
    var head_to_head, criteria : string
    if (!compare_section(head_to_head) || !criteria_section(criteria)) {
        return false
    }
    let raw <- [for (rel in RAW_CAPTURES); rel; where fexist(rel)]
    for (rel in raw) {
        let target = path_join(repo, rel)
        mkdir_rec(dir_name(target))
        if (!write_or_log(target, fread(rel))) {
            return false
        }
    }
    // every raw capture the clone holds, a copy the tree no longer has included
    let held <- [for (rel in RAW_CAPTURES); rel; where fexist(path_join(repo, rel))]
    let path = path_join(repo, "README.md")
    let programs <- [for (name in names); name; where !has_value(RAW_DIRS, name)]
    return write_or_log(path, render_top_readme(fread(path), captures, held) + render_programs(programs, failures) + criteria + head_to_head)
}

//! the folders of the clone that hold c2das-re's raw captures, not a program
let RAW_DIRS <- ["compare", "metrics", "perf"]

//! the head-to-head's capture in the c2das-re tree
let COMPARE_CAPTURE = "compare/results_linux.json"

// the top-level README's head-to-head section rendered from `COMPARE_CAPTURE` into `section`, ""
// without the capture; false when it does not read
def private compare_section(var section : string&) : bool {
    if (!fexist(COMPARE_CAPTURE)) {
        return true
    }
    var error : string
    let results = read_json_file(COMPARE_CAPTURE, error)
    if (results == null) {
        to_log(LOG_ERROR, "ports: {error}\n")
        return false
    }
    section = "\n## Head-to-head with the Rust translator\n\n{compare_report(results)}"
    return true
}

//! the readability criteria's capture in the c2das-re tree
let CRITERIA_CAPTURE = "metrics/criteria_linux.json"

//! The files beside the converter whose change can move a project's criteria row: the project
//! conversion and the criteria's own computation (`metrics/ARCHITECTURE_CRITERIA.md`); a commit to
//! another `metrics/` file (a capture, a test, a document) leaves the row as recorded.
let CRITERIA_SOURCES <- ["compare/projects.das", "metrics/criteria.das", "metrics/criteria_count.das", "metrics/criteria_defines.das", "metrics/criteria_file.das", "metrics/criteria_scan.das", "metrics/readability_inputs.das"]

// the top-level README's readability criteria section rendered from `CRITERIA_CAPTURE` into
// `section`, "" without the capture; false when it does not read
def private criteria_section(var section : string&) : bool {
    if (!fexist(CRITERIA_CAPTURE)) {
        return true
    }
    var error : string
    let cap <- capture_at(CRITERIA_CAPTURE, error)
    if (!empty(error)) {
        to_log(LOG_ERROR, "ports: {error}\n")
        return false
    }
    section = "\n## Readability criteria\n\nThe compliance, in percent, per criterion and per input group, from c2das-re's `{CRITERIA_CAPTURE}`: it counts lines and reads no clock, so it holds on any machine.\n\n{render_criteria(cap)}\n"
    return true
}

//! c2das-re's raw captures, each copied into the clone under its own path when present
let RAW_CAPTURES <- [COMPARE_CAPTURE, CRITERIA_CAPTURE, "perf/results_linux.json", "perf/results_method_linux.json", "perf/dasprofile_linux.json"]

def private commit_program(name : string; repo : string; gen : Generation) : bool {
    var out : string
    var paths <- ["add", "-A", "{name}/", "README.md"]
    paths |> push_from([for (rel in RAW_CAPTURES); rel; where fexist(path_join(repo, rel))])
    if (git_in(repo, paths, out) != 0) {
        to_log(LOG_ERROR, "{name}: git add failed: {out}\n")
        return false
    }
    if (git_in(repo, ["diff", "--cached", "--quiet"], out) == 0) {
        to_log(LOG_INFO, "{name}: nothing to commit\n")
        return true
    }
    let message = gen.recorded ? "{name}: regenerated from c2das-re {gen.describe} ({gen.sha})" : "{name}: republished from c2das-re {gen.describe} ({gen.sha}), the conversion's commit unrecorded"
    var argv <- clone_to_move(IDENTITY)
    argv |> push_from(["commit", "-q", "-m", message])
    if (git_in(repo, argv, out) != 0) {
        to_log(LOG_ERROR, "{name}: git commit failed: {out}\n")
        return false
    }
    let head = git_line(repo, ["rev-parse", "--short", "HEAD"])
    to_log(LOG_INFO, "{name}: committed {head}\n")
    return true
}

// whether the conversion can differ between the c2das-re commits `from` and `to`: the converter,
// `c_runtime` or `dasCRuntime` changed between them, or `from` is no commit of this tree
def private converter_changed(from, to : string) : bool => output_changed(from, to, array<string>())

// whether the converter, `c_runtime`, `dasCRuntime` or any of `more` (paths from the tree's root)
// differ between the commits `from` and `to`
def private output_changed(from, to : string; more : array<string>) : bool {
    var out : string
    var argv <- ["diff", "--quiet", from, to, "--", "converter", "c_runtime", "dasCRuntime"]
    argv |> push_from(more)
    return git_in(".", argv, out) != 0
}

// whether a commit of this tree after `date` (its committer date) changed the converter,
// `c_runtime` or `dasCRuntime`; true when `date` does not read as one
def private converter_changed_since(date : string) : bool {
    var out : string
    if (empty(date) || git_in(".", ["log", "--since={date}", "--format=%H", "HEAD", "--", "converter", "c_runtime", "dasCRuntime"], out) != 0) {
        return true
    }
    return !empty(strip(out))
}

// the line a table measured at `sha` on `date` carries in a publish of the conversion `gen`: none
// when it was measured at the published commit
def private measured_note(sha, date : string; gen : Generation) : string => sha == gen.sha ? "" : measured_at_line(sha, date, converter_changed(sha, gen.sha))

// the folder a project's publish converts in: the whole program in `whole/`, each C file alone in
// `files/`
def private project_work(name : string) : string => path_join("compare/work/ports", name)

// every file of `files` (paths under `from`) written into `into` at its path under `from`, every
// other file under `into` removed, the layout report kept when `from` holds one
def private mirror_tree(from, into : string; files : array<string>) : bool {
    var kept <- [for (f in files); relative_to(f, from)]
    let report = path_join(from, LAYOUT_REPORT)
    if (fexist(report)) {
        kept |> push(LAYOUT_REPORT)
    }
    var ok = drop_unlisted(into, kept)
    if (!ok) {
        to_log(LOG_ERROR, "ports: cannot remove a stale file under {into}\n")
    }
    for (rel in kept) {
        let target = path_join(into, rel)
        mkdir_rec(dir_name(target))
        ok = ok && write_or_log(target, fread(path_join(from, rel)))
    }
    return ok
}

// the license of a project's upstream code: every `LICENSE*` or `COPYING*` file under its
// `upstream/` folder, each under its path, else the notice of each file there that names its
// license by an SPDX line; "" when there is neither
def private project_license(p : Project) : string {
    let upstream = project_path(p, "upstream")
    var files, notices : array<string>
    if (stat(upstream).is_dir) {
        dir_rec(upstream) $(name, is_dir) {
            let base = to_upper(base_name(name))
            if (!is_dir && (base |> starts_with("LICENSE") || base |> starts_with("COPYING"))) {
                files |> push(name)
            } elif (!is_dir && (name |> ends_with(".h") || name |> ends_with(".c"))) {
                notices |> push(name)
            }
        }
    }
    sort(files)
    sort(notices)
    var parts <- [for (f in files); "upstream/{f}:\n\n{fread(path_join(upstream, f))}"]
    if (empty(parts)) {
        for (f in notices) {
            let notice = spdx_notice(fread(path_join(upstream, f)))
            if (!empty(notice)) {
                parts |> push("upstream/{f}:\n\n{spdx_license(notice)}")
            }
        }
    }
    // the Rust repository's own glue (`src/`, `include/`), converted with the upstream code
    let own = path_join(rust_checkout(), "LICENSE")
    if (!empty(parts) && fexist(own)) {
        parts |> push("src/ and include/ of {MANUAL_DIR}/{p.name} (the files of lookibed/c2das itself, its LICENSE):\n\n{fread(own)}")
    }
    return join(parts, "\n")
}

// the commit that recorded the head-to-head's capture, "" outside a git tree
def private compare_recorded_at : string => git_line(".", ["log", "-1", "--format=%H", "--", COMPARE_CAPTURE])

// the perf section of a project's README: its entry of the head-to-head's capture, rendered as the
// compare report renders the projects, under the commit that recorded it; a not-yet line without
// an entry
def private project_perf_text(p : Project) : string {
    if (!fexist(COMPARE_CAPTURE)) {
        return "not yet: c2das-re holds no `{COMPARE_CAPTURE}`, the capture of the head-to-head that times the projects.\n"
    }
    var error : string
    var results = read_json_file(COMPARE_CAPTURE, error)
    var entry = results?["projects"]?[p.name]
    // a project the capture lacks reads as a null value, not as no value
    if (entry == null || !(entry.value is _object)) {
        return "not yet: c2das-re's `{COMPARE_CAPTURE}` holds no entry for {p.name}.\n"
    }
    let one = JV({"projects" => JV({p.name => entry})})
    let date = entry?["date"] ?? ""
    let note = measured_on_line(date, compare_recorded_at(), converter_changed_since(date))
    return "{note}From c2das-re's `{COMPARE_CAPTURE}` (`compare/run.das --project {p.name}`), our side against the Rust translator's:\n\n{projects_text(one)}"
}

// the criteria section of a project's README: its row of `CRITERIA_CAPTURE` under the commit that
// recorded the capture (none for a capture with uncommitted changes), the output changed since when
// the converter or one of `CRITERIA_SOURCES` differs between that commit and the published
// conversion's
def private project_criteria(p : Project; gen : Generation) : string {
    var error : string
    let present = fexist(CRITERIA_CAPTURE)
    let cap <- present ? capture_at(CRITERIA_CAPTURE, error) : CriteriaCapture()
    // a capture with uncommitted changes (a publish under --allow-dirty) was recorded at no commit
    let dirty = !empty(git_line(".", ["status", "--porcelain", "--", CRITERIA_CAPTURE]))
    let recorded = dirty ? "" : git_line(".", ["log", "-1", "--format=%H", "--", CRITERIA_CAPTURE])
    let changed = !empty(recorded) && present && empty(error) && output_changed(recorded, gen.sha, CRITERIA_SOURCES)
    return project_criteria_text(p.name, cap, present, error, recorded, changed)
}

//! one variant's conversion of a compare project, as its README states it: the variant, the whole
//! program's refusal ("" when it converts whole) and each file converted alone
struct ProjectVariant {
    name : string
    refusal : string
    files : array<FileConversion>
}

// the conversion section of a project's README for one variant: whole, or the refusal and the
// per-file results
def private conversion_text(p : Project; stem : string; c : ProjectVariant) : string {
    return build_string() $(var w) {
        w |> write("### `{c.name}/`\n\n")
        if (empty(c.refusal)) {
            w |> write("The program converts whole: `{c.name}/{stem}/` holds it (`{c.name}/{stem}/{stem}.das` holds `main`).\n\n")
            return
        }
        let converted = length([for (f in c.files); f; where empty(f.refusal)])
        w |> write("The program does not convert whole yet: {path_free(c.refusal, p.dir)}\n\n")
        w |> write("What does convert: each C file of the program converted alone, {converted} of {length(c.files)} (`{c.name}/files/`, a module per file at its path under the project folder; ")
        w |> write("a file alone is no program, so these modules show the conversion and do not run):\n\n")
        var rows : array<array<string>>
        rows |> reserve(length(c.files))
        for (f in c.files) {
            rows |> emplace([f.c_path, empty(f.refusal) ? "converted" : "refused: {path_free(f.refusal, p.dir)}"])
        }
        w |> write(table_of(["C file", "Result"], rows, 2))
        w |> write("\n")
    }
}

// a project's README: the variants, what each converted (or what refused and the per-file results),
// the sources, how to run it, the speed from the head-to-head's capture and the criteria line
def private project_readme_text(p : Project; gen : Generation; rust_sha : string; conversions : array<ProjectVariant>; command, variants_text, perf_text, criteria_text : string) : string {
    let stem = trim_suffix(base_name(p.tu), ".c")
    let fixture = "<c2das>/{MANUAL_DIR}/{p.name}/{p.fixture}"
    return build_string() $(var w) {
        w |> write("# {p.name}\n\n")
        w |> write("The real project {p.name} of the Rust translator's `{MANUAL_DIR}` ([lookibed/c2das](https://github.com/lookibed/c2das)) converted to daslang by [c2das-re](https://github.com/lookibed/c2das-re), as its head-to-head converts our side. ")
        w |> write("Everything in this directory is generated by `{command}` in c2das-re; never edit it, a fix belongs in c2das-re.\n\n")
        w |> write("## Variants\n\n{variants_text}\n")
        w |> write("## Conversion\n\n")
        for (c in conversions) {
            w |> write(conversion_text(p, stem, c))
        }
        w |> write("## Files\n\n")
        for (c in conversions) {
            if (empty(c.refusal)) {
                w |> write("- `{c.name}/{stem}/` - the program converted from `{p.tu}`" + (empty(p.units) ? "" : " and the other units of its canonical case, a module per C file (c2das-re's source layout; `{c.name}/{stem}/{LAYOUT_REPORT}` lists the modules)") + ".\n")
            } else {
                w |> write("- `{c.name}/files/` - each C file that converts alone, as its module.\n")
            }
            w |> write("- `{c.name}/{p.name}.c2das` - the sidecar the {c.name} variant's conversion ran under, its paths in the Rust checkout written under `<c2das>`, that checkout; `{c.name}/variant.json` - its knobs with the reason and the numbers behind each.\n")
        }
        w |> write("- `LICENSE` - the license of the upstream code under `{MANUAL_DIR}/{p.name}/upstream/`; the conversion is a derived work.\n\n")
        w |> write("## Source\n\n")
        w |> write("- The C sources: `{MANUAL_DIR}/{p.name}/` of lookibed/c2das at `{rust_sha}`; its `UPSTREAM.md` names each upstream and its revision.\n")
        w |> write("- {generation_line(gen)}\n\n")
        w |> write("## Running\n\n")
        w |> write("The modules require c2das-re's `crt` and `c_runtime` modules: a c2das-re checkout at the commit above, with the daScript its `VERSIONS.md` pins built and `scripts/build_crt.sh` run. ")
        w |> write("The program reads its fixture `{p.fixture}` from the Rust repository's project folder; no fixture is copied here (game data and fixtures stay with their own licenses there). ")
        w |> write("With `<c2das-re>` and `<c2das>` the two checkouts:\n\n```\n")
        let load = "daslang -load_module <c2das-re>/dasCRuntime -load_module <c2das-re>/c_runtime"
        for (c in conversions) {
            if (empty(c.refusal)) {
                w |> write("{load} {c.name == "fast" ? "-jit " : ""}{c.name}/{stem}/{stem}.das -- {fixture}\n")
            } else {
                w |> write("# {c.name}/: not runnable yet: the program does not convert whole\n")
            }
        }
        var native <- ["clang"]
        native |> push_from(clang_args(p), p.native_flags, p.native_sources, p.link_flags)
        w |> write("# the native build the tables compare with, in <c2das>/{MANUAL_DIR}/{p.name}:\n" + replace(join(native, " "), "{p.dir}/", "") + " -o {p.name}\n```\n\n")
        w |> write("Its output must equal `expected.stdout` of the canonical case `{p.case_id}` in the Rust repository's `{CASES_FILE}`.\n\n")
        w |> write("## Performance\n\n{perf_text}\n")
        w |> write("## Readability criteria\n\n{criteria_text}")
    }
}

// the head-to-head's x native of our side of project `name` per tier: the geometric mean over the
// project's benches of the tier's time over native's (`cell_ratio`), into `into`; the entry's date
def private project_speed(name : string; var into : table<string; double>) : string {
    var error : string
    if (!fexist(COMPARE_CAPTURE)) {
        return ""
    }
    var results = read_json_file(COMPARE_CAPTURE, error)
    let speed = results?["projects"]?[name]?["speed"]
    let native = speed?["native"]
    for (tier in SPEED_TIERS) {
        var log_sum = 0.0lf
        var count = 0
        if (native != null && native.value is _object) {
            for (bench in keys(native.value as _object)) {
                let r = cell_ratio(speed?["ours"]?[tier]?[bench], native?[bench])
                if (r > 0.0lf) {
                    log_sum += log(r)
                    count++
                }
            }
        }
        if (count > 0) {
            into[tier] = exp(log_sum / double(count))
        }
    }
    let date = results?["projects"]?[name]?["date"] ?? ""
    delete_json(results)
    return date
}

// a compare project's directory in the clone: per variant converted whole, else file by file, into
// `<variant>/`, every input read and each conversion done before its first write into the clone
def private publish_project(p_row : Project; repo : string; var gen : Generation; var why : string&) : bool {
    var p := p_row
    why = load_expected(p)
    if (!empty(why)) {
        return false
    }
    let license = project_license(p)
    if (empty(license)) {
        why = "no license file or SPDX notice under {project_path(p, "upstream")}"
        return false
    }
    var variants : array<Variant>
    if (!variants_of(p.name, variants)) {
        why = "a variant file does not read (the log names it)"
        return false
    }
    let dir = path_join(repo, p.name)
    let stem = trim_suffix(base_name(p.tu), ".c")
    var ok = true
    var columns : array<VariantColumn>
    columns |> reserve(length(variants))
    var conversions : array<ProjectVariant>
    conversions |> reserve(length(variants))
    for (v in variants) {
        p.ours_variant := v
        let work = path_join(project_work(p.name), v.name)
        let whole = path_join(work, "whole")
        var inscope conv : ProjectConversion
        if (!convert_apart(p.name, v.name, conv, why)) {
            return false
        }
        let into = path_join(dir, v.name)
        mkdir_rec(into)
        ok = mirror_tree(whole, path_join(into, stem), empty(conv.refusal) ? conv.files : array<string>()) && ok
        var inscope converted : array<string>
        for (f in conv.per_file) {
            if (!empty(f.das_path)) {
                converted |> push(f.das_path)
            }
        }
        ok = mirror_tree(path_join(work, "files"), path_join(into, "files"), converted) && ok
        ok = ok && write_or_log(path_join(into, "{p.name}.c2das"), replace(fread(path_join(whole, "{p.name}.c2das")), p.dir, "<c2das>/{MANUAL_DIR}/{p.name}"))
        ok = ok && write_or_log(path_join(into, "variant.json"), fread(variant_path(p.name, v.name)))
        var column = VariantColumn(file := v)
        column.das_lines = empty(conv.refusal) ? lines_of("", conv.files) : lines_of("", converted)
        if (v.name == "readable") {
            column.criteria_fallback = criteria_total("{PROJECT_PREFIX}{p.name}")
            column.criteria_from = criteria_fallback_label("{PROJECT_PREFIX}{p.name}")
            let date = project_speed(p.name, column.speed_fallback)
            column.speed_from = "c2das-re's `{COMPARE_CAPTURE}`, the project's entry measured {date}, the converter's default flags, the geometric mean over its benches"
        }
        columns |> emplace(column)
        conversions |> emplace(ProjectVariant(name = v.name, refusal = conv.refusal, files := conv.per_file))
    }
    gen = tree_generation()
    ok = ok && write_or_log(path_join(dir, "LICENSE"), license)
    let command = "scripts/publish_ports.sh --program {p.name}"
    let rust_sha = git_line(rust_checkout(), ["rev-parse", "HEAD"])
    why = ok ? "" : "a file of its directory was not written"
    return ok && write_or_log(path_join(dir, "README.md"), project_readme_text(p, gen, rust_sha, conversions, command, render_variants(columns, false), project_perf_text(p), project_criteria(p, gen)))
}

def private repo_of(args : Args) : string {
    if (!empty(args.repo)) {
        return args.repo
    }
    return has_env_variable("C2DAS_PORTS") ? get_env_variable("C2DAS_PORTS") : "../c2das-ports"
}

// every compare project of `projects` that `--program` names (all without it) published, the
// top-level README after each, and committed with `--commit`; false at the first that fails
// why the program `name` is not published, "" when it is: a compare project under `--no-convert`
// or missing from the Rust checkout, PureDOOM in a tree without the `doom/` harness
def private skip_reason(args : Args; name : string; projects : array<Project>) : string {
    if (name == PUREDOOM) {
        return fexist(DOOM_HARNESS) ? "" : "this tree has no {DOOM_HARNESS}"
    }
    for (p in projects) {
        if (p.name == name) {
            return args.no_convert ? "a compare project converts on every publish, and --no-convert converts nothing" : stat(p.dir).is_dir ? "" : "the Rust checkout has no {p.dir}"
        }
    }
    return ""
}

// the variant `variant_name` of the compare project `name` converted by this script run again in a
// process of its own with `--program <name> --convert-variant <variant_name> --results <file>` last, so
// the heaps of its conversion go with it, as a program's do (`publish_apart`); the conversion read
// back from the file into `into`; false with `why` set when the process wrote none
[arch(at="ARCHITECTURE_RUN.md#variant-apart")]
def private convert_apart(name, variant_name : string; var into : ProjectConversion; var why : string&) : bool {
    var dir_error : string
    let dir = create_temp_directory("c2das_convert", dir_error)
    if (!empty(dir_error)) {
        why = "no folder for the {variant_name} variant's conversion: {dir_error}"
        return false
    }
    let results = path_join(dir, "conversion.json")
    let command = rerun_command(get_command_line_arguments(), ["--program", name, "--convert-variant", variant_name, "--results", results])
    to_log(LOG_INFO, "{name}: the {variant_name} variant converts in a process of its own: {command}\n")
    let how = process_ended(unsafe(system(command)))
    var error : string
    var js = fexist(results) ? read_json_file(results, error) : null
    if (js == null) {
        why = "the {variant_name} variant's conversion process " + (empty(how) ? "wrote no conversion" : how)
    } else {
        delete into
        into <- from_JV(js, type<ProjectConversion>)
    }
    delete_json(js)
    rmdir_rec(dir)
    return empty(why)
}

// the child of `convert_apart`: the variant `args.convert_variant` of the project `args.program`
// converted into its work folder and written to `args.results`; 1 when the project or the variant
// file is not found or the file is not written
def private convert_variant_child(args : Args; projects : array<Project>) : int {
    for (row in projects) {
        if (row.name == args.program) {
            var p := row
            var error = load_expected(p)
            if (empty(error)) {
                p.ours_variant <- read_variant(variant_path(p.name, args.convert_variant), error)
            }
            if (!empty(error)) {
                to_log(LOG_ERROR, "{p.name}: {error}\n")
                return 1
            }
            var inscope conv <- convert_project(p, path_join(project_work(p.name), args.convert_variant))
            return fwrite(args.results, write_json(JV(conv))) ? 0 : 1
        }
    }
    to_log(LOG_ERROR, "ports: --convert-variant takes a compare project, not `{args.program}`\n")
    return 1
}

def private publish_projects(args : Args; projects : array<Project>; repo : string; var failures : array<string>; var published : int&) {
    for (p in projects) {
        if (!empty(args.program) && args.program != p.name) {
            continue
        }
        let skip = skip_reason(args, p.name, projects)
        if (!empty(skip)) {
            to_log(LOG_WARNING, "{p.name}: not published: {skip}\n")
            continue
        }
        var gen : Generation
        var why : string
        if (!publish_project(p, repo, gen, why)) {
            failures |> push("{p.name}: {why}")
            to_log(LOG_ERROR, "{p.name}: not published: {why}\n")
            continue
        }
        if (!publish_top_readme(repo, failures)) {
            failures |> push("{p.name}: the top-level README was not written")
            continue
        }
        to_log(LOG_INFO, "{p.name}: published into {path_join(repo, p.name)}\n")
        published++
        if (args.commit && !commit_program(p.name, repo, gen)) {
            failures |> push("{p.name}: the commit failed")
        }
    }
}

// every flag and the trees checked before a publish, `lanes` the lanes `--lanes` names after
// `native`; false with the refusal logged
def private flags_hold(args : Args; var lanes : array<string>) : bool {
    let das_lanes <- split(args.lanes, ",")
    lanes |> push("native")
    lanes |> reserve(1 + length(das_lanes))
    for (lane in das_lanes) {
        if (lane == "native" || !has_value(ALL_LANES, lane)) {
            to_log(LOG_ERROR, "ports: no das lane `{lane}`; --lanes takes interp, jit, exe, aot, interp-fast, jit-fast, exe-fast and aot-fast\n")
            return false
        }
        lanes |> push(lane)
    }
    if (args.push && !args.commit) {
        to_log(LOG_ERROR, "ports: --push needs --commit\n")
        return false
    }
    if (args.samples < 1) {
        to_log(LOG_ERROR, "ports: --samples takes a count of 1 or more, not {args.samples}\n")
        return false
    }
    if (args.timeout <= 0) {
        to_log(LOG_ERROR, "ports: --timeout takes seconds above 0, not {args.timeout}\n")
        return false
    }
    let refusal = box_refusal(args.box, cpu_name())
    if (!empty(refusal)) {
        to_log(LOG_ERROR, "ports: {refusal}\n")
        return false
    }
    let repo = repo_of(args)
    if (!is_clone(repo)) {
        to_log(LOG_ERROR, "ports: {repo} is no clone of the ports repository (not the top of a git work tree)\n")
        return false
    }
    var status : string
    if (git_in(".", ["status", "--porcelain"], status) != 0) {
        to_log(LOG_ERROR, "ports: run from the c2das-re checkout: {strip(status)}\n")
        return false
    }
    if (!empty(strip(status)) && !args.allow_dirty) {
        to_log(LOG_ERROR, "ports: the c2das-re tree has uncommitted changes; commit them or pass --allow-dirty\n")
        return false
    }
    return true
}

// the Lua port published, the top-level README after it, and committed with `--commit`
def private publish_and_commit_port(args : Args; port : Port; lanes : array<string>; repo : string; var failures : array<string>; var published : int&) {
    var gen : Generation
    if (!publish_program(args, port, lanes, repo, gen) || !publish_top_readme(repo, failures)) {
        failures |> push("{port.name}: the publish failed (its log names why)")
        return
    }
    to_log(LOG_INFO, "{port.name}: published into {path_join(repo, port.name)}\n")
    published++
    if (args.commit && !commit_program(port.name, repo, gen)) {
        failures |> push("{port.name}: the commit failed")
    }
}

[export]
def main : int {
    var args = Args()
    let early = cli_prologue(args, "scripts/publish_ports.sh")
    if (early >= 0) {
        return early
    }
    var ports : array<Port>
    ports |> emplace(lua_port())
    var projects <- project_table(rust_checkout())
    var known <- [for (p in ports); p.name]
    known |> push_from([for (p in projects); p.name])
    known |> push(PUREDOOM)
    if (!empty(args.program) && !has_value(known, args.program)) {
        to_log(LOG_ERROR, "ports: no program `{args.program}`; the publisher knows " + join(known, ", ") + "\n")
        return 1
    }
    if (!empty(args.convert_variant)) {
        return convert_variant_child(args, projects)
    }
    var lanes : array<string>
    if (!flags_hold(args, lanes)) {
        return 1
    }
    let repo = repo_of(args)
    var failures : array<string>
    var published = 0
    if (empty(args.program)) {
        for (name in known) {
            let skip = skip_reason(args, name, projects)
            if (empty(skip)) {
                publish_apart(name, failures, published)
            } else {
                to_log(LOG_WARNING, "{name}: not published: {skip}\n")
            }
        }
        return finish(args, repo, failures, published)
    }
    for (port in ports) {
        if (args.program == port.name) {
            publish_and_commit_port(args, port, lanes, repo, failures, published)
        }
    }
    publish_projects(args, projects, repo, failures, published)
    if (args.program == PUREDOOM) {
        publish_and_commit_puredoom(args, repo, failures, published)
    }
    if (!empty(args.results)) {
        var lines <- [for (_i in range(published)); "published"]
        lines |> push_from([for (f in failures); "failed {f}"])
        return fwrite(args.results, join(lines, "\n") + "\n") ? 0 : 1
    }
    return finish(args, repo, failures, published)
}

// the program `name` published by this script run again in a process of its own with `--program
// <name> --results <file>` last (`rerun_command`), so the process's heaps, which hold every string
// a conversion made until it exits, go with it; its outcome read back from the file into `failures`
// and `published`, a process that ended without one a failure naming how it ended
[arch(at="ARCHITECTURE_RUN.md#apart")]
def private publish_apart(name : string; var failures : array<string>; var published : int&) {
    var dir_error : string
    let dir = create_temp_directory("c2das_publish", dir_error)
    if (!empty(dir_error)) {
        failures |> push("{name}: no folder for the outcome of its process: {dir_error}")
        return
    }
    let results = path_join(dir, "results.txt")
    let command = rerun_command(get_command_line_arguments(), ["--program", name, "--results", results])
    to_log(LOG_INFO, "{name}: in a process of its own: {command}\n")
    let how = process_ended(unsafe(system(command)))
    var outcome = false
    for (ln in split(fread(results), "\n")) {
        if (ln == "published") {
            published++
            outcome = true
        } elif (ln |> starts_with("failed ")) {
            failures |> push(slice(ln, length("failed ")))
            outcome = true
        }
    }
    if (!outcome && !empty(how)) {
        failures |> push("{name}: the publish process {how} without an outcome")
    }
    rmdir_rec(dir)
}

// the end of a publish: when some program published, the failures named in the top-level README
// and committed with `--commit` (a run that published nothing leaves the clone as it was), whatever
// was committed pushed with `--push`, the failures logged; 1 when any program failed or the push did
def private finish(args : Args; repo : string; failures : array<string>; published : int) : int {
    if (!empty(failures) && published > 0 && publish_top_readme(repo, failures) && args.commit) {
        var out : string
        if (git_in(repo, ["add", "README.md"], out) == 0 && git_in(repo, ["diff", "--cached", "--quiet"], out) != 0) {
            var argv <- clone_to_move(IDENTITY)
            argv |> push_from(["commit", "-q", "-m", "README: the programs this publish failed: " + join(failures, "; ")])
            git_in(repo, argv, out)
        }
    }
    var rc = empty(failures) ? 0 : 1
    var out : string
    if (args.push && git_in(repo, ["push", "-q", "origin", "HEAD"], out) != 0) {
        to_log(LOG_ERROR, "ports: git push failed: {out}\n")
        rc = 1
    }
    for (f in failures) {
        to_log(LOG_ERROR, "ports: failed: {f}\n")
    }
    return rc
}

//! PureDOOM's directory in the clone and the `doom/` harness's paths the publish reads
let PUREDOOM = "puredoom"
let DOOM_HARNESS = "doom/run.das"
let DOOM_FPS = "doom/results_linux.json"
let DOOM_LICENSE = "doom/fetch/PureDOOM/LICENSE"
let DOOM_PATCHES = "doom/patches"

// the `doom/` harness as a port: its stamp and its log under `doom/work/`
def private doom_port : Port => <- Port(name = PUREDOOM, title = "PureDOOM", harness = "doom")

// the folder the `doom/` harness converts the variant `name` in, its tree in `layout`, and the
// verdicts of its demos
def private doom_root(name : string) : string => path_join("doom/work/variants", name)
def private doom_tree(v : Variant) : string => path_join(doom_root(v.name), layout_of(v))
def private doom_sync(name : string) : string => path_join(doom_root(name), "publish_sync.txt")

// the fetch, then per variant the conversion in its layout and each demo of `SYNC_DEMOS` under each
// tier of `SYNC_TIERS` held to its reference log, the verdicts kept in the variant's `publish_sync.txt`;
// a demo out of sync is a verdict of the README, not a failed publish
def private run_doom_harness(port : Port; variants : array<Variant>) : bool {
    remove(stamp_of(port))
    var out : string
    if (run_and_capture(["bash", "doom/fetch.sh"], out, 3600.0) != 0) {
        to_log(LOG_ERROR, "{PUREDOOM}: doom/fetch.sh failed: {last_line(out)}\n")
        return false
    }
    for (v in variants) {
        var inscope variant_args <- ["--variant", variant_path(PUREDOOM, v.name), "--layout", layout_of(v)]
        var inscope argv <- daslang_cmd(CONVERTED_MODULES)
        argv |> push_from(["doom/run.das", "--", "--convert"], variant_args)
        to_log(LOG_INFO, "{PUREDOOM}: " + join(argv, " ") + "\n")
        let rc = run_and_capture(argv, out, 7200.0)
        mkdir_rec(doom_root(v.name))
        fwrite(path_join(doom_root(v.name), "publish_run.log"), out)
        if (!program_converted(out)) {
            to_log(LOG_ERROR, "{PUREDOOM}: the {v.name} variant did not convert (exit {rc}); {doom_root(v.name)}/publish_run.log holds its log\n")
            return false
        }
        var inscope cells : array<SyncCell>
        cells |> reserve(length(SYNC_TIERS) * length(SYNC_DEMOS))
        for (tier in SYNC_TIERS) {
            for (demo in SYNC_DEMOS) {
                var inscope run <- daslang_cmd(CONVERTED_MODULES)
                run |> push_from(["doom/run.das", "--", "--run", "--tier", tier, "--demo", "{demo}"], variant_args)
                let run_rc = run_and_capture(run, out, 7200.0)
                cells |> push(SyncCell(tier = tier, demo = demo, verdict = sync_verdict(tier, demo, run_rc, out)))
                to_log(LOG_INFO, "{PUREDOOM}: {v.name} {tier} demo{demo}: {cells[length(cells) - 1].verdict}\n")
            }
        }
        if (!write_or_log(doom_sync(v.name), sync_record(cells))) {
            return false
        }
    }
    let gen = tree_generation()
    return write_or_log(stamp_of(port), "{gen.sha}\n{gen.describe}\n{gen.date}\n")
}

// the frame-rate capture at `path` read into `into`; false when it does not read
def private read_fps(path : string; var into : FpsCapture) : bool {
    var error : string
    let js = fexist(path) ? read_json_file(path, error) : null
    if (js == null) {
        return false
    }
    delete into
    into <- from_JV(js, type<FpsCapture>)
    return true
}

// the x native per tier of the frame-rate capture `c`: the geometric mean over its demos of the
// native frame rate over the tier's (`slowdown`)
def private fps_speed(c : FpsCapture; var into : table<string; double>) {
    for (tier in SPEED_TIERS) {
        var log_sum = 0.0lf
        var count = 0
        for (demo in c.workloads) {
            let r = slowdown(c, demo, tier)
            if (r > 0.0lf) {
                log_sum += log(r)
                count++
            }
        }
        if (count > 0) {
            into[tier] = exp(log_sum / double(count))
        }
    }
}

// the frame-rate section: the table of `DOOM_FPS` under the commit it was measured at, the output
// changed since when the converter changed after it
def private doom_fps_text(gen : Generation) : string {
    var error : string
    let js = read_json_file(DOOM_FPS, error)
    if (js == null) {
        return "not yet: {error}\n"
    }
    let c <- from_JV(js, type<FpsCapture>)
    let full = git_line(".", ["rev-parse", "--verify", "-q", trim_suffix(c.commit, "-dirty") + "^\{commit\}"])
    let date = empty(full) ? "" : git_line(".", ["log", "-1", "--format=%cs", full])
    let note = full == gen.sha ? "" : measured_at_line(empty(full) ? c.commit : full, date, empty(full) || converter_changed(full, gen.sha))
    return "{note}From c2das-re's `{DOOM_FPS}` (`{c.command}`), the frames per second of each demo's `-timedemo` against the native build:\n\n{render_fps(c)}"
}

// PureDOOM published, the top-level README after it, and committed with `--commit`; skipped with a
// warning in a tree without the `doom/` harness
def private publish_and_commit_puredoom(args : Args; repo : string; var failures : array<string>; var published : int&) {
    let skip = skip_reason(args, PUREDOOM, array<Project>())
    if (!empty(skip)) {
        to_log(LOG_WARNING, "{PUREDOOM}: not published: {skip}\n")
        return
    }
    var gen : Generation
    if (!publish_puredoom(args, repo, gen) || !publish_top_readme(repo, failures)) {
        failures |> push("{PUREDOOM}: the publish failed (its log names why)")
        return
    }
    to_log(LOG_INFO, "{PUREDOOM}: published into {path_join(repo, PUREDOOM)}\n")
    published++
    if (args.commit && !commit_program(PUREDOOM, repo, gen)) {
        failures |> push("{PUREDOOM}: the commit failed")
    }
}

// PureDOOM's directory in the clone: per variant its tree, sidecar and file, then the patches, the
// license and the README, every input checked before the first write
def private publish_puredoom(args : Args; repo : string; var gen : Generation) : bool {
    let port <- doom_port()
    var variants : array<Variant>
    if (!variants_of(PUREDOOM, variants) || (!args.no_convert && !run_doom_harness(port, variants)) || !generation_for(args, port, gen)) {
        return false
    }
    let versions = fread("VERSIONS.md")
    let pin = puredoom_pin(versions)
    let license = fexist(DOOM_LICENSE) ? fread(DOOM_LICENSE) : ""
    var missing = ""
    if (empty(pin)) {
        missing = "VERSIONS.md names no `puredoom:` pin"
    } elif (empty(license)) {
        missing = "no {DOOM_LICENSE}; doom/fetch.sh fetches it"
    }
    var sidecars : array<string>
    sidecars |> reserve(length(variants))
    for (v in variants) {
        var error : string
        sidecars |> push(published_sidecar(v, fread("doom/doom.c2das"), error))
        if (!empty(missing)) {
            break
        } elif (!fexist(path_join(doom_tree(v), "program.modules.txt"))) {
            missing = "no {doom_tree(v)}/program.modules.txt; run without --no-convert"
        } elif (empty(read_sync(fexist(doom_sync(v.name)) ? fread(doom_sync(v.name)) : ""))) {
            missing = "no demo verdicts in {doom_sync(v.name)}; run without --no-convert"
        } elif (!empty(error)) {
            missing = "doom/doom.c2das: {error}"
        }
    }
    if (!empty(missing)) {
        to_log(LOG_ERROR, "{PUREDOOM}: {missing}\n")
        return false
    }
    var patches : array<string>
    dir(DOOM_PATCHES) $(name) {
        if (name |> ends_with(".patch")) {
            patches |> push(name)
        }
    }
    sort(patches)
    let dir = path_join(repo, PUREDOOM)
    var ok = true
    var columns : array<VariantColumn>
    columns |> reserve(length(variants))
    var inscope readme = PureDoomReadme(pin = pin, freedoom = versions_line(versions, "freedoom"), generation = generation_line(gen), command = "scripts/publish_ports.sh --program {PUREDOOM}", fps_text = doom_fps_text(gen))
    readme.syncs |> reserve(length(variants))
    for (v, sidecar in variants, sidecars) {
        let tree = doom_tree(v)
        var inscope files <- tree_files(tree)
        ok = mirror_tree(tree, path_join(dir, "{v.name}/doom"), [for (rel in files); path_join(tree, rel)]) && ok
        ok = ok && write_or_log(path_join(dir, "{v.name}/doom.c2das"), sidecar)
        ok = ok && write_or_log(path_join(dir, "{v.name}/variant.json"), fread(variant_path(PUREDOOM, v.name)))
        readme.syncs |> emplace((name = v.name, cells <- read_sync(fread(doom_sync(v.name)))))
        var column = VariantColumn(file := v, das_lines = lines_of(tree, files))
        var fps : FpsCapture
        let fps_path = v.name == "readable" ? DOOM_FPS : path_join(doom_root(v.name), "results_linux.json")
        if (read_fps(fps_path, fps)) {
            fps_speed(fps, column.speed_fallback)
            column.speed_from = "c2das-re's `{fps_path}`, {fps.timestamp} on {box_label(fps.box, fps.cpu)}, c2das-re `{slice(fps.commit, 0, 12)}`" + (v.name == "readable" ? ", the converter's default flags" : "") + ", the geometric mean over its demos of the native frame rate over the tier's"
        }
        columns |> emplace(column)
    }
    readme.variants_text = render_variants(columns, false)
    ok = mirror_tree(DOOM_PATCHES, path_join(dir, "patches"), [for (name in patches); path_join(DOOM_PATCHES, name)]) && ok
    ok = ok && write_or_log(path_join(dir, "LICENSE"), license)
    readme.patches |> reserve(length(patches))
    for (name in patches) {
        readme.patches |> push((name = name, note = patch_note(fread(path_join(DOOM_PATCHES, name)))))
    }
    return ok && write_or_log(path_join(dir, "README.md"), puredoom_readme_text(readme))
}
