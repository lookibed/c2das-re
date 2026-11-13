options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/json_boost
require daslib/strings_boost
require ../perf_tables.das
require ../perf_cli.das
require ../perf_compose.das

// fixtures spell JSON quotes as single quotes
def capture_of(t : T?; text : string) : JsonValue? {
    var error : string
    var js = read_json(replace(text, "'", "\""), error)
    t |> equal(error, "", "fixture is JSON")
    return js
}

let TWO_BY_TWO = "\{'lanes': ['native', 'interp', 'interp-copy', 'jit', 'exe', 'aot'], 'timestamp': 'T', 'platform': 'P', 'cpu': 'C', 'samples': 5, 'versions': \{'clang': 'clang', 'daslang': 'das'\}, 'tests': \{'b': \{'native': \{'time': 0.002, 'spread': 0.01\}, 'jit': \{'time': 0.001, 'spread': 0.0\}\}, 'a': \{'native': \{'time': 0.001, 'spread': 0.0\}, 'interp-copy': \{'time': 0.004, 'spread': 0.0\}, 'jit': \{'time': 0.003, 'spread': 0.026\}\}\}\}"

[test]
def test_ratio(t : T?) {
    let js = capture_of(t, TWO_BY_TWO)
    t |> run("lane time over native, native itself 1, a missing lane 0") @(t : T?) {
        t |> equal(ratio_of(js, "a", "jit"), 3.0lf)
        t |> equal(ratio_of(js, "b", "jit"), 0.5lf)
        t |> equal(ratio_of(js, "a", "native"), 1.0lf)
        t |> equal(ratio_of(js, "a", "aot"), 0.0lf)
        t |> equal(ratio_of(js, "z", "jit"), 0.0lf)
    }
    t |> run("a kernel without its native cell has no ratio") @(t : T?) {
        let nonative = capture_of(t, "\{'tests': \{'a': \{'jit': \{'time': 0.5\}\}\}\}")
        t |> equal(ratio_of(nonative, "a", "jit"), 0.0lf)
    }
    t |> run("a lane under a tenth of native is suspect, one list item per cell") @(t : T?) {
        let fast = capture_of(t, "\{'tests': \{'a': \{'native': \{'time': 1.0\}, 'jit': \{'time': 0.5\}, 'aot': \{'time': 0.01\}\}\}\}")
        let suspects <- suspect_cells(fast)
        t |> equal(length(suspects), 1)
        t |> equal(suspects[0], "a/aot at 0.01x native")
        t |> success(render_ratios(fast) |> ends_with("|\n\n- SUSPECT a/aot at 0.01x native: a lane this far under native measures a different program\n"))
        t |> equal(length(suspect_cells(js)), 0)
    }
}

[test]
def test_delta(t : T?) {
    let old = capture_of(t, "\{'cpu': 'X', 'tests': \{'a': \{'native': \{'time': 1.0\}, 'jit': \{'time': 2.0\}\}, 'c': \{'native': \{'time': 1.0\}\}\}\}")
    let js = capture_of(t, "\{'cpu': 'X', 'lanes': ['native', 'interp', 'interp-copy', 'jit', 'exe', 'aot'], 'tests': \{'a': \{'native': \{'time': 0.95\}, 'interp-copy': \{'time': 3.0\}, 'jit': \{'time': 2.0\}, 'aot': \{'time': 1.0\}\}, 'b': \{'native': \{'time': 1.0\}\}\}\}")
    t |> run("a cell on both sides is a signed percent") @(t : T?) {
        var cents = 0l
        t |> success(delta_cents(js, old, "a", "native", cents))
        t |> equal(cents, -500l)
        t |> equal(percent_text(cents), "-5.00%")
        t |> success(delta_cents(js, old, "a", "jit", cents))
        t |> equal(percent_text(cents), "+0.00%")
        t |> equal(percent_text(1234l), "+12.34%")
        t |> equal(percent_text(-7l), "-0.07%")
    }
    t |> run("a lane or a kernel missing on either side has no delta") @(t : T?) {
        var cents = 0l
        t |> success(!delta_cents(js, old, "a", "aot", cents), "lane only in the new capture")
        t |> success(!delta_cents(js, old, "a", "interp-copy", cents), "the copy lane only in the new capture")
        t |> success(!delta_cents(js, old, "b", "native", cents), "kernel only in the new capture")
        t |> success(!delta_cents(js, old, "c", "native", cents), "kernel only in the baseline")
    }
    t |> run("the delta table spans the kernels of both captures, n/a where a side is missing") @(t : T?) {
        let text = render_delta(js, old, "old.json")
        t |> equal(text, "Delta against old.json, (new - old) / old per kernel and lane.\n\n| Test | C (clang -O3) | DAS interpreter | DAS interp, copied params | DAS JIT | DAS exe | DAS AOT |\n| :--- | ------------: | --------------: | ------------------------: | ------: | ------: | ------: |\n| a    |        -5.00% |             n/a |                       n/a |  +0.00% |     n/a |     n/a |\n| b    |           n/a |             n/a |                       n/a |     n/a |     n/a |     n/a |\n| c    |           n/a |             n/a |                       n/a |     n/a |     n/a |     n/a |\n\nno lane slower than 10%\n")
    }
}

[test]
def test_delta_across_cpus(t : T?) {
    let old = capture_of(t, "\{'cpu': 'X', 'tests': \{'a': \{'native': \{'time': 1.0\}, 'jit': \{'time': 2.0\}\}\}\}")
    let other_cpu = capture_of(t, "\{'cpu': 'Y', 'tests': \{'a': \{'native': \{'time': 3.0\}, 'jit': \{'time': 6.9\}\}\}\}")
    let same_cpu_run = capture_of(t, "\{'cpu': 'X', 'tests': \{'a': \{'native': \{'time': 3.0\}, 'jit': \{'time': 6.9\}\}\}\}")
    t |> run("another cpu compares lane/native ratios, native has no delta and never flags") @(t : T?) {
        var cents = 0l
        t |> success(!delta_cents(other_cpu, old, "a", "native", cents))
        t |> success(delta_cents(other_cpu, old, "a", "jit", cents))
        t |> equal(cents, 1500l)
        let flags <- flagged_cells(other_cpu, old)
        t |> equal(length(flags), 1)
        t |> equal(flags[0], "a/jit +15.00%")
    }
    t |> run("another cpu without a box renders no delta, one line naming both") @(t : T?) {
        t |> equal(render_delta(other_cpu, old, "old"), "no delta: Y against X, numbers of two boxes are not compared\n")
    }
    t |> run("captures of two boxes render no delta table, one box renders it") @(t : T?) {
        let boxed = capture_of(t, "\{'cpu': 'Y', 'box': 'PC', 'tests': \{\}\}")
        let bench = capture_of(t, "\{'cpu': 'AMD Ryzen 3 1200 Quad-Core Processor', 'tests': \{'a': \{'native': \{'time': 1.0\}\}\}\}")
        let fx = capture_of(t, "\{'cpu': 'AMD FX(tm)-6300', 'tests': \{'a': \{'native': \{'time': 1.0\}\}\}\}")
        let two_boxes = render_delta(fx, bench, "old")
        t |> equal(two_boxes, "no delta: fx (AMD FX(tm)-6300) against bench (AMD Ryzen 3 1200 Quad-Core Processor), numbers of two boxes are not compared\n")
        t |> success(!(two_boxes |> contains("|")), two_boxes)
        t |> equal(render_delta(boxed, old, "old"), "no delta: PC (Y) against X, numbers of two boxes are not compared\n")
        let bench_named = capture_of(t, "\{'cpu': 'Other CPU', 'box': 'bench', 'tests': \{'a': \{'native': \{'time': 1.0\}\}\}\}")
        let one_box = render_delta(bench_named, bench, "old")
        t |> success(one_box |> starts_with("Delta against old, (new - old) / old per kernel and lane."), one_box)
        t |> success(one_box |> contains("| a    |"), one_box)
    }
    t |> run("one box, two CPU strings: the heading notes both labels and the ratios; one CPU, no note") @(t : T?) {
        let a = capture_of(t, "\{'cpu': 'A', 'box': 'bench', 'tests': \{'a': \{'native': \{'time': 1.0\}, 'jit': \{'time': 2.0\}\}\}\}")
        let b = capture_of(t, "\{'cpu': 'B', 'box': 'bench', 'tests': \{'a': \{'native': \{'time': 2.0\}, 'jit': \{'time': 4.0\}\}\}\}")
        t |> success(render_delta(a, b, "old") |> starts_with("Delta against old, (new - old) / old per kernel and lane. The baseline ran on bench (B), this capture on bench (A): the delta compares lane/native ratios.\n\n"), render_delta(a, b, "old"))
        let b_same = capture_of(t, "\{'cpu': 'A', 'box': 'bench', 'tests': \{'a': \{'native': \{'time': 2.0\}, 'jit': \{'time': 4.0\}\}\}\}")
        t |> success(render_delta(a, b_same, "old") |> starts_with("Delta against old, (new - old) / old per kernel and lane.\n\n"), render_delta(a, b_same, "old"))
    }
    t |> run("the same cpu compares times, native included, under a plain heading") @(t : T?) {
        var cents = 0l
        t |> success(delta_cents(same_cpu_run, old, "a", "native", cents))
        t |> equal(cents, 20000l)
        t |> equal(length(flagged_cells(same_cpu_run, old)), 2)
        t |> success(render_delta(same_cpu_run, old, "old") |> starts_with("Delta against old, (new - old) / old per kernel and lane.\n\n"))
    }
}

[test]
def test_flag(t : T?) {
    let old = capture_of(t, "\{'cpu': 'X', 'tests': \{'a': \{'native': \{'time': 1.0\}, 'interp-copy': \{'time': 1.0\}, 'jit': \{'time': 1.0\}\}\}\}")
    t |> run("exactly 10 percent slower is not flagged") @(t : T?) {
        let js = capture_of(t, "\{'cpu': 'X', 'tests': \{'a': \{'native': \{'time': 1.0\}, 'jit': \{'time': 1.1\}\}\}\}")
        t |> equal(length(flagged_cells(js, old)), 0)
        t |> success(render_delta(js, old, "old") |> ends_with("\n\nno lane slower than 10%\n"))
    }
    t |> run("10.01 percent slower is flagged, one FLAG list item per cell") @(t : T?) {
        let js = capture_of(t, "\{'cpu': 'X', 'tests': \{'a': \{'native': \{'time': 1.2\}, 'interp-copy': \{'time': 1.5\}, 'jit': \{'time': 1.1001\}\}\}\}")
        let flags <- flagged_cells(js, old)
        t |> equal(length(flags), 3)
        t |> equal(flags[0], "a/native +20.00%")
        t |> equal(flags[1], "a/interp-copy +50.00%")
        t |> equal(flags[2], "a/jit +10.01%")
        t |> success(render_delta(js, old, "old") |> ends_with("|\n\n- FLAG a/native +20.00%\n- FLAG a/interp-copy +50.00%\n- FLAG a/jit +10.01%\n"))
    }
}

[test]
def test_markdown(t : T?) {
    let js = capture_of(t, TWO_BY_TWO)
    let results = "Captured on T, P, C; clang, das. A cell is the median of 5 samples, each its own process, ± half the sample range as a share of the median; the fastest lane per row is bold; a cell whose spread is above 20% is `suspect` with its spread, no time, and in no ratio or delta.\n\n| Test |      C (clang -O3) | DAS interpreter | DAS interp, copied params |            DAS JIT | DAS exe | DAS AOT |\n| :--- | -----------------: | --------------: | ------------------------: | -----------------: | ------: | ------: |\n| a    | **0.001000s ±0%** |             n/a |            0.004000s ±0% |     0.003000s ±3% |     n/a |     n/a |\n| b    |     0.002000s ±1% |             n/a |                       n/a | **0.001000s ±0%** |     n/a |     n/a |\n"
    let ratios = "Lane time / native, per kernel.\n\n| Test | C (clang -O3) | DAS interpreter | DAS interp, copied params | DAS JIT | DAS exe | DAS AOT |\n| :--- | ------------: | --------------: | ------------------------: | ------: | ------: | ------: |\n| a    |          1.00 |             n/a |                      4.00 |    3.00 |     n/a |     n/a |\n| b    |          1.00 |             n/a |                       n/a |    0.50 |     n/a |     n/a |\n"
    t |> run("results: sorted kernels, the fastest lane bold, the spread rounded, a missing lane n/a") @(t : T?) {
        t |> equal(render_results(js), results)
    }
    t |> run("the provenance line labels the capture with its box, a capture without one with its cpu's") @(t : T?) {
        let boxed = capture_of(t, "\{'cpu': 'C', 'box': 'fx', 'tests': \{\}\}")
        t |> success(render_results(boxed) |> starts_with("Captured on , , fx (C); "), render_results(boxed))
        let bench = capture_of(t, "\{'cpu': 'AMD Ryzen 3 1200 Quad-Core Processor', 'tests': \{\}\}")
        t |> success(render_results(bench) |> starts_with("Captured on , , bench (AMD Ryzen 3 1200 Quad-Core Processor); "), render_results(bench))
    }
    t |> run("a capture without tests has no kernels") @(t : T?) {
        t |> equal(length(kernel_names(capture_of(t, "\{'cpu': 'C'\}"))), 0)
    }
    t |> run("ratios: two decimals, native 1.00") @(t : T?) {
        t |> equal(render_ratios(js), ratios)
    }
    t |> run("the report without a baseline says there is no delta") @(t : T?) {
        t |> equal(render_report(js, null, ""), "**Results**\n\n{results}\n**Ratios**\n\n{ratios}\n**Delta**\n\nNo baseline capture: no delta.\n")
    }
    t |> run("the report with a baseline carries the delta table") @(t : T?) {
        let report = render_report(js, js, "same")
        t |> success(report |> ends_with("**Delta**\n\n{render_delta(js, js, "same")}"))
    }
}

// `a` with its native cell at a 21% spread, `b` with its native and interpreter cells at 20% and
// its JIT cell at 21%; the baseline has the same cells without spreads, `b`'s JIT twice as fast
let SUSPECT_CAPTURE = "\{'cpu': 'X', 'lanes': ['native', 'interp', 'jit'], 'samples': 5, 'tests': \{'a': \{'native': \{'time': 1.0, 'spread': 0.21\}, 'jit': \{'time': 2.0, 'spread': 0.0\}\}, 'b': \{'native': \{'time': 1.0, 'spread': 0.2\}, 'interp': \{'time': 3.0, 'spread': 0.2\}, 'jit': \{'time': 0.5, 'spread': 0.21\}\}\}\}"
let SUSPECT_BASELINE = "\{'cpu': 'X', 'tests': \{'a': \{'native': \{'time': 1.0\}, 'jit': \{'time': 2.0\}\}, 'b': \{'native': \{'time': 1.0\}, 'interp': \{'time': 3.0\}, 'jit': \{'time': 0.25\}\}\}\}"

[test]
def test_suspect(t : T?) {
    let js = capture_of(t, SUSPECT_CAPTURE)
    let old = capture_of(t, SUSPECT_BASELINE)
    t |> run("results: a cell of spread above 20% is suspect with its spread and never the bold one; 20% exactly is a time") @(t : T?) {
        let text = render_results(js)
        t |> success(text |> contains("| a    |   suspect (±21.0%) |             n/a | **2.000000s ±0%** |"), text)
        t |> success(text |> contains("| b    | **1.000000s ±20%** | 3.000000s ±20% |  suspect (±21.0%) |"), text)
    }
    t |> run("ratios: a suspect lane or a suspect native cell has no ratio, and no lane under the bar is listed over one") @(t : T?) {
        let text = render_ratios(js)
        t |> success(text |> contains("| a    |       suspect |             n/a | suspect |"), text)
        t |> success(text |> contains("| b    |          1.00 |            3.00 | suspect |"), text)
        t |> equal(length(suspect_cells(js)), 0)
    }
    t |> run("delta: a suspect cell of either capture has none, so it neither flags nor drifts") @(t : T?) {
        let text = render_delta(js, old, "old")
        t |> success(text |> contains("| a    |       suspect |             n/a |  +0.00% |"), text)
        t |> success(text |> contains("| b    |        +0.00% |          +0.00% | suspect |"), text)
        t |> success(text |> ends_with("no lane slower than 10%\n"), text)
        t |> success(render_delta(old, js, "new") |> contains("| b    |        +0.00% |          +0.00% |                       n/a |"), render_delta(old, js, "new"))
        var cents = 0l
        t |> success(!delta_cents(js, old, "b", "jit", cents))
        t |> equal(length(drifted_cells(js, old, 1000l)), 0)
    }
    t |> run("the method comparison: a suspect cell has its spread, a converted one over a suspect C cell its seconds alone") @(t : T?) {
        let m = capture_of(t, "\{'cpu': 'C', 'tests': \{'fib_loop': \{'native': \{'time': 0.002, 'spread': 0.21\}, 'interp': \{'time': 0.06, 'spread': 0.21\}, 'jit': \{'time': 0.004\}, 'exe': \{'time': 0.004\}, 'aot': \{'time': 0.002\}\}\}\}")
        let text = render_method_comparison(m, capture_of(t, "\{'cpu': 'C'\}"))
        t |> success(text |> contains("| fib_loop | suspect (±21.0%) |            n/a |                 n/a |              n/a |              n/a | suspect (±21.0%) |        0.004s |        0.002s |        0.004s |"), text)
    }
}

[test]
def test_cli(t : T?) {
    var dir_error : string
    let dir = create_temp_directory("c2das_perf_test", dir_error)
    if (!empty(dir_error)) {
        t |> failure("no temp directory: {dir_error}")
        return
    }
    let empty_file = path_join(dir, "empty.json")
    let invalid_file = path_join(dir, "invalid.json")
    let valid_file = path_join(dir, "valid.json")
    fwrite(empty_file, "")
    fwrite(invalid_file, "\{ not json")
    fwrite(valid_file, replace(TWO_BY_TWO, "'", "\""))
    t |> run("--baseline: a missing, empty or invalid file is an error naming it") @(t : T?) {
        for (path in [path_join(dir, "missing.json"), empty_file, invalid_file]) {
            var name, error : string
            let js = baseline_capture(path, "unused", name, error)
            t |> success(js == null, path)
            t |> success(error |> starts_with("{path}: "), error)
            t |> equal(name, path)
        }
    }
    t |> run("--baseline: a valid file is the baseline, named by its path") @(t : T?) {
        var name, error : string
        let js = baseline_capture(valid_file, "unused", name, error)
        t |> success(js != null)
        t |> equal(error, "")
        t |> equal(name, valid_file)
        t |> equal(js?["cpu"] ?? "", "C")
    }
    t |> run("no --baseline: the committed file at HEAD, none when HEAD lacks it, an error when it is not JSON") @(t : T?) {
        var name, error : string
        t |> success(baseline_capture("", "perf/results_linux.json", name, error) != null, "run from the repository root")
        t |> equal(name, "HEAD:perf/results_linux.json")
        t |> equal(error, "")
        t |> success(baseline_capture("", "perf/no_such_capture.json", name, error) == null)
        t |> equal(error, "")
        t |> success(baseline_capture("", "README.md", name, error) == null)
        t |> success(error |> starts_with("HEAD:README.md: "), error)
    }
    let js = capture_of(t, TWO_BY_TWO)
    t |> run("the report arm writes the file and returns its text") @(t : T?) {
        let report = path_join(dir, "report.md")
        let text = show_tables(js, js, "same", false, report)
        t |> equal(text, render_report(js, js, "same"))
        t |> equal(fread(report), text)
    }
    t |> run("without a report: the results, the ratios when asked, the delta only with a baseline") @(t : T?) {
        t |> equal(show_tables(js, null, "", false, ""), render_results(js))
        t |> equal(show_tables(js, null, "", true, ""), render_results(js) + "\n" + render_ratios(js))
        t |> equal(show_tables(js, js, "same", false, ""), render_results(js) + "\n" + render_delta(js, js, "same"))
    }
}

[test]
def test_lanes(t : T?) {
    t |> run("a capture's own lane list orders the columns; one without a list takes every lane") @(t : T?) {
        let listed = capture_of(t, "\{'lanes': ['native', 'jit'], 'tests': \{'a': \{'native': \{'time': 1.0\}, 'jit': \{'time': 2.0\}\}\}\}")
        t |> equal(render_ratios(listed), "Lane time / native, per kernel.\n\n| Test | C (clang -O3) | DAS JIT |\n| :--- | ------------: | ------: |\n| a    |          1.00 |    2.00 |\n")
        let unlisted = capture_of(t, "\{'tests': \{'a': \{'native': \{'time': 1.0\}, 'interp-while': \{'time': 4.0\}\}\}\}")
        let lanes <- lanes_of(unlisted)
        t |> equal(join(lanes, " "), "native interp interp-copy interp-while interp-reinterpret interp-inline interp-goto interp-checks-off interp-past-end-inline interp-fn-macros-expand interp-pointer-steps-off interp-ranged-loops-off interp-c-switch-off jit exe aot")
        t |> success(render_ratios(unlisted) |> contains("| DAS interp, while loops |"), render_ratios(unlisted))
        t |> success(render_ratios(unlisted) |> contains("|                    4.00 |"), render_ratios(unlisted))
    }
}

[test]
def test_drift(t : T?) {
    let old = capture_of(t, "\{'cpu': 'X', 'lanes': ['native', 'jit', 'aot'], 'tests': \{'a': \{'native': \{'time': 1.0\}, 'jit': \{'time': 2.0\}, 'aot': \{'time': 1.0\}\}\}\}")
    t |> run("a cell past the tolerance either way drifts; at the tolerance it does not") @(t : T?) {
        let js = capture_of(t, "\{'cpu': 'X', 'lanes': ['native', 'jit', 'aot'], 'tests': \{'a': \{'native': \{'time': 1.1\}, 'jit': \{'time': 1.7\}, 'aot': \{'time': 1.0\}\}\}\}")
        let drifted <- drifted_cells(js, old, 1000l)
        t |> equal(join(drifted, "; "), "a/jit -15.00%")
        let tight <- drifted_cells(js, old, 500l)
        t |> equal(join(tight, "; "), "a/native +10.00%; a/jit -15.00%")
    }
    t |> run("a cell one capture has and the other lacks is missing, a kernel too") @(t : T?) {
        let js = capture_of(t, "\{'cpu': 'X', 'lanes': ['native', 'jit', 'aot'], 'tests': \{'a': \{'native': \{'time': 1.0\}, 'jit': \{'time': 2.0\}\}, 'b': \{'native': \{'time': 1.0\}\}\}\}")
        let drifted <- drifted_cells(js, old, 1000l)
        t |> equal(join(drifted, "; "), "a/aot missing; b/native missing")
    }
    t |> run("a baseline cell whose samples spread wider than the tolerance drifts only past twice its spread") @(t : T?) {
        let noisy = capture_of(t, "\{'cpu': 'X', 'lanes': ['native', 'jit'], 'tests': \{'a': \{'native': \{'time': 1.0, 'spread': 0.01\}, 'jit': \{'time': 2.0, 'spread': 0.2\}\}\}\}")
        let within = capture_of(t, "\{'cpu': 'X', 'lanes': ['native', 'jit'], 'tests': \{'a': \{'native': \{'time': 1.0\}, 'jit': \{'time': 2.7\}\}\}\}")
        t |> equal(length(drifted_cells(within, noisy, 1000l)), 0)
        let past = capture_of(t, "\{'cpu': 'X', 'lanes': ['native', 'jit'], 'tests': \{'a': \{'native': \{'time': 1.0\}, 'jit': \{'time': 2.9\}\}\}\}")
        t |> equal(join(drifted_cells(past, noisy, 1000l), "; "), "a/jit +45.00%")
    }
    t |> run("a lane or a kernel only the baseline has is missing") @(t : T?) {
        let wider = capture_of(t, "\{'cpu': 'X', 'lanes': ['native', 'jit', 'aot', 'exe'], 'tests': \{'a': \{'native': \{'time': 1.0\}, 'jit': \{'time': 2.0\}, 'aot': \{'time': 1.0\}, 'exe': \{'time': 2.0\}\}, 'c': \{'native': \{'time': 1.0\}\}\}\}")
        let js = capture_of(t, "\{'cpu': 'X', 'lanes': ['native', 'jit', 'aot'], 'tests': \{'a': \{'native': \{'time': 1.0\}, 'jit': \{'time': 2.0\}, 'aot': \{'time': 1.0\}\}\}\}")
        let drifted <- drifted_cells(js, wider, 1000l)
        t |> equal(join(drifted, "; "), "a/exe missing; c/native missing")
    }
    t |> run("--check: no baseline fails; a capture within the tolerance passes, one past it fails") @(t : T?) {
        let js = capture_of(t, "\{'cpu': 'X', 'lanes': ['native', 'jit', 'aot'], 'tests': \{'a': \{'native': \{'time': 1.05\}, 'jit': \{'time': 2.0\}, 'aot': \{'time': 1.0\}\}\}\}")
        t |> success(!check_drift(js, null, "none", 10))
        t |> success(check_drift(js, old, "old", 10))
        t |> success(!check_drift(js, old, "old", 4))
    }
    t |> run("captures of two boxes: no check, drifted_cells names the two boxes and --check fails") @(t : T?) {
        let other = capture_of(t, "\{'cpu': 'AMD FX(tm)-6300', 'lanes': ['native'], 'tests': \{'a': \{'native': \{'time': 1.0\}\}\}\}")
        t |> equal(join(drifted_cells(other, old, 1000l), "; "), "no check: fx (AMD FX(tm)-6300) against X, numbers of two boxes are not compared")
        t |> success(!check_drift(other, old, "old", 1000))
    }
}

let METHOD_CAPTURE = "\{'cpu': 'C', 'timestamp': 'T', 'versions': \{'clang': 'clang 22', 'daslang': '0.6.4'\}, 'lanes': ['native', 'interp', 'jit', 'exe', 'aot'], 'tests': \{'fib_loop': \{'native': \{'time': 0.00190631\}, 'interp': \{'time': 0.06\}, 'jit': \{'time': 0.004\}, 'exe': \{'time': 0.004\}, 'aot': \{'time': 0.001906438\}\}, 'sieve': \{'native': \{'time': 0.1\}\}\}\}"
let DASPROFILE_CAPTURE = "\{'cpu': 'C', 'timestamp': 'D', 'dasprofile_commit': 'abc', 'toolchain': 'Clang 22', 'Interpreted': \{'fibonacci loop': [\{'language': 'DAS INTERPRETER', 'time': 0.06\}]\}, 'AOT or JIT': \{'fibonacci loop': [\{'language': 'DAS AOT', 'time': 0.002\}, \{'language': 'DAS JIT', 'time': 0.002\}, \{'language': 'C++', 'time': 0.001905751\}]\}\}"

[test]
def test_method_comparison(t : T?) {
    let method = capture_of(t, METHOD_CAPTURE)
    let dp = capture_of(t, DASPROFILE_CAPTURE)
    t |> run("dasProfile's capture gives a language's time on a board, 0 for none") @(t : T?) {
        t |> equal(dasprofile_time(dp, "AOT or JIT", "fibonacci loop", "C++"), 0.001905751lf)
        t |> equal(dasprofile_time(dp, "Interpreted", "fibonacci loop", "DAS INTERPRETER"), 0.06lf)
        t |> equal(dasprofile_time(dp, "Interpreted", "primes loop", "DAS INTERPRETER"), 0.0lf)
        t |> equal(dasprofile_time(dp, "AOT or JIT", "fibonacci loop", "Zig"), 0.0lf)
    }
    t |> run("--readme rewrites the method's section between its markers, the other untouched; a missing marker or capture is the error") @(t : T?) {
        var dir_error : string
        let dir = create_temp_directory("c2das_perf_readme", dir_error)
        t |> equal(dir_error, "")
        let readme = path_join(dir, "README.md")
        let dp_path = path_join(dir, "dasprofile.json")
        fwrite(dp_path, replace(DASPROFILE_CAPTURE, "'", "\""))
        fwrite(readme, "top\n{README_BEGIN}\nold table\n{README_END}\nmiddle\n{README_METHOD_BEGIN}\nold comparison\n{README_METHOD_END}\nend\n")
        t |> equal(write_readme(readme, dp_path, method, "dasprofile"), "")
        let compared = fread(readme)
        t |> equal(compared, "top\n{README_BEGIN}\nold table\n{README_END}\nmiddle\n{README_METHOD_BEGIN}\n{render_method_comparison(method, dp)}{README_METHOD_END}\nend\n")
        t |> equal(write_readme(readme, dp_path, method, "default"), "")
        t |> equal(fread(readme), "top\n{README_BEGIN}\n{render_results(method)}{README_END}\nmiddle\n{README_METHOD_BEGIN}\n{render_method_comparison(method, dp)}{README_METHOD_END}\nend\n")
        fwrite(readme, "no markers\n")
        t |> equal(write_readme(readme, dp_path, method, "dasprofile"), "{readme} has no perf-method markers")
        t |> equal(write_readme(readme, dp_path, method, "default"), "{readme} has no perf-table markers")
        t |> success(write_readme(readme, path_join(dir, "none.json"), method, "dasprofile") |> contains("none.json"))
        rmdir_rec(dir)
    }
    t |> run("one row per shared kernel: each hand-written cell over dasProfile's C++, each converted one over the C program; the different programs named") @(t : T?) {
        let text = render_method_comparison(method, dp)
        t |> success(text |> starts_with("The dasProfile method on C, T (clang 22, daslang 0.6.4) beside borisbat/dasProfile abc run on C, D (Clang 22)."), text)
        // five significant digits keep apart cells a microsecond apart
        t |> success(text |> contains("| fib_loop |    0.0019063s |     0.0019058s |      0.06s (31.48x) |   0.002s (1.05x) |   0.002s (1.05x) |   0.06s (31.47x) | 0.004s (2.10x) | 0.0019064s (1.00x) | 0.004s (2.10x) |"), text)
        t |> success(!(text |> contains("| sieve")), text)
        let two_boxes = render_method_comparison(capture_of(t, "\{'cpu': 'AMD FX(tm)-6300', 'tests': \{\}\}"), capture_of(t, "\{'cpu': 'C', 'box': 'bench'\}"))
        t |> equal(two_boxes, "no comparison: fx (AMD FX(tm)-6300) against bench (C), numbers of two boxes are not compared\n")
        let labelled = render_method_comparison(capture_of(t, "\{'cpu': 'AMD Ryzen 3 1200 Quad-Core Processor', 'timestamp': 'T', 'tests': \{\}\}"), capture_of(t, "\{'cpu': 'AMD Ryzen 3 1200 Quad-Core', 'timestamp': 'D'\}"))
        t |> success(labelled |> starts_with("The dasProfile method on bench (AMD Ryzen 3 1200 Quad-Core Processor), T ("), labelled)
        t |> success(labelled |> contains(" run on bench (AMD Ryzen 3 1200 Quad-Core), D ("), labelled)
        let bare = render_method_comparison(method, capture_of(t, "\{'cpu': 'C', 'dasprofile_commit': 'x'\}"))
        t |> success(bare |> contains("| fib_loop |    0.0019063s |            n/a |                 n/a |"), bare)
        // the hand-written columns time a literal count
        t |> success(text |> contains("dasProfile's hand-written das passes its count as a literal (`fibI(6511134)`, `fibR(31)`, `primes(14000)`) where its C++ and the converted program read a `volatile` one"), text)
        t |> success(text |> contains("- the first table's `fib_loop`, `fib_recursive` and `primes` are this tree's versions of the three"), text)
        t |> success(text |> contains("- `fixed_mandel` (16.16 fixed point, 96x96, 48 iterations, struct vectors by value) is not dasProfile's `mandelbrot` (double, 64x64, 255 iterations): different programs, not compared\n"), text)
    }
}

[test]
def test_method_kernels(t : T?) {
    t |> run("the dasProfile method runs the method kernels, the ones SHARED_KERNELS names, whatever the filter matches beside them") @(t : T?) {
        var named <- [for (k in keys(SHARED_KERNELS)); k]
        sort(named)
        t |> equal(join(kernel_ids("dasprofile", ""), " "), join(named, " "))
        t |> equal(join(kernel_ids("dasprofile", "s"), " "), "fib_recursive primes")
        t |> success(has_value(kernel_ids("default", "s"), "sieve"))
    }
    t |> run("the method's program leaves the noinline to the kernel's own functions") @(t : T?) {
        let text = composed_method_source(fread("{METHOD_KERNELS}/fib_loop.c"))
        t |> success(text |> contains("__attribute__((noinline)) int fibI(int n) \{"), text)
        t |> success(!(text |> contains("kernel_run(void) __attribute__")), text)
    }
}
