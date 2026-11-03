options gen2

module perf_tables public

require math
require strings
require daslib/algorithm
require daslib/functional
require daslib/json_boost
require daslib/md_boost
require boxes

//! The tables of a perf current, `results_linux.json` read as JSON: the results table, the
//! ratio of every lane's time to native's, the delta of every cell against a baseline capture
//! with the cells slower than the flag bar, and the markdown report holding all three.

let LANES <- ["native", "interp", "interp-copy", "interp-while", "interp-reinterpret", "jit", "exe", "aot"]
//! the lanes of the dasProfile-method capture: the composed program's own build and its conversion
let METHOD_LANES <- ["native", "interp", "jit", "exe", "aot"]
let LANE_TITLES <- {"native" => "C (clang -O3)", "interp" => "DAS interpreter", "interp-copy" => "DAS interp, copied params", "interp-while" => "DAS interp, while loops", "interp-reinterpret" => "DAS interp, reinterpreted first members", "jit" => "DAS JIT", "exe" => "DAS exe", "aot" => "DAS AOT"}
//! a delta is kept in hundredths of a percent, so exactly 10 percent never flags by rounding
let FLAG_CENTS = 1000l
//! a lane this far under native measures a different program
let SUSPECT_RATIO = 0.1lf
let MISSING = "n/a"

//! The median seconds of one cell, 0 when the capture has no such kernel or lane.
def time_of(js : JsonValue?; kernel, lane : string) : double => js?["tests"]?[kernel]?[lane]?["time"] ?? 0.0lf

//! The lanes a capture lists, in its order; `LANES` for a capture that lists none.
def lanes_of(js : JsonValue?) : array<string> {
    let listed = js?["lanes"]
    if (listed == null || !(listed is _array)) {
        return <- [for (lane in LANES); lane]
    }
    return <- [for (lane in listed as _array); lane ?? ""]
}

def kernel_names(js : JsonValue?) : array<string> {
    var names : array<string>
    let tests = js?["tests"]
    if (tests != null && tests is _object) {
        names <- [for (name in sorted([for (key in keys(tests as _object)); key])); name]
    }
    return <- names
}

def cell_text(time, spread : double) : string => "{time:.6f}s ±{int(round(spread * 100.0lf))}%"

//! Lane time over native time, 0 when either cell is missing.
def ratio_of(js : JsonValue?; kernel, lane : string) : double {
    let native = time_of(js, kernel, "native")
    let t = time_of(js, kernel, lane)
    return native > 0.0lf && t > 0.0lf ? t / native : 0.0lf
}

//! Captures from one CPU compare times; captures from two compare lane/native ratios.
def same_cpu(current, baseline : JsonValue?) : bool => (current?["cpu"] ?? "") == (baseline?["cpu"] ?? "")

def private compared_value(js : JsonValue?; kernel, lane : string; by_ratio : bool) : double {
    if (!by_ratio) {
        return time_of(js, kernel, lane)
    }
    return lane == "native" ? 0.0lf : ratio_of(js, kernel, lane)
}

//! `(new - old) / old` in hundredths of a percent; false when either capture lacks the cell.
def delta_cents(current, baseline : JsonValue?; kernel, lane : string; var cents : int64&) : bool {
    let by_ratio = !same_cpu(current, baseline)
    let old_value = compared_value(baseline, kernel, lane, by_ratio)
    let new_value = compared_value(current, kernel, lane, by_ratio)
    if (old_value <= 0.0lf || new_value <= 0.0lf) {
        return false
    }
    cents = int64(round((new_value - old_value) / old_value * 10000.0lf))
    return true
}

def percent_text(cents : int64) : string => "{double(cents) / 100.0lf:+.2f}%"

def private lane_table(lanes, names : array<string>; cell : block<(kernel, lane : string) : string>) : string {
    var headers <- ["Test"]
    var aligns <- [ColAlign.left]
    headers |> reserve(length(lanes) + 1)
    aligns |> reserve(length(lanes) + 1)
    for (lane in lanes) {
        headers |> push(LANE_TITLES?[lane] ?? lane)
        aligns |> push(ColAlign.right)
    }
    var rows : array<array<string>>
    rows |> reserve(length(names))
    for (name in names) {
        var inscope row : array<string>
        row |> reserve(length(lanes) + 1)
        row |> push(name)
        for (lane in lanes) {
            row |> push(invoke(cell, name, lane))
        }
        rows |> emplace(row)
    }
    return render_md_table(headers, aligns, rows)
}

//! The measured table, the fastest lane of each row bold, under the capture's provenance line.
def render_results(js : JsonValue?) : string {
    let lanes <- lanes_of(js)
    let grid = lane_table(lanes, kernel_names(js)) $(kernel, lane) {
        let t = time_of(js, kernel, lane)
        if (t <= 0.0lf) {
            return MISSING
        }
        var best = t
        for (other in lanes) {
            let o = time_of(js, kernel, other)
            if (o > 0.0lf) {
                best = min(best, o)
            }
        }
        let text = cell_text(t, js?["tests"]?[kernel]?[lane]?["spread"] ?? 0.0lf)
        return t == best ? md_bold(text) : text
    }
    let versions = js?["versions"]
    let head = "Captured on {js?["timestamp"] ?? ""}, {js?["platform"] ?? ""}, {capture_label(js)}; {versions?["clang"] ?? ""}, {versions?["daslang"] ?? ""}. A cell is the median of {js?["samples"] ?? 0l} samples, each its own process, ± half the sample range as a share of the median; the fastest lane per row is bold.\n\n"
    return head + grid + "\n"
}

// the non-empty texts `cell` gives per kernel of `names` and lane, row by row
def private picked_cells(lanes, names : array<string>; cell : block<(kernel, lane : string) : string>) : array<string> {
    var picked : array<string>
    for (name in names) {
        for (lane in lanes) {
            let text = invoke(cell, name, lane)
            if (!empty(text)) {
                picked |> push(text)
            }
        }
    }
    return <- picked
}

//! Every lane under the suspect bar of native, as `<kernel>/<lane> at R.RRx native`.
def suspect_cells(js : JsonValue?) : array<string> {
    return <- picked_cells(lanes_of(js), kernel_names(js)) $(name, lane) {
        let r = ratio_of(js, name, lane)
        return r > 0.0lf && r < SUSPECT_RATIO ? "{name}/{lane} at {r:.2f}x native" : ""
    }
}

//! The ratio table, then one `SUSPECT` list item per lane under the suspect bar.
def render_ratios(js : JsonValue?) : string {
    let grid = lane_table(lanes_of(js), kernel_names(js)) $(kernel, lane) {
        let r = ratio_of(js, kernel, lane)
        return r > 0.0lf ? "{r:.2f}" : MISSING
    }
    let suspects <- suspect_cells(js)
    let notes = empty(suspects) ? "" : "\n" + join([for (c in suspects); "- SUSPECT {c}: a lane this far under native measures a different program\n"], "")
    return "Lane time / native, per kernel.\n\n" + grid + "\n" + notes
}

//! Every cell slower than the baseline by more than the flag bar, as `<kernel>/<lane> +N.NN%`.
def flagged_cells(current, baseline : JsonValue?) : array<string> {
    return <- picked_cells(lanes_of(current), kernel_names(current)) $(name, lane) {
        var cents = 0l
        return delta_cents(current, baseline, name, lane, cents) && cents > FLAG_CENTS ? "{name}/{lane} {percent_text(cents)}" : ""
    }
}

//! Every cell either capture has whose delta is past its bar either way, as `<kernel>/<lane>
//! +N.NN%`, and every kernel or lane one capture has and the other lacks, as `<kernel>/<lane>
//! missing`: a rerun that does not reproduce the committed capture. A cell's bar is
//! `tolerance_cents`, or twice the baseline cell's own spread when that is wider: a cell whose
//! samples already spread that far reproduces anywhere inside it.
def drifted_cells(current, baseline : JsonValue?; tolerance_cents : int64) : array<string> {
    var names <- kernel_names(current)
    names |> push_from(kernel_names(baseline))
    names |> sort_unique()
    var lanes <- lanes_of(current)
    for (lane in lanes_of(baseline)) {
        if (!has_value(lanes, lane)) {
            lanes |> push(lane)
        }
    }
    return <- picked_cells(lanes, names) $(name, lane) {
        let have_new = time_of(current, name, lane) > 0.0lf
        let have_old = time_of(baseline, name, lane) > 0.0lf
        if (have_new != have_old) {
            return "{name}/{lane} missing"
        }
        var cents = 0l
        let spread_cents = int64(round((baseline?["tests"]?[name]?[lane]?["spread"] ?? 0.0lf) * 20000.0lf))
        return delta_cents(current, baseline, name, lane, cents) && abs(cents) > max(tolerance_cents, spread_cents) ? "{name}/{lane} {percent_text(cents)}" : ""
    }
}

//! The delta table over the kernels of either current, then its `FLAG` list or the all-clear;
//! for captures of two boxes the one line saying there is no delta.
def render_delta(current, baseline : JsonValue?; baseline_name : string) : string {
    if (!same_box(current, baseline)) {
        return "no delta: {capture_label(current)} against {capture_label(baseline)}, numbers of two boxes are not compared (ruling 27)\n"
    }
    var names <- kernel_names(current)
    names |> push_from(kernel_names(baseline))
    names |> sort_unique()
    let grid = lane_table(lanes_of(current), names) $(kernel, lane) {
        var cents = 0l
        return delta_cents(current, baseline, kernel, lane, cents) ? percent_text(cents) : MISSING
    }
    let flags <- flagged_cells(current, baseline)
    let verdict = empty(flags) ? "no lane slower than {FLAG_CENTS / 100l}%\n" : join([for (f in flags); "- FLAG {f}\n"], "")
    let cpu_note = same_cpu(current, baseline) ? "" : " The baseline ran on {capture_label(baseline)}, this capture on {capture_label(current)}: the delta compares lane/native ratios."
    return "Delta against {baseline_name}, (new - old) / old per kernel and lane.{cpu_note}\n\n" + grid + "\n\n" + verdict
}

//! The three tables as one markdown block; without a baseline the delta section says so.
def render_report(current, baseline : JsonValue?; baseline_name : string) : string {
    let delta = baseline != null ? render_delta(current, baseline, baseline_name) : "No baseline capture: no delta.\n"
    return "**Results**\n\n{render_results(current)}\n**Ratios**\n\n{render_ratios(current)}\n**Delta**\n\n{delta}"
}

//! The kernels this tree shares with borisbat/dasProfile, by our name to its test's category: the
//! method kernels (`perf/kernels/dasprofile/`), dasProfile's C++ programs in C with the same
//! parameter, so a row compares one program across the two harnesses.
let SHARED_KERNELS <- {"fib_loop" => "fibonacci loop", "fib_recursive" => "fibonacci recursive", "primes" => "primes loop"}
//! The same-named or same-themed kernels that are not the same program, never compared.
let DIFFERENT_PROGRAMS <- ["the first table's `fib_loop`, `fib_recursive` and `primes` are this tree's versions of the three (`primes` tests `i < n` in `isprime` and returns `int`, and no kernel function is `noinline`)", "`fixed_mandel` (16.16 fixed point, 96x96, 48 iterations, struct vectors by value) is not dasProfile's `mandelbrot` (double, 64x64, 255 iterations)", "`matmul`, `sieve`, `blit` and the construct kernels have no dasProfile twin; dasProfile's `n-bodies`, `spectral norm`, `sha256`, `sort`, `tree`, `queen`, `dictionary`, `exp loop`, `particles kinematics`, `string2float`, `float2string` and `interop host calls` have no kernel here"]

//! The median seconds dasProfile's capture `dp` gives `language` on test `category` of `board`
//! (`Interpreted` or `AOT or JIT`), 0 when it has none.
def dasprofile_time(dp : JsonValue?; board, category, language : string) : double {
    let entries = dp?[board]?[category]
    if (entries == null || !(entries is _array)) {
        return 0.0lf
    }
    for (e in entries as _array) {
        if ((e?["language"] ?? "") == language) {
            return e?["time"] ?? 0.0lf
        }
    }
    return 0.0lf
}

// `t` to five significant digits with its ratio to `base`, `n/a` without a time
def private timed_ratio(t, base : double) : string {
    if (t <= 0.0lf) {
        return MISSING
    }
    return base > 0.0lf ? "{t:.5g}s ({t / base:.2f}x)" : "{t:.5g}s"
}

//! The comparison of the dasProfile-method capture `method` with dasProfile's own capture `dp`
//! from the same machine, one row per shared kernel: the composed C program and dasProfile's C++,
//! dasProfile's hand-written das under the interpreter, the JIT and AOT, each over its C++, and
//! the converted kernel under the interpreter, the JIT, AOT and the exe, each over the C program;
//! then the kernels that are not the same program, named and not compared.
def render_method_comparison(method, dp : JsonValue?) : string {
    let headers <- ["Test", "C (clang -O3)", "dasProfile C++", "hand-written interp", "hand-written JIT", "hand-written AOT", "converted interp", "converted JIT", "converted AOT", "converted exe"]
    let aligns <- [for (idx in range(length(headers))); idx == 0 ? ColAlign.left : ColAlign.right]
    var rows : array<array<string>>
    for (kernel in kernel_names(method)) {
        let category = SHARED_KERNELS?[kernel] ?? ""
        if (empty(category)) {
            continue
        }
        let native = time_of(method, kernel, "native")
        let cpp = dasprofile_time(dp, "AOT or JIT", category, "C++")
        var inscope row <- [kernel, timed_ratio(native, 0.0lf), timed_ratio(cpp, 0.0lf)]
        row |> push(timed_ratio(dasprofile_time(dp, "Interpreted", category, "DAS INTERPRETER"), cpp))
        row |> push(timed_ratio(dasprofile_time(dp, "AOT or JIT", category, "DAS JIT"), cpp))
        row |> push(timed_ratio(dasprofile_time(dp, "AOT or JIT", category, "DAS AOT"), cpp))
        row |> push_from([for (lane in ["interp", "jit", "aot", "exe"]); timed_ratio(time_of(method, kernel, lane), native)])
        rows |> emplace(row)
    }
    let head = "The dasProfile method on {capture_label(method)} ({method?["timestamp"] ?? ""}; {method?["versions"]?["clang"] ?? ""}, daslang {method?["versions"]?["daslang"] ?? ""}) beside borisbat/dasProfile {dp?["dasprofile_commit"] ?? ""} run on {capture_label(dp)} ({dp?["timestamp"] ?? ""}; {dp?["toolchain"] ?? ""}). Seconds per run, median of five samples; a hand-written cell's ratio is over dasProfile's C++, a converted cell's over the C program. dasProfile's hand-written das passes its count as a literal (`fibI(6511134)`, `fibR(31)`, `primes(14000)`) where its C++ and the converted program read a `volatile` one, so a hand-written cell times a program whose count its compiler sees: the JIT unrolls that `fib_loop` and not the converted one (`perf/ARCHITECTURE.md` section 3).\n\n"
    let different = join([for (line in DIFFERENT_PROGRAMS); "- {line}: different programs, not compared\n"], "")
    return head + render_md_table(headers, aligns, rows) + "\n\n" + different
}
