options gen2

require strings
require daslib/strings_boost
require daslib/fio
require daslib/clargs
require daslib/json_boost
require ../converter/pipeline.das
require ../converter/tiers.das
require ../converter/dumper_a.das
require ../perf/perf_lanes.das
require ports_render
require ../converter/sidecar.das
require ../compare/compare_render.das

//! The publisher of the ports repository (`lookibed/c2das-ports`): for each program it knows,
//! the converted modules, the sidecar, the upstream license and a README with the release, the
//! generating commit, how to run it, which upstream tests pass and the perf tables of a capture it
//! measures; then the top-level README's projects table, and with `--commit` a commit in the
//! clone. Run from the repository root through `scripts/publish_ports.sh`.

//! one workload of a program: its name, its program arguments, the arguments as the README shows
//! them, whether it runs in the release's test-suite folder (else in the repository root), whether
//! a das lane's output must equal the native build's (else the exit code alone is compared), the
//! line every run, the native oracle's too, must print ("" for none), since a test suite that stops
//! early can exit 0, and whether it is the startup row (no work: the program's load alone)
struct WorkloadSpec {
    name : string
    args : array<string>
    shown : string
    in_tests : bool
    compare_output : bool
    closing_line : string
    startup : bool
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

let ALL_LANES <- ["native", "interp", "jit", "exe", "aot", "interp-source-cut", "jit-source-cut", "interp-single", "jit-single"]
let STARTUP_ARGS <- ["-e", "print(1)"]
let WARM_UP_TIMEOUT = 3600.0
let IDENTITY <- ["-c", "user.name=lookibed", "-c", "user.email=93531352+lookibed@users.noreply.github.com"]

def private bench(name : string) : WorkloadSpec => <- WorkloadSpec(name = name, args <- [get_full_file_name("ports/lua/bench/{name}.lua")], shown = "bench/{name}.lua", compare_output = true)

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
        WorkloadSpec(name = "test suite", args <- ["-e", "_port=true", "all.lua"], shown = "-e \"_port=true\" all.lua", in_tests = true, closing_line = "final OK !!!")
    ])

[CommandLineArgs]
struct Args {
    @clarg_doc = "the clone of the ports repository (default: $C2DAS_PORTS, else ../c2das-ports beside this repository)"
    repo : string = ""
    @clarg_doc = "publish only this program (default: every program the publisher knows: lua)"
    program : string = ""
    @clarg_name = "no-convert"
    @clarg_doc = "skip the fetch and the conversion: publish what the harness's work/ folder holds"
    no_convert : bool
    @clarg_doc = "measure the workloads into a new capture and render the perf tables (default off: the perf method audit comes first)"
    perf : bool
    @clarg_doc = "samples per workload and lane, each its own process (default 5)"
    samples : int = 5
    @clarg_doc = "the das lanes to measure, comma-separated, out of interp,jit,exe,aot,interp-source-cut,jit-source-cut,interp-single,jit-single (default all): the -source-cut and -single lanes run those layouts' modules"
    lanes : string = "interp,jit,exe,aot,interp-source-cut,jit-source-cut,interp-single,jit-single"
    @clarg_doc = "seconds one sample may run before its cell fails (default 1800)"
    timeout : int = 1800
    @clarg_name = "allow-stale"
    @clarg_doc = "with --no-convert, publish a work/ folder whose conversion stamp is missing or names another commit than HEAD"
    allow_stale : bool
    @clarg_name = "allow-dirty"
    @clarg_doc = "publish from a c2das-re tree with uncommitted changes (the README names the commit -dirty)"
    allow_dirty : bool
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
def private stamp_of(port : Port) : string => path_join(port.harness, "work/publish.generation")
def private module_of(port : Port; stem, layout : string) : string => path_join(layout_dir(path_join(port.harness, "work"), stem, layout), "{stem}.das")

// the layout a das lane runs: the -source-cut and -single lanes those layouts' modules, the others the
// source layout's
def private lane_layout(lane : string) : string => lane |> ends_with("-single") ? "single" : lane |> ends_with("-source-cut") ? "source-cut" : "source"

// the das files of a program's source or source-cut layout under `dir` (its modules and fragments), each
// relative to `dir`: the ones the conversion's `program.modules.txt` lists, so a file an earlier
// conversion left there stays out; none when the list is missing
def private tree_files(dir : string) : array<string> {
    var files <- [for (ln in split(fread(path_join(dir, "program.modules.txt")), "\n")); strip(ln); where !empty(strip(ln))]
    sort(files)
    return <- files
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

// the fetch and the harness's conversion with its native oracle and run, the log kept beside
// the converted output for the README
def private run_harness(port : Port) : bool {
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
    let gen = tree_generation()
    return write_or_log(stamp_of(port), "{gen.sha}\n{gen.describe}\n{gen.date}\n")
}

def private clipped(text : string) : string => length(text) > 160 ? slice(text, 0, 157) + "..." : text

//! the native lane's first sample: what every other sample and every das lane must reproduce
struct Oracle {
    rc : int
    output : string
}

// the interpreter and the JIT compile the module on its first run in a folder and cache it there:
// one unmeasured run of the startup arguments keeps the compile out of the cells; "" or why it
// failed
def private warm_up(argv : array<string>; cwd : string) : string {
    var warm <- clone_to_move(argv)
    warm |> push_from(STARTUP_ARGS)
    var out : string
    let rc = run_and_capture(in_folder(cwd, warm), out, WARM_UP_TIMEOUT)
    if (rc == popen_timed_out) {
        return "the warm-up run timed out after {int(WARM_UP_TIMEOUT)} s"
    }
    return rc == 0 ? "" : clipped(with_line("the warm-up run exited {rc}", first_reported_line(out)))
}

def private with_line(text, line : string) : string => empty(line) ? text : "{text}: {line}"

// the first line where a sample's output and the native build's part
def private first_difference(output, native : string) : string {
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

// `samples` runs of `argv` in `cwd` ("" for here), each timed as a whole process; a run that
// differs from `oracle` (the native lane's first, when `oracle.rc` is not -1), or that leaves out
// the closing line `spec` names, fails the cell, which keeps the samples taken, the failing one last
[arch(at="ARCHITECTURE.md#measurement")]
def private measure_cell(argv : array<string>; cwd : string; samples, timeout : int; spec : WorkloadSpec; var oracle : Oracle; var cell : LaneCell) {
    let full <- in_folder(cwd, argv)
    cell.samples |> reserve(samples)
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
        let output = program_output(out)
        cell.samples |> push(seconds)
        if (rc == popen_timed_out) {
            cell.error = "timed out after {timeout} s"
        } elif (oracle.rc == -1 && rc != 0) {
            cell.error = clipped(with_line("exited {rc}", first_reported_line(output)))
        } elif (oracle.rc != -1 && rc != oracle.rc) {
            cell.error = clipped(with_line("exited {rc} where the native build exits {oracle.rc}", first_reported_line(output)))
        } elif (oracle.rc != -1 && spec.compare_output && output != oracle.output) {
            cell.error = clipped(first_difference(output, oracle.output))
        } elif (!empty(spec.closing_line) && !has_value(split(output, "\n"), spec.closing_line)) {
            cell.error = clipped(with_line("exited {rc} without the line `{spec.closing_line}`; its last line", last_line(output)))
        } elif (oracle.rc == -1) {
            oracle = Oracle(rc = rc, output = output)
        }
        if (!empty(cell.error)) {
            return
        }
    }
    cell.time = median_of(cell.samples)
    cell.spread = spread_of(cell.samples, cell.time)
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
        } elif (lane == "interp" || lane == "jit" || lane |> ends_with("-source-cut") || lane |> ends_with("-single")) {
            let layout = lane_layout(lane)
            let flag = lane |> starts_with("jit") ? "-jit" : ""
            run.argv <- das_lane_command(get_full_file_name(module_of(port, port.runs, layout)), flag, modules)
            run.argv |> push("--")
            let shown_module = layout == "single" ? "single/{port.runs}.das" : "{layout_dir("", port.runs, layout)}/{port.runs}.das"
            shown = join(["daslang -load_module <c2das-re>/dasCRuntime -load_module <c2das-re>/c_runtime", flag, "{shown_module} --"], " ") |> replace("  ", " ")
            run.error = warm_up(run.argv, "")
        } else {
            var error : string
            let bin = lane == "exe" ? build_exe(das_path, bench_work, STARTUP_ARGS, error) : build_aot(das_path, bench_work, STARTUP_ARGS, error)
            run.error = clipped(error)
            if (!empty(bin)) {
                run.argv <- [get_full_file_name(bin)]
            }
            shown = lane == "exe" ? "daslang -exe {port.runs}/{port.runs}.das, the binary run" : "the -ctx context and its host compiled by clang++ -O3 (c2das-re converter/tiers.das), the binary run"
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
    measured.machine = Machine(arch = strip(captured(["uname", "-m"])), cpu = cpu_name(), clang_path = default_clang())
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
                    if (spec.in_tests && (lane == "interp" || lane == "jit" || lane |> ends_with("-source-cut") || lane |> ends_with("-single"))) {
                        cell.error = warm_up(run.argv, tests)
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

def private readme_text(port : Port; release : Release; gen : Generation; command, perf_text, harness_log : string; perf : bool) : string {
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
        if (perf) {
            w |> write("- `bench/` - the benchmark scripts the tables below run.\n")
            w |> write("- `perf/capture_*.json` - every capture the tables were rendered from, every sample of every lane.\n\n")
        } else {
            w |> write("- `bench/` - the benchmark scripts the perf tables will run.\n\n")
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
        w |> write("{load} -exe lua/lua.das -output lua && ./lua.exe bench/fib.lua\n")
        w |> write("{load} luac/luac.das -- -o out.luac script.lua\n")
        w |> write("{load} single/lua.das -- -e \"print(1+1)\"\n```\n\n")
        w |> write("Everything after `--` is the program's own command line; daslang names the `-exe` binary with `.exe` on every platform.\n\n")
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

// the program's directory in the clone: every file of the fixed set replaced whole, every input
// checked before the first write; `gen` the commit the published conversion ran at
def private publish_program(args : Args; port : Port; lanes : array<string>; repo : string; var gen : Generation) : bool {
    var release : Release
    if (!release_of(fread("VERSIONS.md"), port.name, release) || length(release.tarballs) != 2) {
        to_log(LOG_ERROR, "{port.name}: VERSIONS.md names no `{port.name}:` line with the release and the test-suite tarballs\n")
        return false
    }
    if ((!args.no_convert && !run_harness(port)) || !generation_for(args, port, gen)) {
        return false
    }
    for (m in port.modules) {
        for (path in [module_of(port, m.stem, "source"), module_of(port, m.stem, "source-cut"), module_of(port, m.stem, "single"), path_join(dir_name(module_of(port, m.stem, "source")), "program.modules.txt"), path_join(dir_name(module_of(port, m.stem, "source-cut")), "program.modules.txt")]) {
            if (!fexist(path)) {
                to_log(LOG_ERROR, "{port.name}: no {path}; run without --no-convert\n")
                return false
            }
        }
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
    for (m in port.modules) {
        for (layout in ["source", "source-cut"]) {
            let tree = dir_name(module_of(port, m.stem, layout))
            let into = layout_dir(dir, m.stem, layout)
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
    for (spec in port.workloads) {
        if (!spec.startup && !spec.in_tests) {
            ok = ok && write_or_log(path_join(dir, spec.shown), fread(spec.args[0]))
        }
    }
    var perf_text = "{PERF_NOT_YET}\n"
    if (ok && args.perf) {
        ok = measure_program(args, port, release, lanes, dir, gen)
        var latest : Capture
        var found = false
        ok = ok && latest_capture(dir, latest, found)
        perf_text = render_perf(latest)
    }
    return ok && write_or_log(path_join(dir, "README.md"), readme_text(port, release, gen, publish_command(args, port), perf_text, harness_report(port), args.perf))
}

// the top-level README: the charter kept above the marker, the projects table (or the perf
// method line without `--perf`) below it, then the head-to-head when its capture exists
def private publish_top_readme(repo : string; perf : bool) : bool {
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
    var head_to_head : string
    if (!compare_section(head_to_head)) {
        return false
    }
    let path = path_join(repo, "README.md")
    return write_or_log(path, render_top_readme(fread(path), captures, perf) + head_to_head)
}

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

def private commit_program(port : Port; repo : string; gen : Generation) : bool {
    var out : string
    if (git_in(repo, ["add", "-A", "{port.name}/", "README.md"], out) != 0) {
        to_log(LOG_ERROR, "{port.name}: git add failed: {out}\n")
        return false
    }
    if (git_in(repo, ["diff", "--cached", "--quiet"], out) == 0) {
        to_log(LOG_INFO, "{port.name}: nothing to commit\n")
        return true
    }
    let message = gen.recorded ? "{port.name}: regenerated from c2das-re {gen.describe} ({gen.sha})" : "{port.name}: republished from c2das-re {gen.describe} ({gen.sha}), the conversion's commit unrecorded"
    var argv <- clone_to_move(IDENTITY)
    argv |> push_from(["commit", "-q", "-m", message])
    if (git_in(repo, argv, out) != 0) {
        to_log(LOG_ERROR, "{port.name}: git commit failed: {out}\n")
        return false
    }
    let head = git_line(repo, ["rev-parse", "--short", "HEAD"])
    to_log(LOG_INFO, "{port.name}: committed {head}\n")
    return true
}

def private repo_of(args : Args) : string {
    if (!empty(args.repo)) {
        return args.repo
    }
    return has_env_variable("C2DAS_PORTS") ? get_env_variable("C2DAS_PORTS") : "../c2das-ports"
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
    if (!empty(args.program) && !has_value([for (p in ports); p.name], args.program)) {
        to_log(LOG_ERROR, "ports: no program `{args.program}`; the publisher knows " + join([for (p in ports); p.name], ", ") + "\n")
        return 1
    }
    let das_lanes <- split(args.lanes, ",")
    var lanes <- ["native"]
    lanes |> reserve(1 + length(das_lanes))
    for (lane in das_lanes) {
        if (lane == "native" || !has_value(ALL_LANES, lane)) {
            to_log(LOG_ERROR, "ports: no das lane `{lane}`; --lanes takes interp, jit, exe, aot, interp-source-cut, jit-source-cut, interp-single and jit-single\n")
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
    for (port in ports) {
        var gen : Generation
        if (!publish_program(args, port, lanes, repo, gen) || !publish_top_readme(repo, args.perf)) {
            return 1
        }
        to_log(LOG_INFO, "{port.name}: published into {path_join(repo, port.name)}\n")
        if (args.commit && !commit_program(port, repo, gen)) {
            return 1
        }
    }
    var out : string
    if (args.push && git_in(repo, ["push", "-q", "origin", "HEAD"], out) != 0) {
        to_log(LOG_ERROR, "ports: git push failed: {out}\n")
        return 1
    }
    return 0
}
