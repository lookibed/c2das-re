options gen2

require strings
require daslib/strings_boost
require daslib/fio
require daslib/clargs
require daslib/json_boost
require ../converter/pipeline.das
require ../converter/tiers.das
require ../perf/perf_lanes.das
require ports_render

//! The publisher of the ports repository (`lookibed/c2das-ports`): for each program it knows,
//! the converted modules, the sidecar, the upstream license and a README with the release, the
//! generating commit, how to run it, which upstream tests pass and the perf tables of a capture it
//! measures; then the top-level README's projects table, and with `--commit` a commit in the
//! clone. Run from the repository root through `scripts/publish_ports.sh`.

//! one workload of a program: its program arguments, the folder it runs in ("" for the repository
//! root, else a folder under the program's fetch/), and whether a das lane's output must equal
//! the native build's (else the exit code alone is compared)
struct WorkloadSpec {
    name : string
    args : array<string>
    shown : string
    in_tests : bool
    compare_output : bool
    startup : bool
}

//! one program the publisher knows: its harness folder, the composed modules it publishes, the
//! module the workloads run, the libraries its native build links, and its claims
struct Port {
    name : string
    title : string
    harness : string
    modules : array<tuple<stem : string; role : string>>
    runs : string
    libs : array<string>
    license_header : string
    claims : array<string>
    workloads : array<WorkloadSpec>
}

let ALL_LANES <- ["native", "interp", "jit", "exe", "aot"]
let STARTUP_ARGS <- ["-e", "print(1)"]
let IDENTITY <- ["-c", "user.name=lookibed", "-c", "user.email=93531352+lookibed@users.noreply.github.com"]

def private bench(name : string) : WorkloadSpec => <- WorkloadSpec(name = name, args <- [get_full_file_name("ports/lua/bench/{name}.lua")], shown = "bench/{name}.lua", compare_output = true)

def private lua_port : Port => <- Port(
    name = "lua", title = "Lua", harness = "lua", runs = "lua_all", license_header = "lua.h",
    modules <- [
        (stem = "lua_all", role = "the interpreter `lua`: the core, the standard libraries and `lua.c` as one translation unit"),
        (stem = "luac_all", role = "the compiler `luac`: the core, the auxiliary library and `luac.c` as one translation unit")
    ],
    libs <- ["-lm"],
    claims <- [
        "`lua -e \"print(1+1)\"` and a script over string, table and math print what the native build prints, under the interpreter and the JIT.",
        "`luac -o` writes the native build's bytecode byte for byte for every file of the release's test suite.",
        "Lua's own test suite is not run yet (c2das-re's P5.3): Lua's error recovery is a stub until P5.2, so a Lua error, and with it every `pcall` that catches one, aborts the process."
    ],
    workloads <- [
        WorkloadSpec(name = "startup", args <- clone_to_move(STARTUP_ARGS), shown = "-e \"print(1)\"", compare_output = true, startup = true),
        bench("fib"),
        bench("binary_trees"),
        bench("nbody"),
        bench("spectral_norm"),
        WorkloadSpec(name = "test suite", args <- ["-e", "_port=true", "all.lua"], shown = "-e \"_port=true\" all.lua", in_tests = true)
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
    @clarg_doc = "the das lanes to measure, comma-separated, out of interp,jit,exe,aot (default all)"
    lanes : string = "interp,jit,exe,aot"
    @clarg_doc = "seconds one sample may run before its cell fails (default 1800)"
    timeout : int = 1800
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

//! the facts of one publish, each read once
struct Generation {
    describe : string
    sha : string
    date : string
    command : string
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
def private is_clone(repo : string) : bool {
    let top = git_line(repo, ["rev-parse", "--show-toplevel"])
    return !empty(top) && top == strip(captured(["realpath", repo]))
}

def private generation_of(args : Args; port : Port) : Generation {
    var command = "scripts/publish_ports.sh --program {port.name}"
    if (args.no_convert) {
        command += " --no-convert"
    }
    if (args.perf) {
        command += " --perf"
    }
    return Generation(describe = git_line(".", ["describe", "--tags", "--always", "--dirty"]), sha = git_line(".", ["rev-parse", "HEAD"]), date = git_line(".", ["log", "-1", "--format=%cs"]), command = command)
}

def private tarball_stem(url : string) : string {
    let name = base_name(url)
    return name |> ends_with(".tar.gz") ? slice(name, 0, length(name) - length(".tar.gz")) : name
}

// the program's fetched release: `fetch/<release tarball>/src` and `fetch/<tests tarball>`
def private sources_of(port : Port; release : Release) : string => path_join(port.harness, "fetch/{tarball_stem(release.tarballs[0].url)}/src")
def private tests_of(port : Port; release : Release) : string => path_join(port.harness, "fetch/{tarball_stem(release.tarballs[1].url)}")
def private log_of(port : Port) : string => path_join(port.harness, "work/publish_run.log")

// the fetch and the harness's conversion with its native oracle and run, the log kept beside
// the converted output for the README
def private convert_program(port : Port) : bool {
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
    return true
}

// a sample's output without the JIT's `info` lines
def private program_output(text : string) : string => join([for (ln in split(text, "\n")); ln; where !(ln |> starts_with("[I] "))], "\n")

def private clipped(text : string) : string => length(text) > 160 ? slice(text, 0, 157) + "..." : text

//! the native lane's first sample: what every other sample and every das lane must reproduce
struct Oracle {
    rc : int
    output : string
}

// `argv` run in the folder `cwd`, "" for here
def private in_folder(cwd : string; argv : array<string>) : array<string> {
    var full : array<string>
    if (!empty(cwd)) {
        full |> push_from(["sh", "-c", "cd \"$0\" && exec \"$@\"", cwd])
    }
    full |> push_from(argv)
    return <- full
}

// the JIT compiles the module on its first run in a folder and caches it there: one unmeasured
// run of the startup arguments keeps the compile out of the cells; "" or why it failed
def private warm_up(argv : array<string>; cwd : string) : string {
    var warm <- clone_to_move(argv)
    warm |> push_from(STARTUP_ARGS)
    var out : string
    let rc = run_and_capture(in_folder(cwd, warm), out, 3600.0)
    return rc == 0 ? "" : clipped(with_line("the warm-up run exited {rc}", first_reported_line(out)))
}

def private with_line(text, line : string) : string => empty(line) ? text : "{text}: {line}"

// `samples` runs of `argv` in `cwd` ("" for here), each timed as a whole process; a run that
// differs from `oracle` (the native lane's first, when `oracle.rc` is not -1) fails the cell
[arch(at="ARCHITECTURE.md#measurement")]
def private measure_cell(argv : array<string>; cwd : string; samples, timeout : int; compare_output : bool; var oracle : Oracle; var cell : LaneCell) {
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
        if (rc == popen_timed_out) {
            cell.error = "timed out after {timeout} s"
        } elif (oracle.rc == -1 && rc != 0) {
            cell.error = clipped(with_line("exited {rc}", last_line(output)))
        } elif (oracle.rc == -1) {
            oracle = Oracle(rc = rc, output = output)
        } elif (rc != oracle.rc) {
            cell.error = clipped(with_line("exited {rc} where the native build exits {oracle.rc}", last_line(output)))
        } elif (compare_output && output != oracle.output) {
            cell.error = clipped("prints `{last_line(output)}` where the native build prints `{last_line(oracle.output)}`")
        }
        if (!empty(cell.error)) {
            return
        }
        cell.samples |> push(seconds)
    }
    cell.time = median_of(cell.samples)
    cell.spread = spread_of(cell.samples, cell.time)
}

//! one lane ready to measure: the argv the program's arguments follow, or the reason it is not
struct LaneRun {
    argv : array<string>
    error : string
}

// every lane of `lanes` built once: native from the composed C file, the das lanes over the
// converted module, the program's arguments after `--` for the interpreter and the JIT
def private build_lanes(port : Port; lanes : array<string>; var into : Capture) : table<string; LaneRun> {
    var runs : table<string; LaneRun>
    let work = path_join(port.harness, "work")
    let bench_work = path_join(work, "bench")
    mkdir_rec(bench_work)
    let c_path = path_join(work, "{port.runs}.c")
    let das_path = get_full_file_name(path_join(work, "{port.runs}/{port.runs}.das"))
    let modules <- [for (dir in CONVERTED_MODULES); get_full_file_name(dir)]
    into.lanes |> reserve(length(lanes))
    for (lane in lanes) {
        var run : LaneRun
        var shown : string
        if (lane == "native") {
            let bin = path_join(bench_work, "{port.runs}_native")
            var out : string
            if (run_and_capture(native_build_command(c_path, bin, port.libs), out, 3600.0) != 0) {
                run.error = clipped(with_line("the build failed", first_reported_line(out)))
            }
            run.argv <- [get_full_file_name(bin)]
            shown = join(native_build_command("{port.runs}.c", "{port.runs}_native", port.libs), " ")
        } elif (lane == "interp" || lane == "jit") {
            let flag = lane == "jit" ? "-jit" : ""
            run.argv <- das_lane_command(das_path, flag, modules)
            run.argv |> push("--")
            shown = join(["daslang -load_module <c2das-re>/dasCRuntime -load_module <c2das-re>/c_runtime", flag, "{port.runs}.das --"], " ") |> replace("  ", " ")
            if (lane == "jit") {
                run.error = warm_up(run.argv, "")
            }
        } else {
            var error : string
            let bin = lane == "exe" ? build_exe(das_path, bench_work, STARTUP_ARGS, error) : build_aot(das_path, bench_work, STARTUP_ARGS, error)
            run.error = clipped(error)
            if (!empty(bin)) {
                run.argv <- [get_full_file_name(bin)]
            }
            shown = lane == "exe" ? "daslang -exe {port.runs}.das, the binary run" : "the -ctx context and its host compiled by clang++ -O3 (c2das-re converter/tiers.das), the binary run"
        }
        into.lanes |> push(Lane(name = lane, command = shown, error = run.error))
        let reported = empty(run.error) ? join(run.argv, " ") : "not yet: {run.error}"
        to_log(LOG_INFO, "{port.name}/{lane}: {reported}\n")
        runs[lane] <- run
    }
    return <- runs
}

// a capture of every workload under every lane of `lanes`, written into the clone
def private measure_program(args : Args; port : Port; release : Release; lanes : array<string>; repo_dir : string) : bool {
    var measured = Capture(program = port.name, samples = args.samples)
    measured.timestamp = strip(captured(["date", "-u", "+%Y-%m-%d %H:%M UTC"]))
    measured.machine = Machine(arch = strip(captured(["uname", "-m"])), cpu = cpu_name())
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
                    if (lane == "jit" && spec.in_tests) {
                        warm_up(run.argv, tests)
                    }
                    var inscope argv <- clone_to_move(run.argv)
                    argv |> push_from(spec.args)
                    measure_cell(argv, spec.in_tests ? tests : "", args.samples, args.timeout, spec.compare_output, oracle, cell)
                }
            }
            let reported = empty(cell.error) ? "{cell.time:.3f} s" : "not yet: {cell.error}"
            to_log(LOG_INFO, "{port.name}/{spec.name}/{lane}: {reported}\n")
            measured.cells |> emplace(cell)
        }
    }
    let perf_dir = path_join(repo_dir, "perf")
    mkdir_rec(perf_dir)
    let stamp = strip(captured(["date", "-u", "+%Y-%m-%dT%H%M%SZ"]))
    return fwrite(path_join(perf_dir, "capture_{stamp}.json"), write_json(JV(measured)) + "\n")
}

// the latest capture under `<dir>/perf/`, by its name's timestamp; false when there is none
def private latest_capture(dir : string; var into : Capture) : bool {
    var latest = ""
    let perf_dir = path_join(dir, "perf")
    if (stat(perf_dir).is_dir) {
        dir(perf_dir) $(name) {
            if (name |> starts_with("capture_") && name |> ends_with(".json") && name > latest) {
                latest = name
            }
        }
    }
    if (empty(latest)) {
        return false
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

def private readme_text(port : Port; release : Release; gen : Generation; perf, has_capture : bool; shown_capture : Capture; harness_log : string) : string {
    return build_string() $(var w) {
        w |> write("# {port.name}\n\n")
        w |> write("{port.title} {release.version} converted to daslang by [c2das-re](https://github.com/lookibed/c2das-re). ")
        w |> write("Everything in this directory is generated by `{gen.command}` in c2das-re; never edit it, a fix belongs in c2das-re.\n\n")
        w |> write("## Files\n\n")
        for (m in port.modules) {
            w |> write("- `{m.stem}.das` - {m.role}, converted.\n")
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
        w |> write("- Generated by c2das-re `{gen.describe}` (`{gen.sha}`, committed {gen.date})\n\n")
        w |> write("## Running\n\n")
        w |> write("The modules require c2das-re's `crt` and `c_runtime` modules: a c2das-re checkout at the commit above, ")
        w |> write("with the daScript its `VERSIONS.md` pins built and `scripts/build_crt.sh` run. With `<c2das-re>` that checkout:\n\n```\n")
        let load = "daslang -load_module <c2das-re>/dasCRuntime -load_module <c2das-re>/c_runtime"
        w |> write("{load} lua_all.das -- -e \"print(1+1)\"\n")
        w |> write("{load} -jit lua_all.das -- bench/fib.lua\n")
        w |> write("{load} -exe lua_all.das -output lua && ./lua.exe bench/fib.lua\n")
        w |> write("{load} luac_all.das -- -o out.luac script.lua\n```\n\n")
        w |> write("Everything after `--` is the program's own command line; daslang names the `-exe` binary with `.exe` on every platform.\n\n")
        w |> write("## Upstream tests\n\n")
        for (claim in port.claims) {
            w |> write("- {claim}\n")
        }
        if (empty(harness_log)) {
            w |> write("\nThis publish reused a conversion that left no harness log.\n\n")
        } else {
            w |> write("\nThe harness's report of this conversion (`{port.harness}/run.das --native --run`: the dumper, emitter and compile-check seconds, the das line counts, and `lua -e \"print(1+1)\"` under the interpreter against the native build):\n\n```\n{harness_log}```\n\n")
        }
        w |> write("## Performance\n\n")
        if (!perf) {
            w |> write("{PERF_NOT_YET}\n")
        } elif (has_capture) {
            w |> write(render_perf(shown_capture))
        } else {
            w |> write("No capture yet.\n")
        }
    }
}

// the lines of the harness's log that report the conversion
def private harness_report(port : Port) : string {
    let lines <- [for (ln in split(fread(log_of(port)), "\n")); strip(ln); where ln |> contains("{port.name}: ")]
    return empty(lines) ? "" : join(lines, "\n") + "\n"
}

def private write_or_log(path, text : string) : bool {
    if (!fwrite(path, text)) {
        to_log(LOG_ERROR, "ports: cannot write {path}\n")
        return false
    }
    return true
}

// the program's directory in the clone: every file of the fixed set replaced whole
def private publish_program(args : Args; port : Port; lanes : array<string>; repo : string) : bool {
    var release : Release
    if (!release_of(fread("VERSIONS.md"), port.name, release) || length(release.tarballs) != 2) {
        to_log(LOG_ERROR, "{port.name}: VERSIONS.md names no `{port.name}:` line with the release and the test-suite tarballs\n")
        return false
    }
    if (!args.no_convert && !convert_program(port)) {
        return false
    }
    let dir = path_join(repo, port.name)
    mkdir_rec(path_join(dir, "bench"))
    for (m in port.modules) {
        let das = path_join(port.harness, "work/{m.stem}/{m.stem}.das")
        if (!fexist(das)) {
            to_log(LOG_ERROR, "{port.name}: no {das}; run without --no-convert\n")
            return false
        }
        if (!write_or_log(path_join(dir, "{m.stem}.das"), fread(das))) {
            return false
        }
    }
    let license = license_block(fread(path_join(sources_of(port, release), port.license_header)))
    if (empty(license)) {
        to_log(LOG_ERROR, "{port.name}: {sources_of(port, release)}/{port.license_header} holds no license block\n")
        return false
    }
    var ok = write_or_log(path_join(dir, "LICENSE"), license)
    ok = ok && write_or_log(path_join(dir, "{port.name}.c2das"), fread(path_join(port.harness, "{port.name}.c2das")))
    for (spec in port.workloads) {
        if (!spec.startup && !spec.in_tests) {
            ok = ok && write_or_log(path_join(dir, spec.shown), fread(spec.args[0]))
        }
    }
    if (ok && args.perf) {
        ok = measure_program(args, port, release, lanes, dir)
    }
    var latest : Capture
    let has_capture = latest_capture(dir, latest)
    return ok && write_or_log(path_join(dir, "README.md"), readme_text(port, release, generation_of(args, port), args.perf, has_capture, latest, harness_report(port)))
}

// the top-level README: the charter kept above the marker, the projects table (or the perf
// method line without `--perf`) below it
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
        if (latest_capture(path_join(repo, name), latest)) {
            captures |> emplace(latest)
        }
    }
    let path = path_join(repo, "README.md")
    return write_or_log(path, render_top_readme(fread(path), captures, perf))
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
    var argv <- clone_to_move(IDENTITY)
    argv |> push_from(["commit", "-q", "-m", "{port.name}: regenerated from c2das-re {gen.describe} ({gen.sha})"])
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
            to_log(LOG_ERROR, "ports: no das lane `{lane}`; --lanes takes interp, jit, exe and aot\n")
            return 1
        }
        lanes |> push(lane)
    }
    if (args.push && !args.commit) {
        to_log(LOG_ERROR, "ports: --push needs --commit\n")
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
        if (!empty(args.program) && port.name != args.program) {
            continue
        }
        if (!publish_program(args, port, lanes, repo) || !publish_top_readme(repo, args.perf)) {
            return 1
        }
        to_log(LOG_INFO, "{port.name}: published into {path_join(repo, port.name)}\n")
        if (args.commit && !commit_program(port, repo, generation_of(args, port))) {
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
