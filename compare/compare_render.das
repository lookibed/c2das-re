options gen2

module compare_render public

require math
require strings
require daslib/strings_boost
require daslib/json_boost
require ../ports/ports_render.das
require ../metrics/readability_file.das

//! The head-to-head as markdown, rendered from the capture `compare/results_linux.json` alone: the
//! suites, the perf ratios with their geometric means, the readability counters and sizes, the
//! functions side by side, Lua and Doom, and the list of where the Rust translator is ahead
//! (`compare/ARCHITECTURE_REPORT.md`). It reads and writes no file.

//! every status a case ends in, the keys of a capture's counts
let STATUSES <- ["pass", "refused", "compile", "timeout", "exit", "output", "native", "crash"]

//! the key of the quality totals over every group, the last row of its tables
let ALL_GROUPS = "all"

//! the counters `rust_ahead` does not rank: `c_function` counts an annotation only our output
//! writes, so the Rust side's 0 says nothing of its code
let UNRANKED_COUNTERS <- ["c_function"]

//! the markers of the generated block in a README
let COMPARE_BEGIN = "<!-- compare:begin -->"
let COMPARE_END = "<!-- compare:end -->"

//! the longest reason an error line shows
let REASON_WIDTH = 160

// the keys of object `js`, sorted; none when it is no object
def private keys_of(js : JsonValue const?) : array<string> {
    var names : array<string>
    if (js != null && js.value is _object) {
        for (name in keys(js.value as _object)) {
            names |> push(name)
        }
    }
    names |> sort()
    return <- names
}

// the strings of array `js`; none when it is no array
def private strings_of(js : JsonValue const?) : array<string> {
    if (js == null || !(js.value is _array)) {
        return <- array<string>()
    }
    return <- [for (item in js.value as _array); item ?? ""]
}

// whether `js` is missing: null, or the null value a `?[]` read of a missing key returns
def private absent(js : JsonValue const?) : bool => js == null || js.value is _null

def private clip(text : string) : string => length(text) > REASON_WIDTH ? slice(text, 0, REASON_WIDTH - 3) + "..." : text

def private ratio_cell(r : double) : string => "{r:.2f}"

//! how much higher the other side's value must be for the lower side to be ahead: 5%
let AHEAD_MARGIN = 1.05lf

//! Whether `lower` is ahead of `higher`: `higher` exceeds it by more than `AHEAD_MARGIN`.
def ahead_by_margin(lower, higher : double) : bool => higher > lower * AHEAD_MARGIN

//! Whether the cell with ratio `lower` is ahead of the one with `higher`: by the margin, and by
//! more than either cell's spread, a share of its median.
def cell_ahead(lower, higher, lower_spread, higher_spread : double) : bool => ahead_by_margin(lower, higher) && higher / lower - 1.0lf > max(lower_spread, higher_spread)

//! The suites table: per suite the ids run, our ratchet's pass count, the Rust passes over the
//! same ids and by our tag, then each Rust status counted; a total row under two or more suites.
def suites_table(results : JsonValue const?) : string {
    let suites = results?["suites"]
    let names <- keys_of(suites)
    if (empty(names)) {
        return "No suite is captured yet.\n"
    }
    var headers <- ["Suite", "ids", "ours pass (ratchet)", "Rust pass", "Rust pass of ours", "of our skips", "of unlisted"]
    let failures <- [for (s in STATUSES); s; where s != "pass"]
    headers |> push_from([for (s in failures); "Rust {s}"])
    let fields <- ["ids", "ours_pass", "rust:pass", "rust_pass_of_ours", "rust_pass_of_skipped", "rust_pass_of_unlisted"]
    var all_fields <- clone_to_move(fields)
    all_fields |> push_from([for (s in failures); "rust:{s}"])
    var totals : array<int>
    totals |> resize(length(all_fields))
    var rows : array<array<string>>
    rows |> reserve(length(names) + 1)
    for (name in names) {
        let entry = suites?[name]
        var inscope row <- [name]
        row |> reserve(1 + length(all_fields))
        for (field, idx in all_fields, count()) {
            let n = field |> starts_with("rust:") ? entry?["rust"]?[slice(field, 5)] ?? 0 : entry?[field] ?? 0
            totals[idx] += n
            row |> push("{n}")
        }
        rows |> emplace(row)
    }
    if (length(names) > 1) {
        var inscope total_row <- ["total"]
        total_row |> push_from([for (n in totals); "{n}"])
        rows |> emplace(total_row)
    }
    return table_of(headers, rows, 1)
}

//! A lane's error line in short form: `differs` for a result other than native's, `timeout` past
//! a limit, `compile` for a build that left no binary, `exit` for a run exiting non-zero,
//! `convert` for our conversion, else `error`.
def error_word(error : string) : string {
    if (error |> contains("differs from the native")) {
        return "differs"
    }
    if (error |> contains("longer than")) {
        return "timeout"
    }
    if (error |> starts_with("the build")) {
        return "compile"
    }
    if (error |> starts_with("exited ")) {
        return "exit"
    }
    if (error |> starts_with("convert")) {
        return "convert"
    }
    return "error"
}

//! The ratio of `cell`'s time to `native`, 0 when either does not stand.
def cell_ratio(cell, native : JsonValue const?) : double {
    let t = cell?["time"] ?? 0.0lf
    let n = native?["time"] ?? 0.0lf
    return !key_exists(cell, "error") && t > 0.0lf && n > 0.0lf ? t / n : 0.0lf
}

// the das lanes of the perf section, its `lanes` less `native`
def private das_lanes(perf : JsonValue const?) : array<string> => <- [for (lane in strings_of(perf?["lanes"])); lane; where lane != "native"]

// the Rust side's cell of `lane` in kernel `entry`, null for a refused translation
def private rust_cell(entry : JsonValue const?; lane : string) : JsonValue const? => entry?["rust"]?["lanes"]?[lane]

// the text of one side's cell: its ratio to native, `refused` for a refused Rust translation, the
// error's short form, else `n/a`
def private side_text(entry, cell : JsonValue const?; refused : bool) : string {
    if (refused) {
        return "refused"
    }
    if (absent(cell)) {
        return "n/a"
    }
    let error = cell?["error"] ?? ""
    return empty(error) ? ratio_cell(cell_ratio(cell, entry?["native"])) : error_word(error)
}

def private is_refused(entry : JsonValue const?) : bool => (entry?["rust"]?["status"] ?? "") == "refused"

//! The perf table: per kernel the native seconds, then for each das lane our ratio to native and
//! the Rust side's, an error cell in short form; then the geometric mean row of the capture.
def perf_table(results : JsonValue const?) : string {
    let perf = results?["perf"]
    let kernels = perf?["kernels"]
    let names <- keys_of(kernels)
    if (empty(names)) {
        return "No kernel is timed yet.\n"
    }
    let lanes <- das_lanes(perf)
    var headers <- ["Kernel", "native (s)"]
    for (lane in lanes) {
        headers |> push_from(["ours {lane_title(lane)}", "Rust {lane_title(lane)}"])
    }
    var rows : array<array<string>>
    rows |> reserve(length(names) + 1)
    for (name in names) {
        let entry = kernels?[name]
        let native = entry?["native"]
        var inscope row <- [name, key_exists(native, "error") ? error_word(native?["error"] ?? "") : "{native?["time"] ?? 0.0lf:.6f}"]
        for (lane in lanes) {
            row |> push_from([side_text(entry, entry?["ours"]?[lane], false), side_text(entry, rust_cell(entry, lane), is_refused(entry))])
        }
        rows |> emplace(row)
    }
    var inscope mean_row <- ["geomean (kernels)", ""]
    for (lane in lanes) {
        let g = perf?["geomean"]?[lane]
        let n = g?["kernels"] ?? 0
        mean_row |> push_from(n == 0 ? ["n/a", "n/a"] : ["{ratio_cell(g?["ours"] ?? 0.0lf)} ({n})", "{ratio_cell(g?["rust"] ?? 0.0lf)} ({n})"])
    }
    rows |> emplace(mean_row)
    return table_of(headers, rows, 1)
}

//! One line per error cell of the perf section: the kernel, the side, the lane and the reason.
def perf_errors(results : JsonValue const?) : array<string> {
    var lines : array<string>
    let kernels = results?["perf"]?["kernels"]
    for (name in keys_of(kernels)) {
        let entry = kernels?[name]
        if (is_refused(entry)) {
            lines |> push("- {name}, Rust: refused: {clip(entry?["rust"]?["error"] ?? "")}")
        }
        for (side in ["ours", "rust"]) {
            let cells = side == "ours" ? entry?["ours"] : entry?["rust"]?["lanes"]
            for (lane in keys_of(cells)) {
                let error = cells?[lane]?["error"] ?? ""
                if (!empty(error)) {
                    lines |> push("- {name}, {side == "ours" ? "ours" : "Rust"} {lane_title(lane)}: {clip(error)}")
                }
            }
        }
    }
    return <- lines
}

// the quality groups, sorted, `all` last
def private groups_of(totals : JsonValue const?) : array<string> {
    var groups <- [for (g in keys_of(totals)); g; where g != ALL_GROUPS]
    if (!absent(totals?[ALL_GROUPS])) {
        groups |> push(ALL_GROUPS)
    }
    return <- groups
}

//! The size table: per group and over all, the keys counted, both sides' files and lines, the
//! Rust runtime's lines, the Rust lines without it, and both line ratios.
def size_table(results : JsonValue const?) : string {
    let totals = results?["quality"]?["totals"]
    let groups <- groups_of(totals)
    if (empty(groups)) {
        return "No quality section is captured yet.\n"
    }
    let headers <- ["Group", "keys counted", "files ours", "files Rust", "lines ours", "lines Rust", "Rust runtime", "Rust without runtime", "Rust / ours", "without runtime / ours"]
    var rows : array<array<string>>
    rows |> reserve(length(groups))
    for (g in groups) {
        let gt = totals?[g]
        let rust_lines = gt?["rust"]?["lines"] ?? 0
        let runtime = gt?["rust"]?["runtime_lines"] ?? 0
        var inscope row <- [g, "{gt?["counted"] ?? 0} of {gt?["keys"] ?? 0}", "{gt?["ours"]?["files"] ?? 0}", "{gt?["rust"]?["files"] ?? 0}",
                      "{gt?["ours"]?["lines"] ?? 0}", "{rust_lines}", "{runtime}", "{rust_lines - runtime}",
                      ratio_cell(gt?["line_ratio"] ?? 0.0lf), ratio_cell(gt?["program_line_ratio"] ?? 0.0lf)]
        rows |> emplace(row)
    }
    return table_of(headers, rows, 1)
}

//! The counters table: each readability counter's total over all keys, ours and Rust's.
def counters_table(results : JsonValue const?) : string {
    let all = results?["quality"]?["totals"]?[ALL_GROUPS]
    if (absent(all)) {
        return "No quality section is captured yet.\n"
    }
    let rows <- [for (m in METRICS); [m, "{all?["ours"]?[m] ?? 0}", "{all?["rust"]?[m] ?? 0}"]]
    return table_of(["Counter (all keys)", "ours", "Rust"], rows, 1)
}

//! One line per group with keys left out of the totals: the side and status of each count.
def excluded_lines(results : JsonValue const?) : array<string> {
    var lines : array<string>
    let totals = results?["quality"]?["totals"]
    for (g in groups_of(totals)) {
        let excluded = totals?[g]?["excluded"]
        var inscope reasons <- keys_of(excluded)
        if (!empty(reasons)) {
            lines |> push("- {g}: " + join([for (r in reasons); "{r} {excluded?[r] ?? 0}"], ", "))
        }
    }
    return <- lines
}

//! The functions side by side: per entry a heading naming the key and the C function, then our
//! text and the Rust side's as fenced `das` blocks, a side without the function said so.
def side_by_side(results : JsonValue const?) : string => functions_text(results?["quality"]?["functions"])

//! The functions of the array `functions`, each `{key, name, ours, rust}`, side by side.
def functions_text(functions : JsonValue const?) : string {
    if (absent(functions) || !(functions.value is _array) || empty(functions.value as _array)) {
        return "No function is sampled yet.\n"
    }
    return build_string() $(var w) {
        for (f in functions.value as _array) {
            w |> write("#### `{f?["key"] ?? ""}`: `{f?["name"] ?? ""}`\n\n")
            for (side in ["ours", "rust"]) {
                let text = f?[side] ?? ""
                let title = side == "ours" ? "Ours" : "Rust"
                w |> write(empty(text) ? "{title}: not found in this side's module.\n\n" : "{title}:\n\n```das\n{text}\n```\n\n")
            }
        }
    }
}

// the cause of a translation error: the text after `cause=` when it has one
def private cause_of(error : string) : string {
    let at = find(error, "cause=")
    return at < 0 ? clip(error) : clip(slice(error, at + length("cause=")))
}

//! Lua and Doom: the Rust translation's status with its cause, the C library functions it lowers
//! in no mode, where our Lua numbers are, and Doom's status.
def lua_text(results : JsonValue const?) : string {
    let lua = results?["lua"]
    let doom = results?["doom"]
    return build_string() $(var w) {
        if (absent(lua)) {
            w |> write("Lua: not run yet.\n")
        } else {
            let status = lua?["status"] ?? ""
            let program = lua?["program"] ?? ""
            if (status == "refused") {
                w |> write("Lua: the Rust translator refuses `{program}` ({lua?["units"] ?? 0} units, `--libc std`): `{cause_of(lua?["error"] ?? "")}`, ")
                w |> write("so the Rust side has no Lua speed or output to compare. ")
            } else {
                w |> write("Lua: the Rust translator writes `{program}` ({lua?["units"] ?? 0} units) as {lua?["files"] ?? 0} files; speed: {lua?["speed"] ?? ""}. ")
            }
            let gap <- strings_of(lua?["gap"])
            let gap_error = lua?["gap_error"] ?? ""
            if (!empty(gap_error)) {
                w |> write("The gap was not computed: {clip(gap_error)}. ")
            } else {
                w |> write("The C library functions it calls that the Rust translator lowers in no mode ({length(gap)}): ")
                w |> write(empty(gap) ? "none. " : join([for (name in gap); "`{name}`"], ", ") + ". ")
            }
            w |> write("Our Lua numbers are in the ports repository (lookibed/c2das-ports); whether to write host modules for the gap waits on a ruling (c2das-re's `docs/rulings-pending.md`, P8.1).\n")
        }
        w |> write(absent(doom) ? "\nDoom: not run yet.\n" : "\nDoom: {doom?["status"] ?? ""} ({doom?["reason"] ?? ""}).\n")
    }
}

//! Where the Rust translator is ahead, one fact a line: a suite it passes more ids of than our
//! ratchet, a perf cell or geometric mean whose ratio ours exceeds by `AHEAD_MARGIN` (a cell also by
//! more than both cells' spreads) or where ours has no cell, a readability counter (but those of
//! `UNRANKED_COUNTERS`) or the line total without the Rust runtime that ours exceeds by `AHEAD_MARGIN`.
def rust_ahead(results : JsonValue const?) : array<string> {
    var lines : array<string>
    let suites = results?["suites"]
    for (name in keys_of(suites)) {
        let entry = suites?[name]
        let rust = entry?["rust"]?["pass"] ?? 0
        let ours = entry?["ours_pass"] ?? 0
        if (rust > ours) {
            lines |> push("- {name}: Rust passes {rust} of {entry?["ids"] ?? 0} ids, our ratchet {ours}; of the Rust passes {entry?["rust_pass_of_skipped"] ?? 0} are ids we skip and {entry?["rust_pass_of_unlisted"] ?? 0} ids our ratchet does not list.")
        }
    }
    let perf = results?["perf"]
    let lanes <- das_lanes(perf)
    let kernels = perf?["kernels"]
    for (name in keys_of(kernels)) {
        let entry = kernels?[name]
        for (lane in lanes) {
            let rust_cell_of = rust_cell(entry, lane)
            let rust = cell_ratio(rust_cell_of, entry?["native"])
            if (rust == 0.0lf) {
                continue
            }
            let ours_cell = entry?["ours"]?[lane]
            let ours = cell_ratio(ours_cell, entry?["native"])
            if (ours == 0.0lf) {
                lines |> push("- {name}, {lane_title(lane)}: Rust {ratio_cell(rust)}x native, ours has no cell ({error_word(ours_cell?["error"] ?? "")}).")
            } elif (cell_ahead(rust, ours, rust_cell_of?["spread"] ?? 0.0lf, ours_cell?["spread"] ?? 0.0lf)) {
                lines |> push("- {name}, {lane_title(lane)}: Rust {ratio_cell(rust)}x native, ours {ratio_cell(ours)}x.")
            }
        }
    }
    for (lane in lanes) {
        let g = perf?["geomean"]?[lane]
        let rust = g?["rust"] ?? 0.0lf
        let ours = g?["ours"] ?? 0.0lf
        if ((g?["kernels"] ?? 0) > 0 && ahead_by_margin(rust, ours)) {
            lines |> push("- geomean, {lane_title(lane)}: Rust {ratio_cell(rust)}x native, ours {ratio_cell(ours)}x over {g?["kernels"] ?? 0} kernels.")
        }
    }
    for (name in keys_of(results?["projects"])) {
        let entry = results?["projects"]?[name]
        var inscope ahead <- [for (lane in strings_of(entry?["lanes"])); lane_title(lane); where(entry?["rust"]?["lanes"]?[lane]?["status"] ?? "") == "pass" && (entry?["ours"]?["lanes"]?[lane]?["status"] ?? "") != "pass"]
        if (!empty(ahead)) {
            lines |> push("- project {name}: Rust passes {join(ahead, ", ")}, ours does not.")
        }
    }
    let all = results?["quality"]?["totals"]?[ALL_GROUPS]
    if (!absent(all)) {
        for (m in METRICS) {
            if (has_value(UNRANKED_COUNTERS, m)) {
                continue
            }
            let rust = all?["rust"]?[m] ?? 0
            let ours = all?["ours"]?[m] ?? 0
            if (ahead_by_margin(double(rust), double(ours))) {
                lines |> push("- counter `{m}`: Rust {rust}, ours {ours} over all keys.")
            }
        }
        let ours_lines = all?["ours"]?["lines"] ?? 0
        let rust_program = (all?["rust"]?["lines"] ?? 0) - (all?["rust"]?["runtime_lines"] ?? 0)
        if (ahead_by_margin(double(rust_program), double(ours_lines))) {
            lines |> push("- lines without the Rust runtime: Rust {rust_program}, ours {ours_lines}.")
        }
    }
    return <- lines
}

// the lanes of the capture's first project, sorted by name
def private project_lanes(results : JsonValue const?) : array<string> {
    let names <- keys_of(results?["projects"])
    return <- empty(names) ? array<string>() : strings_of(results?["projects"]?[names[0]]?["lanes"])
}

// the title of a side
def private side_title(side : string) : string => side == "ours" ? "Ours" : "Rust"

//! The real projects table: per project and side the native build's verdict and each lane's.
[arch(at="ARCHITECTURE_PROJECTS.md#rendering")]
def projects_table(results : JsonValue const?) : string {
    let names <- keys_of(results?["projects"])
    let lanes <- project_lanes(results)
    if (empty(names)) {
        return "No project is captured yet.\n"
    }
    var headers <- ["Project", "Side", "Native"]
    headers |> push_from([for (lane in lanes); lane_title(lane)])
    var rows : array<array<string>>
    rows |> reserve(2 * length(names))
    for (name in names) {
        let entry = results?["projects"]?[name]
        for (side in ["ours", "rust"]) {
            var inscope row <- [name, side_title(side), entry?["native"]?["status"] ?? ""]
            row |> push_from([for (lane in lanes); entry?[side]?["lanes"]?[lane]?["status"] ?? "n/a"])
            rows |> emplace(row)
        }
    }
    return table_of(headers, rows, 3)
}

//! The code table: per project and side its status, files, non-blank lines, the Rust runtime's
//! lines and each readability counter, each `-` for a side that was not measured.
[arch(at="ARCHITECTURE_PROJECTS.md#rendering")]
def project_code_table(results : JsonValue const?) : string {
    let names <- keys_of(results?["projects"])
    let lanes <- project_lanes(results)
    if (empty(names)) {
        return ""
    }
    var headers <- ["Project", "Side", "Code", "Files", "Lines", "Runtime lines"]
    headers |> push_from(METRICS)
    var rows : array<array<string>>
    rows |> reserve(2 * length(names))
    for (name in names) {
        for (side in ["ours", "rust"]) {
            let code = results?["projects"]?[name]?["code"]?[side]
            let measured = (code?["status"] ?? "") == "ok"
            var inscope row <- [name, side_title(side), code?["status"] ?? ""]
            row |> push_from([for (key in ["files", "lines", "runtime_lines"]); measured ? "{code?[key] ?? 0}" : "-"], [for (m in METRICS); measured ? "{code?["counts"]?[m] ?? 0}" : "-"])
            rows |> emplace(row)
        }
    }
    return table_of(headers, rows, 3)
}

//! A bench cell's text: the decode time over the native one, `n/a` without a cell, else the
//! error's first word: the verdict of a lane that does not pass, `refused` for a side with no
//! bench module, the run's verdict.
[arch(at="ARCHITECTURE_PROJECTS.md#rendering")]
def bench_text_of(cell, native : JsonValue const?) : string {
    if (absent(cell)) {
        return "n/a"
    }
    let error = cell?["error"] ?? ""
    if (empty(error)) {
        let r = cell_ratio(cell?["decode"], native?["decode"])
        return r > 0.0lf ? ratio_cell(r) : "n/a"
    }
    let lane_fails = "the lane does not pass: "
    if (error |> starts_with(lane_fails)) {
        return slice(error, length(lane_fails))
    }
    let colon = find(error, ":")
    return error |> starts_with("bench: ") ? "refused" : colon < 0 ? error : slice(error, 0, colon)
}

//! A compiler's version line without the source it was built from: the text before ` (`.
def compiler_name(line : string) : string {
    let at = find(line, " (")
    return at < 0 ? line : slice(line, 0, at)
}

//! The bench table: per project and side the native compiler's version line, the native build's
//! decode seconds and each lane's decode time over it.
[arch(at="ARCHITECTURE_PROJECTS.md#rendering")]
def project_speed_table(results : JsonValue const?) : string {
    let names <- keys_of(results?["projects"])
    let lanes <- project_lanes(results)
    if (empty(names)) {
        return ""
    }
    var headers <- ["Project", "Side", "Native compiler", "Native s"]
    headers |> push_from([for (lane in lanes); lane_title(lane)])
    var rows : array<array<string>>
    rows |> reserve(2 * length(names))
    for (name in names) {
        let speed = results?["projects"]?[name]?["speed"]
        let native = speed?["native"]
        let native_time = native?["decode"]?["time"] ?? 0.0lf
        for (side in ["ours", "rust"]) {
            var inscope row <- [name, side_title(side), compiler_name(results?["projects"]?[name]?["native_compiler"] ?? ""), native_time > 0.0lf ? "{native_time:.6f}" : bench_text_of(native, null)]
            row |> push_from([for (lane in lanes); bench_text_of(speed?[side]?[lane], native)])
            rows |> emplace(row)
        }
    }
    return table_of(headers, rows, 3)
}

//! One line per side of each project for every reason its lanes give, the lanes sharing it named
//! together, and one for a native build that does not pass.
[arch(at="ARCHITECTURE_PROJECTS.md#rendering")]
def project_reasons(results : JsonValue const?) : array<string> {
    var lines : array<string>
    let names <- keys_of(results?["projects"])
    let lanes <- project_lanes(results)
    for (name in names) {
        let entry = results?["projects"]?[name]
        if ((entry?["native"]?["status"] ?? "") != "pass") {
            lines |> push("- {name}, native: {clip(entry?["native"]?["reason"] ?? "")}")
        }
        for (side in ["ours", "rust"]) {
            var inscope order : array<string>
            var inscope by_reason : table<string; array<string>>
            for (lane in lanes) {
                let v = entry?[side]?["lanes"]?[lane]
                let status = v?["status"] ?? ""
                if (status != "pass") {
                    let reason = "{status}: {v?["reason"] ?? ""}"
                    if (!key_exists(by_reason, reason)) {
                        order |> push(reason)
                    }
                    by_reason[reason] |> push(lane_title(lane))
                }
            }
            lines |> push_from([for (reason in order); "- {name}, {side_title(side)}, {join(by_reason?[reason] ?? array<string>(), " ")}: {clip(reason)}"])
        }
    }
    return <- lines
}

//! The real projects: the verdicts, the bench, the reasons and the functions side by side.
[arch(at="ARCHITECTURE_PROJECTS.md#rendering")]
def projects_text(results : JsonValue const?) : string {
    let names <- keys_of(results?["projects"])
    let lanes <- project_lanes(results)
    return build_string() $(var w) {
        if (!empty(names)) {
            w |> write("Each project of the Rust repository's `tests/manual` on its own fixture, checked against the `expected.stdout` of its canonical case in the Rust repository's `tests/canonical/cases.json`; the native build (the pinned clang with the README's flags) must print it too. ")
            w |> write("Captured: " + join([for (n in names); "{n} ({project_stamp(results?["projects"]?[n])})"], "; ") + ".\n\n")
        }
        w |> write(projects_table(results))
        let defines <- ours_define_lines(results)
        if (!empty(defines)) {
            w |> write("\nDefines of our side's sidecar alone (the Rust side and the native build do not get them):\n\n" + join(defines, "\n") + "\n")
        }
        let reasons <- project_reasons(results)
        if (!empty(reasons)) {
            w |> write("\nWhy a lane does not pass:\n\n" + join(reasons, "\n") + "\n")
        }
        if (!empty(names)) {
            w |> write("\nThe bench entry's timed loop (`decode_us`), a lane's median over the native build's (lower is faster), {samples_text(results)}:\n\n")
            w |> write(project_speed_table(results))
            w |> write("\nThe code of each side's module (the Rust runtime is its `c2da_rt_` and `c2da_std_` declarations):\n\n{project_code_table(results)}")
            for (n in names) {
                w |> write("\n{functions_text(results?["projects"]?[n]?["functions"])}")
            }
        }
    }
}

//! A project's stamp: its Rust commit, its date and the address-space cap its lanes ran under.
[arch(at="ARCHITECTURE_PROJECTS.md#rendering")]
def project_stamp(entry : JsonValue const?) : string {
    let cap = cap_text(entry?["address_cap"] ?? "")
    return empty(cap) ? stamp_of(entry, "date") : "{stamp_of(entry, "date")}, {cap}"
}

//! An address-space cap as the capture holds it (`address_cap_of`) in words: "" when not
//! recorded, `no address-space cap` for `unlimited`, else its size in GiB or MiB.
def cap_text(cap : string) : string {
    if (cap == "unlimited") {
        return "no address-space cap"
    }
    var digits = !empty(cap)
    for (c in cap) {
        digits = digits && is_number(c)
    }
    if (!digits) {
        return empty(cap) ? "" : "address-space cap {cap}"
    }
    let bytes = to_int64(cap)
    let gib = 1073741824l
    return bytes % gib == 0l ? "{bytes / gib} GiB address-space cap" : "{bytes / 1048576l} MiB address-space cap"
}

//! One line per project whose sidecar on our side carries defines of its own.
[arch(at="ARCHITECTURE_PROJECTS.md#rendering")]
def ours_define_lines(results : JsonValue const?) : array<string> {
    var lines : array<string>
    for (name in keys_of(results?["projects"])) {
        var inscope list <- [for (d in strings_of(results?["projects"]?[name]?["ours"]?["defines"])); "`-D{d}`"]
        if (!empty(list)) {
            lines |> push("- {name}, Ours: {join(list, " ")}")
        }
    }
    return <- lines
}

//! The sample count of the projects' bench cells: one count for every project, `not measured`
//! when it is 0, else each project's own.
[arch(at="ARCHITECTURE_PROJECTS.md#rendering")]
def samples_text(results : JsonValue const?) : string {
    let names <- keys_of(results?["projects"])
    let counts <- [for (n in names); results?["projects"]?[n]?["samples"] ?? 0]
    let one = empty([for (c in counts); c; where c != counts[0]])
    if (one) {
        return counts[0] > 0 ? "{counts[0]} samples a cell" : "not measured in this capture (`--samples 0`)"
    }
    return "samples a cell per project: " + join([for (n, c in names, counts); c > 0 ? "{n} {c}" : "{n} not measured"], ", ")
}

// the stamps of a section: its Rust commit and date
def private stamp_of(section : JsonValue const?; date_key : string) : string => "Rust `{slice(section?["rust_commit"] ?? "", 0, 12)}`, {section?[date_key] ?? ""}"

def private list_or(lines : array<string>; none : string) : string => empty(lines) ? "{none}\n" : join(lines, "\n") + "\n"

//! The whole comparison: every table and list under a `###` heading each.
[arch(at="ARCHITECTURE_REPORT.md#report")]
def compare_report(results : JsonValue const?) : string {
    return build_string() $(var w) {
        w |> write("Rendered from c2das-re's `compare/results_linux.json` alone, never edited by hand. ")
        w |> write("Both translators run on one machine and one daslang, under the same runner and oracle (c2das-re's `compare/ARCHITECTURE.md`).\n\n")
        w |> write("### Suites\n\n")
        let suites = results?["suites"]
        let names <- keys_of(suites)
        if (!empty(names)) {
            w |> write("Captured: " + join([for (n in names); "{n} ({stamp_of(suites?[n], "date")})"], "; ") + ". ")
            w |> write("Ours is the ratchet (c2das-re's `suites/<suite>/expected_pass.txt`); the Rust side runs every id under `--libc std --strict`, the interpreter.\n\n")
        }
        w |> write(suites_table(results))
        let perf = results?["perf"]
        w |> write("\n### Speed\n\n")
        if (!absent(perf)) {
            w |> write("Captured {perf?["timestamp"] ?? ""} on {perf?["platform"] ?? ""}, {perf?["cpu"] ?? ""}; {perf?["versions"]?["clang"] ?? ""}; daslang {perf?["versions"]?["daslang"] ?? ""}; ")
            w |> write("Rust `{slice(perf?["rust_commit"] ?? "", 0, 12)}`; {perf?["samples"] ?? 0} samples a cell. A cell is a lane's time over the native build's (lower is faster); ")
            w |> write("the geomean row covers the kernels where native and both sides stand, their count in parentheses.\n\n")
        }
        w |> write(perf_table(results))
        let errors <- perf_errors(results)
        if (!empty(errors)) {
            w |> write("\nError cells:\n\n" + join(errors, "\n") + "\n")
        }
        let quality = results?["quality"]
        w |> write("\n### Readability and size\n\n")
        if (!absent(quality)) {
            w |> write("Captured {stamp_of(quality, "date")}, over every input both sides translated into daslang that compiles. ")
            w |> write("The Rust lines hold the runtime it writes into every module; ours sits in `c_runtime` and `crt`. The Rust counters count its whole module, runtime included.\n\n")
        }
        w |> write(size_table(results))
        let excluded <- excluded_lines(results)
        if (!empty(excluded)) {
            w |> write("\nLeft out of the totals:\n\n" + join(excluded, "\n") + "\n")
        }
        w |> write("\n{counters_table(results)}")
        w |> write("\n### Functions side by side\n\n{side_by_side(results)}")
        w |> write("\n### Lua and Doom\n\n{lua_text(results)}")
        w |> write("\n### Real projects\n\n{projects_text(results)}")
        w |> write("\n### Where the Rust translator is ahead\n\n{list_or(rust_ahead(results), "Nowhere in this capture.")}")
    }
}
