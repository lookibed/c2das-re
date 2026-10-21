options gen2

module perf_tables public

require math
require strings
require daslib/algorithm
require daslib/functional
require daslib/json_boost
require daslib/md_boost

//! The tables of a perf current, `results_linux.json` read as JSON: the results table, the
//! ratio of every lane's time to native's, the delta of every cell against a baseline capture
//! with the cells slower than the flag bar, and the markdown report holding all three.

let LANES <- ["native", "interp", "interp-copy", "jit", "exe", "aot"]
let LANE_TITLES <- {"native" => "C (clang -O3)", "interp" => "DAS interpreter", "interp-copy" => "DAS interp, copied params", "jit" => "DAS JIT", "exe" => "DAS exe", "aot" => "DAS AOT"}
//! a delta is kept in hundredths of a percent, so exactly 10 percent never flags by rounding
let FLAG_CENTS = 1000l
//! a lane this far under native measures a different program
let SUSPECT_RATIO = 0.1lf
let MISSING = "n/a"

//! The median seconds of one cell, 0 when the capture has no such kernel or lane.
def time_of(js : JsonValue?; kernel, lane : string) : double => js?["tests"]?[kernel]?[lane]?["time"] ?? 0.0lf

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

def private lane_table(names : array<string>; cell : block<(kernel, lane : string) : string>) : string {
    var headers <- ["Test"]
    var aligns <- [ColAlign.left]
    headers |> reserve(length(LANES) + 1)
    aligns |> reserve(length(LANES) + 1)
    for (lane in LANES) {
        headers |> push(LANE_TITLES?[lane] ?? lane)
        aligns |> push(ColAlign.right)
    }
    var rows : array<array<string>>
    rows |> reserve(length(names))
    for (name in names) {
        var inscope row : array<string>
        row |> reserve(length(LANES) + 1)
        row |> push(name)
        for (lane in LANES) {
            row |> push(invoke(cell, name, lane))
        }
        rows |> emplace(row)
    }
    return render_md_table(headers, aligns, rows)
}

//! The measured table, the fastest lane of each row bold, under the capture's provenance line.
def render_results(js : JsonValue?) : string {
    let grid = lane_table(kernel_names(js)) $(kernel, lane) {
        let t = time_of(js, kernel, lane)
        if (t <= 0.0lf) {
            return MISSING
        }
        var best = t
        for (other in LANES) {
            let o = time_of(js, kernel, other)
            if (o > 0.0lf) {
                best = min(best, o)
            }
        }
        let text = cell_text(t, js?["tests"]?[kernel]?[lane]?["spread"] ?? 0.0lf)
        return t == best ? md_bold(text) : text
    }
    let versions = js?["versions"]
    let head = "Captured on {js?["timestamp"] ?? ""}, {js?["platform"] ?? ""}, {js?["cpu"] ?? ""}; {versions?["clang"] ?? ""}, {versions?["daslang"] ?? ""}. A cell is the median of {js?["samples"] ?? 0l} samples, each its own process, ± half the sample range as a share of the median; the fastest lane per row is bold.\n\n"
    return head + grid + "\n"
}

// the non-empty texts `cell` gives per kernel of `names` and lane, row by row
def private picked_cells(names : array<string>; cell : block<(kernel, lane : string) : string>) : array<string> {
    var picked : array<string>
    for (name in names) {
        for (lane in LANES) {
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
    return <- picked_cells(kernel_names(js)) $(name, lane) {
        let r = ratio_of(js, name, lane)
        return r > 0.0lf && r < SUSPECT_RATIO ? "{name}/{lane} at {r:.2f}x native" : ""
    }
}

//! The ratio table, then one `SUSPECT` list item per lane under the suspect bar.
def render_ratios(js : JsonValue?) : string {
    let grid = lane_table(kernel_names(js)) $(kernel, lane) {
        let r = ratio_of(js, kernel, lane)
        return r > 0.0lf ? "{r:.2f}" : MISSING
    }
    let suspects <- suspect_cells(js)
    let notes = empty(suspects) ? "" : "\n" + join([for (c in suspects); "- SUSPECT {c}: a lane this far under native measures a different program\n"], "")
    return "Lane time / native, per kernel.\n\n" + grid + "\n" + notes
}

//! Every cell slower than the baseline by more than the flag bar, as `<kernel>/<lane> +N.NN%`.
def flagged_cells(current, baseline : JsonValue?) : array<string> {
    return <- picked_cells(kernel_names(current)) $(name, lane) {
        var cents = 0l
        return delta_cents(current, baseline, name, lane, cents) && cents > FLAG_CENTS ? "{name}/{lane} {percent_text(cents)}" : ""
    }
}

//! The delta table over the kernels of either current, then its `FLAG` list or the all-clear.
def render_delta(current, baseline : JsonValue?; baseline_name : string) : string {
    var names <- kernel_names(current)
    names |> push_from(kernel_names(baseline))
    names |> sort_unique()
    let grid = lane_table(names) $(kernel, lane) {
        var cents = 0l
        return delta_cents(current, baseline, kernel, lane, cents) ? percent_text(cents) : MISSING
    }
    let flags <- flagged_cells(current, baseline)
    let verdict = empty(flags) ? "no lane slower than {FLAG_CENTS / 100l}%\n" : join([for (f in flags); "- FLAG {f}\n"], "")
    let cpu_note = same_cpu(current, baseline) ? "" : " The baseline ran on {baseline?["cpu"] ?? ""}, this capture on {current?["cpu"] ?? ""}: the delta compares lane/native ratios."
    return "Delta against {baseline_name}, (new - old) / old per kernel and lane.{cpu_note}\n\n" + grid + "\n\n" + verdict
}

//! The three tables as one markdown block; without a baseline the delta section says so.
def render_report(current, baseline : JsonValue?; baseline_name : string) : string {
    let delta = baseline != null ? render_delta(current, baseline, baseline_name) : "No baseline capture: no delta.\n"
    return "**Results**\n\n{render_results(current)}\n**Ratios**\n\n{render_ratios(current)}\n**Delta**\n\n{delta}"
}
