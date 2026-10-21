options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/json_boost
require ../perf_tables.das
require ../perf_cli.das

// fixtures spell JSON quotes as single quotes
def capture_of(t : T?; text : string) : JsonValue? {
    var error : string
    var js = read_json(replace(text, "'", "\""), error)
    t |> equal(error, "", "fixture is JSON")
    return js
}

let TWO_BY_TWO = "\{'timestamp': 'T', 'platform': 'P', 'cpu': 'C', 'samples': 5, 'versions': \{'clang': 'clang', 'daslang': 'das'\}, 'tests': \{'b': \{'native': \{'time': 0.002, 'spread': 0.01\}, 'jit': \{'time': 0.001, 'spread': 0.0\}\}, 'a': \{'native': \{'time': 0.001, 'spread': 0.0\}, 'interp-copy': \{'time': 0.004, 'spread': 0.0\}, 'jit': \{'time': 0.003, 'spread': 0.026\}\}\}\}"

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
    let old = capture_of(t, "\{'tests': \{'a': \{'native': \{'time': 1.0\}, 'jit': \{'time': 2.0\}\}, 'c': \{'native': \{'time': 1.0\}\}\}\}")
    let js = capture_of(t, "\{'tests': \{'a': \{'native': \{'time': 0.95\}, 'interp-copy': \{'time': 3.0\}, 'jit': \{'time': 2.0\}, 'aot': \{'time': 1.0\}\}, 'b': \{'native': \{'time': 1.0\}\}\}\}")
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
    t |> run("another cpu is named in the delta heading") @(t : T?) {
        t |> success(render_delta(other_cpu, old, "old") |> starts_with("Delta against old, (new - old) / old per kernel and lane. The baseline ran on X, this capture on Y: the delta compares lane/native ratios.\n\n"))
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
    let old = capture_of(t, "\{'tests': \{'a': \{'native': \{'time': 1.0\}, 'interp-copy': \{'time': 1.0\}, 'jit': \{'time': 1.0\}\}\}\}")
    t |> run("exactly 10 percent slower is not flagged") @(t : T?) {
        let js = capture_of(t, "\{'tests': \{'a': \{'native': \{'time': 1.0\}, 'jit': \{'time': 1.1\}\}\}\}")
        t |> equal(length(flagged_cells(js, old)), 0)
        t |> success(render_delta(js, old, "old") |> ends_with("\n\nno lane slower than 10%\n"))
    }
    t |> run("10.01 percent slower is flagged, one FLAG list item per cell") @(t : T?) {
        let js = capture_of(t, "\{'tests': \{'a': \{'native': \{'time': 1.2\}, 'interp-copy': \{'time': 1.5\}, 'jit': \{'time': 1.1001\}\}\}\}")
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
    let results = "Captured on T, P, C; clang, das. A cell is the median of 5 samples, each its own process, ± half the sample range as a share of the median; the fastest lane per row is bold.\n\n| Test |      C (clang -O3) | DAS interpreter | DAS interp, copied params |            DAS JIT | DAS exe | DAS AOT |\n| :--- | -----------------: | --------------: | ------------------------: | -----------------: | ------: | ------: |\n| a    | **0.001000s ±0%** |             n/a |            0.004000s ±0% |     0.003000s ±3% |     n/a |     n/a |\n| b    |     0.002000s ±1% |             n/a |                       n/a | **0.001000s ±0%** |     n/a |     n/a |\n"
    let ratios = "Lane time / native, per kernel.\n\n| Test | C (clang -O3) | DAS interpreter | DAS interp, copied params | DAS JIT | DAS exe | DAS AOT |\n| :--- | ------------: | --------------: | ------------------------: | ------: | ------: | ------: |\n| a    |          1.00 |             n/a |                      4.00 |    3.00 |     n/a |     n/a |\n| b    |          1.00 |             n/a |                       n/a |    0.50 |     n/a |     n/a |\n"
    t |> run("results: sorted kernels, the fastest lane bold, the spread rounded, a missing lane n/a") @(t : T?) {
        t |> equal(render_results(js), results)
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
