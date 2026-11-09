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
require ../perf/boxes.das
require ../converter/sidecar.das
require ../compare/compare_render.das
require ../metrics/criteria_file.das
require ../compare/projects.das
require ../compare/rust_translator.das

//! The publisher of the ports repository (`lookibed/c2das-ports`): for each program it knows,
//! the converted modules, the sidecar, the upstream license and a README with the release, the
//! generating commit, how to run it, which upstream tests pass and the perf tables of a capture it
//! measures; then the top-level README's projects table, and with `--commit` a commit in the
//! clone. Run from the repository root through `scripts/publish_ports.sh`. Beside Lua it publishes
//! every real project of compare's `project_table`, converted as compare converts our side.

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

let ALL_LANES <- ["native", "interp", "jit", "exe", "jit-goto", "aot", "interp-source-cut", "jit-source-cut", "interp-single", "jit-single"]
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
    @clarg_doc = "publish only this program (default: every program the publisher knows: lua and the compare projects)"
    program : string = ""
    @clarg_name = "no-convert"
    @clarg_doc = "skip the fetch and the conversion: publish what the harness's work/ folder holds"
    no_convert : bool
    @clarg_doc = "measure the workloads into a new capture and render the perf tables (default off: the perf method audit comes first)"
    perf : bool
    @clarg_doc = "samples per workload and lane, each its own process (default 5)"
    samples : int = 5
    @clarg_doc = "the das lanes to measure, comma-separated, out of interp,jit,exe,jit-goto,aot,interp-source-cut,jit-source-cut,interp-single,jit-single (default all but aot): the -source-cut and -single lanes run those layouts' modules, jit-goto the source layout converted with --switch-dispatch goto"
    lanes : string = "interp,jit,exe,jit-goto,interp-source-cut,jit-source-cut,interp-single,jit-single"
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
def private goto_log_of(port : Port) : string => path_join(port.harness, "work/publish_goto_run.log")
def private stamp_of(port : Port) : string => path_join(port.harness, "work/publish.generation")
// the empty script the warm-up runs under `TIMED_LUA`
def private empty_script_of(port : Port) : string => get_full_file_name(path_join(port.harness, "work/bench/empty.lua"))
def private module_of(port : Port; stem, layout : string) : string => path_join(layout_dir(path_join(port.harness, "work"), stem, layout), "{stem}.das")

// the layout a das lane runs: the -source-cut and -single lanes those layouts' modules, `jit-goto`
// the source layout's converted with `--switch-dispatch goto` (its folder `work/goto/`), the others
// the source layout's
def private lane_layout(lane : string) : string => lane |> ends_with("-single") ? "single" : lane |> ends_with("-source-cut") ? "source-cut" : lane == "jit-goto" ? "goto" : "source"

// whether daslang runs `lane` over a converted module, which it caches in the folder it runs in;
// the exe and AOT lanes run a binary, the native lane the C build
def private runs_module(lane : string) : bool => lane != "native" && lane != "exe" && lane != "aot"

// the das files of a program's source or source-cut layout under `dir` (its modules and fragments), each
// relative to `dir`: the ones the conversion's `program.modules.txt` lists, so a file an earlier
// conversion left there stays out; none when the list is missing
def private tree_files(dir : string) : array<string> {
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

// the fetch, the harness's conversion with its native oracle and run, the log kept beside the
// converted output for the README, then the goto lane's conversion
def private run_harness(port : Port) : bool {
    // a stamp an earlier conversion left would name this HEAD over a work folder this run leaves
    // half written
    remove(stamp_of(port))
    var out : string
    if (run_and_capture(["bash", path_join(port.harness, "fetch.sh")], out, 3600.0) != 0) {
        to_log(LOG_ERROR, "{port.name}: {port.harness}/fetch.sh failed: {last_line(out)}\n")
        return false
    }
    var argv <- daslang_cmd(CONVERTED_MODULES)
    argv |> push_from([path_join(port.harness, "run.das"), "--", "--native", "--run"])
    to_log(LOG_INFO, "{port.name}: " + join(argv, " ") + "\n")
    let rc = run_and_capture(argv, out, 7200.0)
    fwrite(log_of(port), out)
    if (rc != 0) {
        to_log(LOG_ERROR, "{port.name}: the conversion exited {rc}; {log_of(port)} holds its log\n")
        return false
    }
    // the goto lane's tree: the source layout of the program the workloads run, converted with
    // the jump-table dispatch into `work/goto/`, its log apart from the one the README quotes
    var goto_argv <- daslang_cmd(CONVERTED_MODULES)
    goto_argv |> push_from([path_join(port.harness, "run.das"), "--", "--filter", port.runs, "--layout", "source", "--switch-dispatch", "goto"])
    to_log(LOG_INFO, "{port.name}: " + join(goto_argv, " ") + "\n")
    let goto_rc = run_and_capture(goto_argv, out, 7200.0)
    fwrite(goto_log_of(port), out)
    if (goto_rc != 0) {
        to_log(LOG_ERROR, "{port.name}: the goto-dispatch conversion exited {goto_rc}; {goto_log_of(port)} holds its log\n")
        return false
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

// `samples` runs of `argv` in `cwd` ("" for here), each timed as a whole process and, for a
// workload under `TIMED_LUA`, inside it by the wrapper's line, which the comparison does not see;
// a run that differs from `oracle` (the native lane's first, when `oracle.rc` is not -1), that
// leaves out the closing line `spec` names, or that prints no work seconds under the wrapper,
// fails the cell, which keeps the samples taken, the failing one last
[arch(at="ARCHITECTURE.md#measurement")]
def private measure_cell(argv : array<string>; cwd : string; samples, timeout : int; spec : WorkloadSpec; var oracle : Oracle; var cell : LaneCell) {
    let full <- in_folder(cwd, argv)
    cell.samples |> reserve(samples)
    cell.work_samples |> reserve(spec.timed ? samples : 0)
    for (_s in range(samples)) {
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
        if (!empty(cell.error)) {
            return
        }
    }
    cell.time = median_of(cell.samples)
    cell.spread = spread_of(cell.samples, cell.time)
    if (spec.timed) {
        cell.work_time = median_of(cell.work_samples)
        cell.work_time_spread = spread_of(cell.work_samples, cell.work_time)
    }
}

//! one lane ready to measure: the argv the program's arguments follow, or the reason it is not
struct LaneRun {
    argv : array<string>
    error : string
}

// every lane of `lanes` built once: native from the sources the harness's program manifest lists,
// the das lanes over the converted module, the program's arguments after `--` for the interpreter
// and the JIT
def private build_lanes(port : Port; lanes : array<string>; var into : Capture) : table<string; LaneRun> {
    var runs : table<string; LaneRun>
    let work = path_join(port.harness, "work")
    let bench_work = path_join(work, "bench")
    mkdir_rec(bench_work)
    let empty_script = empty_script_of(port)
    fwrite(empty_script, "")
    let manifest = path_join(work, "{port.runs}.program.json")
    let das_path = get_full_file_name(module_of(port, port.runs, "source"))
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
            } elif (run_and_capture(native_build_command(input.c_paths, bin, port.libs), out, 3600.0) != 0) {
                run.error = clipped(with_line("the build failed", first_reported_line(out)))
            }
            run.argv <- [get_full_file_name(bin)]
            var inscope listed <- empty(error) ? [for (c_path in input.c_paths); base_name(c_path)] : ["<the C files of {manifest}>"]
            shown = join(native_build_command(listed, "{port.runs}_native", port.libs), " ")
        } elif (runs_module(lane)) {
            let layout = lane_layout(lane)
            let flag = lane |> starts_with("jit") ? "-jit" : ""
            run.argv <- das_lane_command(get_full_file_name(module_of(port, port.runs, layout)), flag, modules)
            run.argv |> push("--")
            let shown_module = layout == "single" ? "single/{port.runs}.das" : layout == "goto" ? "{port.runs}/{port.runs}.das" : "{layout_dir("", port.runs, layout)}/{port.runs}.das"
            shown = join(["daslang -load_module <c2das-re>/dasCRuntime -load_module <c2das-re>/c_runtime", flag, "{shown_module} --"], " ") |> replace("  ", " ")
            // the goto tree is not published: the command names the conversion that regenerates it
            if (layout == "goto") {
                shown += ", {port.runs}/ converted by c2das-re's {port.harness}/run.das -- --filter {port.runs} --layout source --switch-dispatch goto"
            }
            run.error = warm_up(run.argv, "", empty_script)
        } else {
            var error : string
            let bin = lane == "exe" ? build_exe(das_path, bench_work, STARTUP_ARGS, error) : build_aot(das_path, bench_work, STARTUP_ARGS, error)
            run.error = clipped(error)
            if (!empty(bin)) {
                run.argv <- [get_full_file_name(bin)]
                // the AOT host is no standalone exe: the program's arguments follow `--`, as under daslang
                if (lane == "aot") {
                    run.argv |> push("--")
                }
                if (empty(run.error)) {
                    run.error = warm_up(run.argv, "", empty_script)
                }
            }
            shown = lane == "exe" ? "daslang -exe {port.runs}/{port.runs}.das, the binary run" : "the -ctx context and its host compiled by clang++ -O3 (c2das-re converter/tiers.das), the binary run with `--`"
        }
        into.lanes |> push(Lane(name = lane, command = shown, error = run.error))
        let reported = empty(run.error) ? join(run.argv, " ") : "not yet: {run.error}"
        to_log(LOG_INFO, "{port.name}/{lane}: {reported}\n")
        runs[lane] <- run
    }
    return <- runs
}

// a capture of every workload under every lane of `lanes`, written into the clone
def private measure_program(args : Args; port : Port; release : Release; lanes : array<string>; repo_dir : string; gen : Generation) : bool {
    var measured = Capture(program = port.name, commit = gen.sha, command = publish_command(args, port), samples = args.samples, timeout = args.timeout)
    let cpu = cpu_name()
    measured.machine = Machine(arch = strip(captured(["uname", "-m"])), cpu = cpu, box = capture_box(args.box, cpu), clang_path = default_clang())
    tool_versions(measured.machine.clang, measured.machine.daslang)
    var runs <- build_lanes(port, lanes, measured)
    let tests = get_full_file_name(tests_of(port, release))
    measured.workloads |> reserve(length(port.workloads))
    measured.cells |> reserve(length(port.workloads) * length(lanes))
    for (spec in port.workloads) {
        measured.workloads |> push(Workload(name = spec.name, args = spec.shown, startup = spec.startup))
        var oracle = Oracle(rc = -1)
        for (lane in lanes) {
            var cell = LaneCell(workload = spec.name, lane = lane)
            runs |> get(lane) $(run) {
                if (!empty(run.error)) {
                    cell.error = run.error
                } elif (lane != "native" && oracle.rc == -1) {
                    cell.error = "no native run to compare with"
                } elif (spec.in_tests && !stat(tests).is_dir) {
                    cell.error = "no {tests_of(port, release)}"
                } else {
                    // the test-suite folder has a module cache of its own to warm
                    if (spec.in_tests && runs_module(lane)) {
                        cell.error = warm_up(run.argv, tests, empty_script_of(port))
                    }
                    if (empty(cell.error)) {
                        var inscope argv <- clone_to_move(run.argv)
                        argv |> push_from(spec.args)
                        measure_cell(argv, spec.in_tests ? tests : "", args.samples, args.timeout, spec, oracle, cell)
                    }
                }
            }
            let reported = empty(cell.error) ? "{cell.time:.3f} s" : "not yet: {cell.error}"
            to_log(LOG_INFO, "{port.name}/{spec.name}/{lane}: {reported}\n")
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
def private readme_text(port : Port; release : Release; gen : Generation; command, perf_text, harness_log : string; captured : bool) : string {
    return build_string() $(var w) {
        w |> write("# {port.name}\n\n")
        w |> write("{port.title} {release.version} converted to daslang by [c2das-re](https://github.com/lookibed/c2das-re). ")
        w |> write("Everything in this directory is generated by `{command}` in c2das-re; never edit it, a fix belongs in c2das-re.\n\n")
        w |> write("## Files\n\n")
        for (m in port.modules) {
            w |> write("- `{m.stem}/` - {m.role}, converted as a module per C file, every cycle of files one module of `.das.inc` fragments (c2das-re's source layout, its default; `{m.stem}/program.layout.txt` lists the modules); `{m.stem}/{m.stem}.das` holds `main`.\n")
        }
        for (m in port.modules) {
            w |> write("- `source-cut/{m.stem}/` - the same program with the cycles among files cut by late binding through `source-cut/{m.stem}/{m.stem}_link.das` (c2das-re's `--layout source-cut`; its `program.layout.txt` lists the cut).\n")
        }
        for (m in port.modules) {
            w |> write("- `single/{m.stem}.das` - the same program as one module (c2das-re's `--layout single`).\n")
        }
        w |> write("- `{port.name}.c2das` - the sidecar both were converted under.\n")
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
        w |> write("{load} lua/lua.das -- -e \"print(1+1)\"\n")
        w |> write("{load} -jit lua/lua.das -- bench/fib.lua\n")
        w |> write("{load} -exe lua/lua.das -output lua && ./lua bench/fib.lua\n")
        w |> write("{load} luac/luac.das -- -o out.luac script.lua\n")
        w |> write("{load} single/lua.das -- -e \"print(1+1)\"\n```\n\n")
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
            w |> write("\nThe harness's report of this conversion (`{port.harness}/run.das --native --run`: the native binaries' sizes, the JSON bytes, ")
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

// the lines of the harness's log that report the conversion, without their seconds
def private harness_report(port : Port) : string {
    var lines : array<string>
    for (ln in split(fread(log_of(port)), "\n")) {
        let line = clock_free(strip(ln))
        if (ln |> contains("{port.name}: ") && !empty(line)) {
            lines |> push(line)
        }
    }
    return empty(lines) ? "" : join(lines, "\n") + "\n"
}

def private write_or_log(path, text : string) : bool {
    if (!fwrite(path, text)) {
        to_log(LOG_ERROR, "ports: cannot write {path}\n")
        return false
    }
    return true
}

// every file of the conversion the publish reads or the goto lane runs: each module's three layouts
// with the module lists, and the goto tree's entry module; false with the first missing one logged
def private converted_files_exist(port : Port) : bool {
    var paths <- [module_of(port, port.runs, "goto")]
    for (m in port.modules) {
        paths |> push_from([module_of(port, m.stem, "source"), module_of(port, m.stem, "source-cut"), module_of(port, m.stem, "single"), path_join(dir_name(module_of(port, m.stem, "source")), "program.modules.txt"), path_join(dir_name(module_of(port, m.stem, "source-cut")), "program.modules.txt")])
    }
    for (path in paths) {
        if (!fexist(path)) {
            to_log(LOG_ERROR, "{port.name}: no {path}; run without --no-convert\n")
            return false
        }
    }
    return true
}

// the program's directory in the clone: every file of the fixed set replaced whole, every input
// checked before the first write; `gen` the commit the published conversion ran at
def private publish_program(args : Args; port : Port; lanes : array<string>; repo : string; var gen : Generation) : bool {
    var release : Release
    if (!release_of(fread("VERSIONS.md"), port.name, release) || length(release.tarballs) != 2) {
        to_log(LOG_ERROR, "{port.name}: VERSIONS.md names no `{port.name}:` line with the release and the test-suite tarballs\n")
        return false
    }
    if ((!args.no_convert && !run_harness(port)) || !generation_for(args, port, gen) || !converted_files_exist(port)) {
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
    let dir = path_join(repo, port.name)
    mkdir_rec(path_join(dir, "bench"))
    var ok = true
    mkdir_rec(path_join(dir, "single"))
    // the folder the cut layout had under its former name `scc`
    if (fexist(path_join(dir, "scc"))) {
        rmdir_rec(path_join(dir, "scc"))
    }
    for (m in port.modules) {
        for (layout in ["source", "source-cut"]) {
            let tree = dir_name(module_of(port, m.stem, layout))
            let into = layout_dir(dir, m.stem, layout)
            var inscope kept <- tree_files(tree)
            kept |> push("program.layout.txt")
            if (!drop_unlisted(into, kept)) {
                to_log(LOG_ERROR, "{port.name}: cannot remove a stale file under {into}\n")
                ok = false
            }
            for (rel in tree_files(tree)) {
                let target = path_join(into, rel)
                mkdir_rec(dir_name(target))
                ok = ok && write_or_log(target, fread(path_join(tree, rel)))
            }
        }
        for (layout in ["source", "source-cut"]) {
            let report = path_join(dir_name(module_of(port, m.stem, layout)), "program.layout.txt")
            if (fexist(report)) {
                ok = ok && write_or_log(path_join(layout_dir(dir, m.stem, layout), "program.layout.txt"), fread(report))
            }
        }
        ok = ok && write_or_log(path_join(dir, "single/{m.stem}.das"), fread(module_of(port, m.stem, "single")))
    }
    ok = ok && write_or_log(path_join(dir, "LICENSE"), license)
    ok = ok && write_or_log(path_join(dir, "{port.name}.c2das"), fread(sidecar_of(port)))
    ok = ok && write_or_log(path_join(dir, "bench/{base_name(TIMED_LUA)}"), fread(TIMED_LUA))
    for (spec in port.workloads) {
        if (!spec.startup && !spec.in_tests) {
            let script = spec.args[length(spec.args) - 1]
            ok = ok && write_or_log(path_join(dir, "bench/{base_name(script)}"), fread(script))
        }
    }
    if (ok && args.perf) {
        ok = measure_program(args, port, release, lanes, dir, gen)
    }
    // the tables render from the latest capture, this publish's or an earlier one's
    var latest : Capture
    var found = false
    ok = ok && latest_capture(dir, latest, found)
    let perf_text = found ? measured_note(latest.commit, "", gen) + render_perf(latest) : "{PERF_NOT_YET}\n"
    return ok && write_or_log(path_join(dir, "README.md"), readme_text(port, release, gen, publish_command(args, port), perf_text, harness_report(port), found))
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

// a project's README: what was converted (or what refused and the per-file results), the sources,
// how to run it, the speed from the head-to-head's capture and the criteria line
def private project_readme_text(p : Project; gen : Generation; rust_sha, refusal : string; files : array<FileConversion>; command, perf_text, criteria_text : string) : string {
    let stem = trim_suffix(base_name(p.tu), ".c")
    let fixture = "<c2das>/{MANUAL_DIR}/{p.name}/{p.fixture}"
    return build_string() $(var w) {
        w |> write("# {p.name}\n\n")
        w |> write("The real project {p.name} of the Rust translator's `{MANUAL_DIR}` ([lookibed/c2das](https://github.com/lookibed/c2das)) converted to daslang by [c2das-re](https://github.com/lookibed/c2das-re), as its head-to-head converts our side. ")
        w |> write("Everything in this directory is generated by `{command}` in c2das-re; never edit it, a fix belongs in c2das-re.\n\n")
        w |> write("## Conversion\n\n")
        if (empty(refusal)) {
            w |> write("The program converts whole: `{stem}/` holds it (`{stem}/{stem}.das` holds `main`).\n\n")
        } else {
            let converted = length([for (f in files); f; where empty(f.refusal)])
            w |> write("The program does not convert whole yet: {path_free(refusal, p.dir)}\n\n")
            w |> write("What does convert: each C file of the program converted alone, {converted} of {length(files)} (`files/`, a module per file at its path under the project folder; ")
            w |> write("a file alone is no program, so these modules show the conversion and do not run):\n\n")
            var rows : array<array<string>>
            for (f in files) {
                rows |> emplace([f.c_path, empty(f.refusal) ? "converted" : "refused: {path_free(f.refusal, p.dir)}"])
            }
            w |> write(table_of(["C file", "Result"], rows, 2))
            w |> write("\n")
        }
        w |> write("## Files\n\n")
        if (empty(refusal)) {
            w |> write("- `{stem}/` - the program converted from `{p.tu}`" + (empty(p.units) ? "" : " and the other units of its canonical case, a module per C file (c2das-re's source layout; `{stem}/{LAYOUT_REPORT}` lists the modules)") + ".\n")
        } else {
            w |> write("- `files/` - each C file that converts alone, as its module.\n")
        }
        w |> write("- `{p.name}.c2das` - the sidecar the conversion ran under, its paths in the Rust checkout written under `<c2das>`, that checkout.\n")
        w |> write("- `LICENSE` - the license of the upstream code under `{MANUAL_DIR}/{p.name}/upstream/`; the conversion is a derived work.\n\n")
        w |> write("## Source\n\n")
        w |> write("- The C sources: `{MANUAL_DIR}/{p.name}/` of lookibed/c2das at `{rust_sha}`; its `UPSTREAM.md` names each upstream and its revision.\n")
        w |> write("- {generation_line(gen)}\n\n")
        w |> write("## Running\n\n")
        w |> write("The modules require c2das-re's `crt` and `c_runtime` modules: a c2das-re checkout at the commit above, with the daScript its `VERSIONS.md` pins built and `scripts/build_crt.sh` run. ")
        w |> write("The program reads its fixture `{p.fixture}` from the Rust repository's project folder; no fixture is copied here (game data and fixtures stay with their own licenses there). ")
        w |> write("With `<c2das-re>` and `<c2das>` the two checkouts:\n\n```\n")
        let load = "daslang -load_module <c2das-re>/dasCRuntime -load_module <c2das-re>/c_runtime"
        if (empty(refusal)) {
            w |> write("{load} {stem}/{stem}.das -- {fixture}\n{load} -jit {stem}/{stem}.das -- {fixture}\n")
        } else {
            w |> write("# not runnable yet: the program does not convert whole\n")
        }
        var native <- ["clang"]
        native |> push_from(clang_args(p), p.native_flags, p.native_sources, p.link_flags)
        w |> write("# the native build the tables compare with, in <c2das>/{MANUAL_DIR}/{p.name}:\n" + replace(join(native, " "), "{p.dir}/", "") + " -o {p.name}\n```\n\n")
        w |> write("Its output must equal `expected.stdout` of the canonical case `{p.case_id}` in the Rust repository's `{CASES_FILE}`.\n\n")
        w |> write("## Performance\n\n{perf_text}\n")
        w |> write("## Readability criteria\n\n{criteria_text}")
    }
}

// a compare project's directory in the clone: converted whole, else file by file, every input
// read and the conversion done before the first write into the clone
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
    let work = project_work(p.name)
    let whole = path_join(work, "whole")
    var inscope conv <- convert_project(p, work)
    let refusal = conv.refusal
    gen = tree_generation()
    let dir = path_join(repo, p.name)
    mkdir_rec(dir)
    let stem = trim_suffix(base_name(p.tu), ".c")
    var ok = mirror_tree(whole, path_join(dir, stem), empty(refusal) ? conv.files : array<string>())
    var inscope converted : array<string>
    for (f in conv.per_file) {
        if (!empty(f.das_path)) {
            converted |> push(f.das_path)
        }
    }
    ok = mirror_tree(path_join(work, "files"), path_join(dir, "files"), converted) && ok
    ok = ok && write_or_log(path_join(dir, "{p.name}.c2das"), replace(fread(path_join(whole, "{p.name}.c2das")), p.dir, "<c2das>/{MANUAL_DIR}/{p.name}"))
    ok = ok && write_or_log(path_join(dir, "LICENSE"), license)
    let command = "scripts/publish_ports.sh --program {p.name}"
    let rust_sha = git_line(rust_checkout(), ["rev-parse", "HEAD"])
    why = ok ? "" : "a file of its directory was not written"
    return ok && write_or_log(path_join(dir, "README.md"), project_readme_text(p, gen, rust_sha, refusal, conv.per_file, command, project_perf_text(p), project_criteria(p, gen)))
}

def private repo_of(args : Args) : string {
    if (!empty(args.repo)) {
        return args.repo
    }
    return has_env_variable("C2DAS_PORTS") ? get_env_variable("C2DAS_PORTS") : "../c2das-ports"
}

// every compare project of `projects` that `--program` names (all without it) published, the
// top-level README after each, and committed with `--commit`; false at the first that fails
def private publish_projects(args : Args; projects : array<Project>; repo : string; var failures : array<string>; var published : int&) {
    for (p in projects) {
        if (!empty(args.program) && args.program != p.name) {
            continue
        }
        if (args.no_convert) {
            to_log(LOG_WARNING, "{p.name}: not published: a compare project converts on every publish, and --no-convert converts nothing\n")
            continue
        }
        if (!stat(p.dir).is_dir) {
            to_log(LOG_WARNING, "{p.name}: not published: the Rust checkout has no {p.dir}\n")
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
    if (!empty(args.program) && !has_value(known, args.program)) {
        to_log(LOG_ERROR, "ports: no program `{args.program}`; the publisher knows " + join(known, ", ") + "\n")
        return 1
    }
    let das_lanes <- split(args.lanes, ",")
    var lanes <- ["native"]
    lanes |> reserve(1 + length(das_lanes))
    for (lane in das_lanes) {
        if (lane == "native" || !has_value(ALL_LANES, lane)) {
            to_log(LOG_ERROR, "ports: no das lane `{lane}`; --lanes takes interp, jit, exe, jit-goto, aot, interp-source-cut, jit-source-cut, interp-single and jit-single\n")
            return 1
        }
        lanes |> push(lane)
    }
    if (args.push && !args.commit) {
        to_log(LOG_ERROR, "ports: --push needs --commit\n")
        return 1
    }
    if (args.samples < 1) {
        to_log(LOG_ERROR, "ports: --samples takes a count of 1 or more, not {args.samples}\n")
        return 1
    }
    if (args.timeout <= 0) {
        to_log(LOG_ERROR, "ports: --timeout takes seconds above 0, not {args.timeout}\n")
        return 1
    }
    let refusal = box_refusal(args.box, cpu_name())
    if (!empty(refusal)) {
        to_log(LOG_ERROR, "ports: {refusal}\n")
        return 1
    }
    let repo = repo_of(args)
    if (!is_clone(repo)) {
        to_log(LOG_ERROR, "ports: {repo} is no clone of the ports repository (not the top of a git work tree)\n")
        return 1
    }
    var status : string
    if (git_in(".", ["status", "--porcelain"], status) != 0) {
        to_log(LOG_ERROR, "ports: run from the c2das-re checkout: {strip(status)}\n")
        return 1
    }
    if (!empty(strip(status)) && !args.allow_dirty) {
        to_log(LOG_ERROR, "ports: the c2das-re tree has uncommitted changes; commit them or pass --allow-dirty\n")
        return 1
    }
    var failures : array<string>
    var published = 0
    for (port in ports) {
        if (!empty(args.program) && args.program != port.name) {
            continue
        }
        var gen : Generation
        if (!publish_program(args, port, lanes, repo, gen) || !publish_top_readme(repo, failures)) {
            failures |> push("{port.name}: the publish failed (its log names why)")
            continue
        }
        to_log(LOG_INFO, "{port.name}: published into {path_join(repo, port.name)}\n")
        published++
        if (args.commit && !commit_program(port.name, repo, gen)) {
            failures |> push("{port.name}: the commit failed")
        }
    }
    publish_projects(args, projects, repo, failures, published)
    return finish(args, repo, failures, published)
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
