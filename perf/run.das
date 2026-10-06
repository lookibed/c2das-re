options gen2

require strings
require math
require daslib/strings_boost
require daslib/fio
require daslib/clargs
require daslib/json_boost
require crt
require ../converter/pipeline.das
require ../converter/tiers.das

//! The performance comparison of docs/very-detailed-plan.md section 2, measured the way
//! borisbat/dasProfile measures: every kernel under perf/kernels/<name>.c is composed with
//! the profile prologue and epilogue into one C file, built natively by the pinned clang at
//! -O2 and converted by the pipeline, and each lane runs it as its own process SAMPLES times;
//! the program itself runs the kernel as many times as fit the budget and prints the per-run
//! seconds, so startup never enters a cell. A cell is the median, ± half the range as a share
//! of it. Run from the repository root through scripts/run_perf.sh.

let KERNELS = "perf/kernels"
let WORK = "perf/work"
let RESULTS = "perf/results_linux.json"
let README = "README.md"
let README_BEGIN = "<!-- perf-table:begin -->"
let README_END = "<!-- perf-table:end -->"
let LANES <- ["native", "interp", "jit", "exe", "aot"]
let LANE_TITLES <- {"native" => "C (clang -O2)", "interp" => "DAS interpreter", "jit" => "DAS JIT", "exe" => "DAS exe", "aot" => "DAS AOT"}

[CommandLineArgs]
struct Args {
    @clarg_doc = "run only the kernels whose name contains this text"
    filter : string = ""
    @clarg_doc = "samples per lane, each its own process (default 5)"
    samples : int = 5
    @clarg_name = "table"
    @clarg_doc = "render the table from the stored results instead of measuring"
    show_table : bool
    @clarg_doc = "rewrite the perf table section of README.md after measuring"
    readme : bool
    @clarg_short = "?"
    @clarg_name = "show-help"
    @clarg_doc = "show this help and exit"
    show_help : bool
}

struct Cell {
    time : double
    spread : double
    count : int64
    samples : array<double>
}

def fread_text(path : string) : string {
    var text = ""
    fopen(path, "rb") $(f) {
        if (f != null) {
            text = fread(f)
        }
    }
    return text
}

def write_text(path : string; text : string) {
    fopen(path, "wb") $(f) {
        if (f != null) {
            fwrite(f, text)
        }
    }
}

def first_line(text : string) : string {
    let nl = find(text, "\n")
    return nl < 0 ? text : slice(text, 0, nl)
}

def clang_bin : string {
    return has_env_variable("PATH_TO_LIBCLANG") ? get_env_variable("PATH_TO_LIBCLANG") + "/bin/clang" : "clang"
}

def captured(args : array<string>) : string {
    var out : string
    run_and_capture(args, out, 600.0)
    return out
}

//! The profile protocol around a kernel: dastest's budget loop in C, timed by the CRT clock
//! the kernel's converted form also reaches, one line `<seconds per run> <runs>` at the end.
def composed_source(kernel : string) : string {
    let prologue = "int printf(const char *, ...);\nlong clock(void);\n#define C2DAS_CLOCKS_PER_SEC {crt::CLOCKS_PER_SEC}L\n#define C2DAS_BUDGET (C2DAS_CLOCKS_PER_SEC / 2)\n\n"
    let epilogue = "\nint main(void) \{\n    long reps = 1;\n    long total = 0;\n    for (;;) \{\n        long start = clock();\n        for (long i = 0; i < reps; i++) kernel_run();\n        total = clock() - start;\n        if (total >= C2DAS_BUDGET || reps >= 1000000000L) break;\n        long next = total <= 0 ? 100 * reps : (long) ((double) reps * (double) C2DAS_BUDGET / (double) total * 1.2);\n        if (next > 100 * reps) next = 100 * reps;\n        if (next < reps + 1) next = reps + 1;\n        reps = next;\n    \}\n    if (!kernel_check()) \{\n        printf(\"FAIL\\n\");\n        return 1;\n    \}\n    printf(\"%.9f %ld\\n\", (double) total / (double) C2DAS_CLOCKS_PER_SEC / (double) reps, reps);\n    return 0;\n\}\n"
    return prologue + kernel + epilogue
}

// the kernel's line is the last one: a tier may log before the program runs
def last_line(text : string) : string {
    let lines <- [for (l in split(text, "\n")); strip(l); where !empty(strip(l))]
    return empty(lines) ? "" : lines[length(lines) - 1]
}

def parse_sample(out : string; var seconds : double&; var reps : int64&) : bool {
    let fields <- split(last_line(out), " ")
    if (length(fields) != 2) {
        return false
    }
    let digits = unsafe(reinterpret<uint8?>(fields[0]))
    seconds = unsafe(crt::strtod(digits, null))
    reps = to_int64(fields[1], false)
    return seconds > 0.0lf
}

def median_of(values : array<double>) : double {
    var sorted := values
    sorted |> sort()
    let n = length(sorted)
    return n == 0 ? 0.0lf : (n & 1) == 1 ? sorted[n / 2] : (sorted[n / 2 - 1] + sorted[n / 2]) * 0.5lf
}

def cell_of(samples : array<double>; count : int64) : Cell {
    var c = Cell(time = median_of(samples), count = count)
    if (!empty(samples)) {
        var lo = samples[0]
        var hi = samples[0]
        for (s in samples) {
            lo = min(lo, s)
            hi = max(hi, s)
        }
        c.spread = c.time > 0.0lf ? (hi - lo) * 0.5lf / c.time : 0.0lf
    }
    c.samples := samples
    return <- c
}

//! `samples` launches of `argv`, each a process; the kernel's own line gives the per-run time.
def measure(argv : array<string>; samples : int; var error : string&) : Cell {
    var times : array<double>
    var count = 0l
    for (_s in range(samples)) {
        var out : string
        let rc = run_and_capture(argv, out, 600.0)
        var seconds = 0.0lf
        if (rc != 0 || !parse_sample(out, seconds, count)) {
            error = "exited {rc}: {first_line(out)}"
            break
        }
        times |> push(seconds)
    }
    return <- cell_of(times, count)
}

def module_dirs : array<string> {
    return <- ["c_runtime", "dasCRuntime"]
}

//! Every lane of one kernel: the native build and the four converter tiers.
def run_kernel(name : string; samples : int; var errors : array<string>) : table<string; Cell> {
    var cells : table<string; Cell>
    let work = path_join(WORK, name)
    mkdir_rec(work)
    let c_path = path_join(work, "{name}.c")
    write_text(c_path, composed_source(fread_text("{KERNELS}/{name}.c")))
    let native_bin = path_join(work, "{name}_native")
    var build_out : string
    if (run_and_capture([clang_bin(), "-O2", "-w", "-funsigned-char", "-o", native_bin, c_path], build_out, 600.0) != 0) {
        errors |> push("{name}/native: {first_line(build_out)}")
    } else {
        var err : string
        cells["native"] <- measure([native_bin], samples, err)
        if (!empty(err)) {
            errors |> push("{name}/native: {err}")
        }
    }
    let res <- convert(c_path, work, "linux")
    if (!res.ok) {
        errors |> push("{name}/convert: {first_line(res.error)}")
        return <- cells
    }
    let daslang = get_das_root() + "/bin/daslang"
    var loader : array<string>
    loader |> reserve(2 * length(module_dirs()))
    for (dir in module_dirs()) {
        loader |> push("-load_module")
        loader |> push(dir)
    }
    var err : string
    cells["interp"] <- measure(with_binary_first(daslang, loader, "", res.das_path), samples, err)
    if (!empty(err)) {
        errors |> push("{name}/interp: {err}")
    }
    err = ""
    cells["jit"] <- measure(with_binary_first(daslang, loader, "-jit", res.das_path), samples, err)
    if (!empty(err)) {
        errors |> push("{name}/jit: {err}")
    }
    var tier_out : string
    if (run_tier(res.das_path, "exe", work, tier_out, module_dirs()) >= 0) {
        let exe = path_join(work, "{name}_exe")
        let built = fexist(exe + ".exe") ? exe + ".exe" : exe
        err = ""
        cells["exe"] <- measure([built], samples, err)
        if (!empty(err)) {
            errors |> push("{name}/exe: {err}")
        }
    } else {
        errors |> push("{name}/exe: {first_line(tier_out)}")
    }
    tier_out = ""
    if (run_tier(res.das_path, "aot", work, tier_out, module_dirs()) >= 0) {
        let bin = path_join(path_join(work, "ctx"), "{name}_aot")
        err = ""
        cells["aot"] <- measure([bin], samples, err)
        if (!empty(err)) {
            errors |> push("{name}/aot: {err}")
        }
    } else {
        errors |> push("{name}/aot: {first_line(tier_out)}")
    }
    return <- cells
}

def with_binary_first(daslang : string; loader : array<string>; flag : string; script : string) : array<string> {
    var argv <- [daslang]
    let tail <- empty(flag) ? [script] : [flag, script]
    argv |> push_from(loader, tail)
    return <- argv
}

def cpu_name : string {
    for (line in split(fread_text("/proc/cpuinfo"), "\n")) {
        if (line |> starts_with("model name")) {
            let colon = find(line, ":")
            return colon < 0 ? line : strip(slice(line, colon + 1))
        }
    }
    return "unknown cpu"
}

// six decimals through the CRT, the way the kernels print their own line
def seconds_text(v : double) : string {
    var buf : uint8[64]
    var out = unsafe(addr(buf[0]))
    let spec = unsafe(reinterpret<uint8?>("%.6f"))
    let n = unsafe(crt::snprintf_double(out, uint64(typeinfo dim(buf)), spec, v))
    let rendered = unsafe(reinterpret<string>(out))
    return slice(rendered, 0, n)
}

def fmt_cell(c : Cell) : string {
    return "{seconds_text(c.time)}s ±{int(math::round(c.spread * 100.0lf))}%"
}

def lane_text(cells : table<string; Cell>; lane : string) : string {
    var text = "-"
    cells |> get(lane) $(c) {
        text = fmt_cell(c)
    }
    return text
}

def render_table(js : JsonValue?) : string {
    var rows : array<string>
    rows |> push("| Test | " + join([for (lane in LANES); LANE_TITLES?[lane] ?? lane], " | ") + " |")
    rows |> push("| --- | " + join([for (_lane in LANES); "---:"], " | ") + " |")
    let tests = js?["tests"]
    if (tests != null && tests is _object) {
        var names <- [for (name in keys(tests as _object)); name]
        names |> sort()
        for (name in names) {
            var cells : array<string>
            var best = 0.0lf
            for (lane in LANES) {
                let t = tests?[name]?[lane]?["time"] ?? 0.0lf
                if (t > 0.0lf && (best == 0.0lf || t < best)) {
                    best = t
                }
            }
            for (lane in LANES) {
                let t = tests?[name]?[lane]?["time"] ?? 0.0lf
                if (t <= 0.0lf) {
                    cells |> push("-")
                    continue
                }
                let spread = tests?[name]?[lane]?["spread"] ?? 0.0lf
                let text = "{seconds_text(t)}s ±{int(math::round(spread * 100.0lf))}%"
                cells |> push(t == best ? "**{text}**" : text)
            }
            rows |> push("| {name} | " + join(cells, " | ") + " |")
        }
    }
    let platform = js?["platform"] ?? ""
    let cpu = js?["cpu"] ?? ""
    let stamp = js?["timestamp"] ?? ""
    let versions = js?["versions"]
    let head = "Captured on {stamp}, {platform}, {cpu}; {versions?["clang"] ?? ""}, {versions?["daslang"] ?? ""}. A cell is the median of {js?["samples"] ?? 0l} samples, each its own process, ± half the sample range as a share of the median; the fastest lane per row is bold.\n\n"
    return head + join(rows, "\n") + "\n"
}

def update_readme(rendered : string) : bool {
    let text = fread_text(README)
    let b = find(text, README_BEGIN)
    let e = find(text, README_END)
    if (b < 0 || e < 0 || e < b) {
        return false
    }
    write_text(README, slice(text, 0, b + length(README_BEGIN)) + "\n" + rendered + slice(text, e))
    return true
}

[export]
def main : int {
    var args = Args()
    let parsed = parse_args_with_help(args, "run_perf")
    if (parsed >= 0) {
        return parsed
    }
    if (args.show_table) {
        var error : string
        let js = read_json(fread_text(RESULTS), error)
        if (js == null) {
            to_log(LOG_ERROR, "{RESULTS}: {error}\n")
            return 1
        }
        print(render_table(js))
        return 0
    }
    var names : array<string>
    names |> reserve(32)
    dir(KERNELS) $(file) {
        if (file |> ends_with(".c") && (empty(args.filter) || find(file, args.filter) >= 0)) {
            names |> push(slice(file, 0, length(file) - 2))
        }
    }
    names |> sort()
    var errors : array<string>
    var tests : table<string; JsonValue?>
    for (name in names) {
        let cells <- run_kernel(name, args.samples, errors)
        var row <- {for (lane, cell in keys(cells), values(cells)); lane => JV((time = cell.time, spread = cell.spread, count = cell.count, samples = JV(cell.samples)))}
        tests[name] = JV(row)
        to_log(LOG_INFO, "{name}: " + join([for (lane in LANES); "{lane} {lane_text(cells, lane)}"], ", ") + "\n")
    }
    var root <- {
        "cpu" => JV(cpu_name()),
        "platform" => JV("{get_platform_name()} {strip(captured(["uname", "-m"]))}"),
        "timestamp" => JV(strip(captured(["date", "-u", "+%Y-%m-%d %H:%M UTC"]))),
        "samples" => JV(args.samples),
        "versions" => JV({"clang" => JV(first_line(captured([clang_bin(), "--version"]))), "daslang" => JV(first_line(captured([get_das_root() + "/bin/daslang", "-version"])))}),
        "lanes" => JV(LANES),
        "tests" => JV(tests)
    }
    let js = JV(root)
    write_text(RESULTS, write_json(js) + "\n")
    let rendered = render_table(js)
    print(rendered)
    if (args.readme && !update_readme(rendered)) {
        to_log(LOG_ERROR, "{README} has no perf-table markers\n")
    }
    for (e in errors) {
        to_log(LOG_ERROR, "{e}\n")
    }
    return empty(errors) ? 0 : 1
}
