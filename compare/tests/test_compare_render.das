options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require daslib/json_boost
require ../../perf/perf_lanes.das
require ../compare_render.das
require ../../perf/boxes.das
require ../../ports/tests/_standin_upstream.das

//! `compare/compare_render.das` over captures the test writes: every table and list, each section
//! missing, and `compare/run.das --readme` and `--report` over scratch files in a scratch folder.

// one suite with every status, the Rust side passing more than the ratchet
let SUITE = "\"s1\": \{\"ids\": 9, \"ours_pass\": 1, \"rust\": \{\"pass\": 2, \"refused\": 1, \"compile\": 1, \"timeout\": 1, \"exit\": 1, \"output\": 1, \"native\": 1, \"crash\": 1\}, \"rust_pass_of_ours\": 1, \"rust_pass_of_skipped\": 1, \"rust_pass_of_unlisted\": 0, \"rust_commit\": \"abcdef0123456789\", \"date\": \"d1\"\}"
// a second suite where the ratchet passes more
let SUITE2 = "\"s2\": \{\"ids\": 4, \"ours_pass\": 4, \"rust\": \{\"pass\": 4\}, \"rust_pass_of_ours\": 4\}"

// two kernels: `k1` our interpreter 2x native, our JIT a differing result, the Rust side 1x and
// 3x; `k2` refused on the Rust side, its native an error
let PERF = "\"perf\": \{\"lanes\": [\"native\", \"interp\", \"jit\"], \"timestamp\": \"t\", \"samples\": 5, \"kernels\": \{
\"k1\": \{\"native\": \{\"time\": 0.5\}, \"ours\": \{\"interp\": \{\"time\": 1.0\}, \"jit\": \{\"error\": \"result 5 differs from the native 6\"\}\}, \"rust\": \{\"status\": \"ran\", \"lanes\": \{\"interp\": \{\"time\": 0.5\}, \"jit\": \{\"time\": 1.5\}\}\}\},
\"k2\": \{\"native\": \{\"error\": \"convert: no\"\}, \"ours\": \{\"interp\": \{\"error\": \"convert: no\"\}\}, \"rust\": \{\"status\": \"refused\", \"error\": \"translation failed: x; cause=unsupported external call: qsort\"\}\}\},
\"geomean\": \{\"interp\": \{\"ours\": 2.0, \"rust\": 1.0, \"kernels\": 1\}, \"jit\": \{\"ours\": 0.0, \"rust\": 0.0, \"kernels\": 0\}\}\}"

// three kernels: `k1` our interpreter's cell at a 21% spread, the Rust one at 20%; `k2` its native
// cell at 21%; `k3` native at 20%, nothing suspect. The capture's geomean counts all three
let SUSPECT_PERF = "\{\"perf\": \{\"lanes\": [\"native\", \"interp\"], \"kernels\": \{
\"k1\": \{\"native\": \{\"time\": 1.0\}, \"ours\": \{\"interp\": \{\"time\": 2.0, \"spread\": 0.21\}\}, \"rust\": \{\"status\": \"ran\", \"lanes\": \{\"interp\": \{\"time\": 1.0, \"spread\": 0.2\}\}\}\},
\"k2\": \{\"native\": \{\"time\": 1.0, \"spread\": 0.21\}, \"ours\": \{\"interp\": \{\"time\": 3.0\}\}, \"rust\": \{\"status\": \"ran\", \"lanes\": \{\"interp\": \{\"time\": 3.0\}\}\}\},
\"k3\": \{\"native\": \{\"time\": 1.0, \"spread\": 0.2\}, \"ours\": \{\"interp\": \{\"time\": 4.0\}\}, \"rust\": \{\"status\": \"ran\", \"lanes\": \{\"interp\": \{\"time\": 2.0\}\}\}\}\},
\"geomean\": \{\"interp\": \{\"ours\": 3.0, \"rust\": 1.8, \"kernels\": 3\}\}\}\}"

// one group and `all`: the Rust side lower on `goto` and on its lines without its runtime; one
// key left out
let QUALITY = "\"quality\": \{\"rust_commit\": \"q\", \"date\": \"d\", \"totals\": \{
\"s1\": \{\"keys\": 2, \"counted\": 1, \"excluded\": \{\"rust_compile\": 1\}, \"ours\": \{\"files\": 1, \"lines\": 10, \"goto\": 3\}, \"rust\": \{\"files\": 2, \"lines\": 30, \"runtime_lines\": 25, \"goto\": 1\}, \"line_ratio\": 3.0, \"program_line_ratio\": 0.5\},
\"all\": \{\"keys\": 2, \"counted\": 1, \"excluded\": \{\}, \"ours\": \{\"files\": 1, \"lines\": 10, \"goto\": 3, \"label\": 2\}, \"rust\": \{\"files\": 2, \"lines\": 30, \"runtime_lines\": 25, \"goto\": 1, \"label\": 2\}, \"line_ratio\": 3.0, \"program_line_ratio\": 0.5\}\},
\"functions\": [\{\"key\": \"s1/a\", \"name\": \"f\", \"ours\": \"def f \{\n\}\", \"rust\": \"\"\}]\}"

let LUA = "\"lua\": \{\"program\": \"lua\", \"units\": 3, \"status\": \"refused\", \"error\": \"translation failed: operation=x; cause=unsupported external call: ldexp\", \"gap\": [\"ldexp\", \"clock\"], \"gap_error\": \"\"\}, \"doom\": \{\"status\": \"pending\", \"reason\": \"P6\"\}"

def private json_of(t : T?; text : string) : JsonValue? {
    var error : string
    var js = read_json(text, error)
    t |> equal(error, "")
    return js
}

def private full_capture : string => "\{\"suites\": \{{SUITE}\}, {PERF}, {QUALITY}, {LUA}\}"

[test]
def test_suites(t : T?) {
    t |> run("one suite: every status a column, no total row") @(t : T?) {
        let md = suites_table(json_of(t, "\{\"suites\": \{{SUITE}\}\}"))
        t |> success(md |> contains("| s1    |   9 |                   1 |         2 |                 1 |            1 |           0 |            1 |            1 |            1 |         1 |           1 |           1 |          1 |"), md)
        for (s in STATUSES) {
            t |> success(md |> contains(s == "pass" ? "Rust pass |" : "Rust {s} |"), "{s}: {md}")
        }
        t |> success(!(md |> contains("total")), md)
    }
    t |> run("two suites: the total row sums each column") @(t : T?) {
        let md = suites_table(json_of(t, "\{\"suites\": \{{SUITE}, {SUITE2}\}\}"))
        t |> success(md |> contains("| total |  13 |                   5 |         6 |                 5 |"), md)
    }
    t |> run("no suite: said so") @(t : T?) {
        t |> equal(suites_table(json_of(t, "\{\}")), "No suite is captured yet.\n")
    }
}

[test]
def test_error_word(t : T?) {
    t |> run("each error line in its short form") @(t : T?) {
        t |> equal(error_word("result 5 differs from the native 6"), "differs")
        t |> equal(error_word("a sample took longer than 120 s"), "timeout")
        t |> equal(error_word("the build exited 1 and left no binary: x"), "compile")
        t |> equal(error_word("exited 1: EXCEPTION"), "exit")
        t |> equal(error_word("convert: no"), "convert")
        t |> equal(error_word("something else"), "error")
    }
}

[test]
def test_perf(t : T?) {
    t |> run("ratios, short errors, refused, the geomean row with its count, n/a without kernels") @(t : T?) {
        let md = perf_table(json_of(t, "\{{PERF}\}"))
        t |> success(md |> contains("| Kernel            | native (s) |"), md)
        t |> success(md |> contains("| k1                |   0.500000 |             2.00 |             1.00 |  differs |     3.00 |"), md)
        t |> success(md |> contains("| k2                |    convert |          convert |          refused |      n/a |  refused |"), md)
        t |> success(md |> contains("| geomean (kernels) |            |         2.00 (1) |         1.00 (1) |      n/a |      n/a |"), md)
    }
    t |> run("the error lines: the refusal and each error cell") @(t : T?) {
        let lines <- perf_errors(json_of(t, "\{{PERF}\}"))
        t |> equal(join(lines, "\n"), "- k1, ours JIT: result 5 differs from the native 6\n- k2, Rust: refused: translation failed: x; cause=unsupported external call: qsort\n- k2, ours interpreter: convert: no")
    }
    t |> run("our AOT cell of a kernel a fork issue slows carries the issue and the footnote under the table; Rust's cell and other kernels none") @(t : T?) {
        with_standin_marks() $ {
            let md = perf_table(json_of(t, "\{\"perf\": \{\"lanes\": [\"native\", \"jit\", \"aot\"], \"kernels\": \{\"sieve\": \{\"native\": \{\"time\": 1.0\}, \"ours\": \{\"jit\": \{\"time\": 1.0\}, \"aot\": \{\"time\": 8.0\}\}, \"rust\": \{\"status\": \"ran\", \"lanes\": \{\"aot\": \{\"time\": 8.0\}\}\}\}, \"fib_loop\": \{\"native\": \{\"time\": 1.0\}, \"ours\": \{\"aot\": \{\"time\": 2.0\}\}, \"rust\": \{\"status\": \"ran\", \"lanes\": \{\}\}\}\}\}\}"))
            t |> success(md |> contains("| sieve             |   1.000000 |     1.00 |      n/a | 8.00 (#48) |     8.00 |"), md)
            t |> success(md |> contains("| fib_loop          |   1.000000 |      n/a |      n/a |       2.00 |      n/a |"), md)
            t |> success(md |> contains("\nOurs:\n\n- (#48) daslang's AOT generator"), md)
            t |> success(md |> ends_with(" runs sieve 1.63 x native: [lookibed/daScript#48](https://github.com/lookibed/daScript/issues/48).\n"), md)
            t |> success(!(perf_table(json_of(t, "\{{PERF}\}")) |> contains("#48")))
        }
    }
    t |> run("no kernel: said so") @(t : T?) {
        t |> equal(perf_table(json_of(t, "\{\}")), "No kernel is timed yet.\n")
    }
    t |> run("a cell of spread above 20% is suspect with its spread, a lane over a suspect native one too, both out of the geomean; 20% exactly is a number") @(t : T?) {
        let js = json_of(t, SUSPECT_PERF)
        let md = perf_table(js)
        t |> success(md |> contains("| k1                |          1.000000 | suspect (±21.0%) |             1.00 |"), md)
        t |> success(md |> contains("| k2                | suspect (±21.0%) |  suspect (native) | suspect (native) |"), md)
        t |> success(md |> contains("| k3                |          1.000000 |              4.00 |             2.00 |"), md)
        t |> success(md |> contains("| geomean (kernels) |                   |          4.00 (1) |         2.00 (1) |"), md)
        // the capture's own geomean (over all three) is not what the row shows
        t |> success(!(md |> contains("3.00")), md)
        t |> equal(join(rust_ahead(js), "\n"), "- k3, interpreter: Rust 2.00x native, ours 4.00x.\n- geomean, interpreter: Rust 2.00x native, ours 4.00x over 1 kernels.")
    }
}

[test]
def test_quality(t : T?) {
    t |> run("the size table per group, all last, both ratios") @(t : T?) {
        let md = size_table(json_of(t, "\{{QUALITY}\}"))
        t |> success(md |> contains("| s1    |       1 of 2 |          1 |          2 |         10 |         30 |           25 |                    5 |        3.00 |                   0.50 |"), md)
        t |> success(find(md, "| s1 ") < find(md, "| all "), md)
    }
    t |> run("the counters over all keys, every metric a row") @(t : T?) {
        let md = counters_table(json_of(t, "\{{QUALITY}\}"))
        t |> success(md |> contains("| goto               |    3 |    1 |"), md)
        t |> success(md |> contains("| c_function         |    0 |    0 |"), md)
    }
    t |> run("the keys left out, per group") @(t : T?) {
        t |> equal(join(excluded_lines(json_of(t, "\{{QUALITY}\}")), "\n"), "- s1: rust_compile 1")
    }
    t |> run("a function side by side, a side without it said so") @(t : T?) {
        let text = side_by_side(json_of(t, "\{{QUALITY}\}"))
        t |> equal(text, "#### `s1/a`: `f`\n\nOurs:\n\n```das\ndef f \{\n\}\n```\n\nRust: not found in this side's module.\n\n")
    }
    t |> run("no quality section: each table says so") @(t : T?) {
        let empty_capture = json_of(t, "\{\}")
        t |> equal(size_table(empty_capture), "No quality section is captured yet.\n")
        t |> equal(counters_table(empty_capture), "No quality section is captured yet.\n")
        t |> equal(side_by_side(empty_capture), "No function is sampled yet.\n")
        t |> equal(length(excluded_lines(empty_capture)), 0)
    }
}

[test]
def test_lua(t : T?) {
    t |> run("refused: the cause, the gap, Doom pending") @(t : T?) {
        let text = lua_text(json_of(t, "\{{LUA}\}"))
        t |> success(text |> contains("refuses `lua` (3 units, `--libc std`): `unsupported external call: ldexp`"), text)
        t |> success(text |> contains("lowers in no mode (2): `ldexp`, `clock`. "), text)
        t |> success(text |> ends_with("\nDoom: pending (P6).\n"), text)
    }
    t |> run("translated, the gap not computed") @(t : T?) {
        let text = lua_text(json_of(t, "\{\"lua\": \{\"program\": \"lua\", \"units\": 3, \"status\": \"translated\", \"files\": 4, \"speed\": \"not measured here\", \"gap\": [], \"gap_error\": \"no nm\"\}\}"))
        t |> success(text |> contains("writes `lua` (3 units) as 4 files; speed: not measured here. The gap was not computed: no nm. "), text)
    }
    t |> run("translated with an empty gap") @(t : T?) {
        let text = lua_text(json_of(t, "\{\"lua\": \{\"status\": \"translated\", \"gap\": [], \"gap_error\": \"\"\}\}"))
        t |> success(text |> contains("lowers in no mode (0): none. "), text)
    }
    t |> run("neither run: said so") @(t : T?) {
        t |> equal(lua_text(json_of(t, "\{\}")), "Lua: not run yet.\n\nDoom: not run yet.\n")
    }
}

[test]
def test_rust_ahead(t : T?) {
    t |> run("each rule fires on the capture") @(t : T?) {
        let lines <- rust_ahead(json_of(t, full_capture()))
        t |> equal(join(lines, "\n"), "- s1: Rust passes 2 of 9 ids, our ratchet 1; of the Rust passes 1 are ids we skip and 0 ids our ratchet does not list.\n- k1, interpreter: Rust 1.00x native, ours 2.00x.\n- k1, JIT: Rust 3.00x native, ours has no cell (differs).\n- geomean, interpreter: Rust 1.00x native, ours 2.00x over 1 kernels.\n- counter `goto`: Rust 1, ours 3 over all keys.\n- lines without the Rust runtime: Rust 5, ours 10.")
    }
    t |> run("negative controls: equal or higher Rust values, a shown tie, a lane without a Rust cell") @(t : T?) {
        let cap = "\{\"suites\": \{{SUITE2}\}, \"perf\": \{\"lanes\": [\"native\", \"interp\", \"jit\"], \"kernels\": \{
\"k\": \{\"native\": \{\"time\": 1.0\}, \"ours\": \{\"interp\": \{\"time\": 1.001\}, \"jit\": \{\"time\": 1.0\}\}, \"rust\": \{\"status\": \"ran\", \"lanes\": \{\"interp\": \{\"time\": 1.0\}, \"jit\": \{\"error\": \"a sample took longer than 120 s\"\}\}\}\}\},
\"geomean\": \{\"interp\": \{\"ours\": 1.001, \"rust\": 1.0, \"kernels\": 1\}, \"jit\": \{\"ours\": 2.0, \"rust\": 1.0, \"kernels\": 0\}\}\},
\"quality\": \{\"totals\": \{\"all\": \{\"ours\": \{\"lines\": 5, \"goto\": 1\}, \"rust\": \{\"lines\": 9, \"runtime_lines\": 4, \"goto\": 1\}\}\}\}\}"
        t |> equal(length(rust_ahead(json_of(t, cap))), 0)
    }
    t |> run("the margin: ours more than 5% above and above both spreads is ahead, 5% or less, or within a spread, is not") @(t : T?) {
        t |> success(ahead_by_margin(1.0lf, 1.06lf))
        t |> success(!ahead_by_margin(1.0lf, 1.04lf))
        t |> success(cell_ahead(1.0lf, 1.06lf, 0.05lf, 0.0lf))
        t |> success(!cell_ahead(1.0lf, 1.06lf, 0.07lf, 0.0lf))
        t |> success(!cell_ahead(1.0lf, 1.06lf, 0.0lf, 0.07lf))
        t |> success(!cell_ahead(1.0lf, 1.04lf, 0.0lf, 0.0lf))
        let cap = "\{\"perf\": \{\"lanes\": [\"native\", \"interp\", \"jit\"], \"kernels\": \{
\"a\": \{\"native\": \{\"time\": 1.0\}, \"ours\": \{\"interp\": \{\"time\": 1.06, \"spread\": 0.01\}, \"jit\": \{\"time\": 1.04\}\}, \"rust\": \{\"status\": \"ran\", \"lanes\": \{\"interp\": \{\"time\": 1.0, \"spread\": 0.02\}, \"jit\": \{\"time\": 1.0\}\}\}\},
\"b\": \{\"native\": \{\"time\": 1.0\}, \"ours\": \{\"interp\": \{\"time\": 1.06, \"spread\": 0.08\}\}, \"rust\": \{\"status\": \"ran\", \"lanes\": \{\"interp\": \{\"time\": 1.0\}\}\}\}\},
\"geomean\": \{\"interp\": \{\"ours\": 1.06, \"rust\": 1.0, \"kernels\": 2\}, \"jit\": \{\"ours\": 1.04, \"rust\": 1.0, \"kernels\": 1\}\}\},
\"quality\": \{\"totals\": \{\"all\": \{\"ours\": \{\"lines\": 104, \"goto\": 106, \"label\": 104\}, \"rust\": \{\"lines\": 120, \"runtime_lines\": 20, \"goto\": 100, \"label\": 100\}\}\}\}\}"
        t |> equal(join(rust_ahead(json_of(t, cap)), "\n"), "- a, interpreter: Rust 1.00x native, ours 1.06x.\n- geomean, interpreter: Rust 1.00x native, ours 1.06x over 2 kernels.\n- counter `goto`: Rust 100, ours 106 over all keys.")
        let lines_cap = "\{\"quality\": \{\"totals\": \{\"all\": \{\"ours\": \{\"lines\": 106\}, \"rust\": \{\"lines\": 120, \"runtime_lines\": 20\}\}\}\}\}"
        t |> equal(join(rust_ahead(json_of(t, lines_cap)), "\n"), "- lines without the Rust runtime: Rust 100, ours 106.")
    }
    t |> run("c_function is not ranked: the Rust side writes no such annotation") @(t : T?) {
        let cap = "\{\"quality\": \{\"totals\": \{\"all\": \{\"ours\": \{\"lines\": 1, \"c_function\": 50, \"label\": 50\}, \"rust\": \{\"lines\": 1, \"c_function\": 0, \"label\": 0\}\}\}\}\}"
        t |> equal(join(rust_ahead(json_of(t, cap)), "\n"), "- counter `label`: Rust 0, ours 50 over all keys.")
    }
    t |> run("our lane without a cell where the Rust side has one") @(t : T?) {
        let cap = "\{\"perf\": \{\"lanes\": [\"native\", \"aot\"], \"kernels\": \{\"k\": \{\"native\": \{\"time\": 1.0\}, \"ours\": \{\"aot\": \{\"error\": \"the build exited 1 and left no binary\"\}\}, \"rust\": \{\"status\": \"ran\", \"lanes\": \{\"aot\": \{\"time\": 2.0\}\}\}\}\}\}\}"
        t |> equal(join(rust_ahead(json_of(t, cap)), "\n"), "- k, AOT: Rust 2.00x native, ours has no cell (compile).")
    }
}

[test]
def test_report(t : T?) {
    t |> run("each section's stamp names its box: a capture with its box, one with its cpu alone, one with neither") @(t : T?) {
        let boxed = compare_report(json_of(t, "\{\"suites\": \{\"s\": \{\"rust_commit\": \"r\", \"date\": \"d\", \"cpu\": \"C\", \"box\": \"bench\"\}\}, \"perf\": \{\"timestamp\": \"t\", \"platform\": \"p\", \"cpu\": \"C\", \"box\": \"bench\"\}, \"quality\": \{\"rust_commit\": \"q\", \"date\": \"d\", \"cpu\": \"C\", \"box\": \"bench\"\}, \"projects\": \{\"w\": \{\"rust_commit\": \"r\", \"date\": \"d\", \"cpu\": \"C\", \"box\": \"bench\"\}\}\}"))
        t |> success(boxed |> contains("Captured: s (Rust `r`, d, bench (C)). "), boxed)
        t |> success(boxed |> contains("Captured t on p, bench (C); "), boxed)
        t |> success(boxed |> contains("Captured Rust `q`, d, bench (C), over every input"), boxed)
        t |> success(boxed |> contains("Captured: w (Rust `r`, d, bench (C))."), boxed)
        let cpu_only = compare_report(json_of(t, "\{\"suites\": \{\"s\": \{\"rust_commit\": \"r\", \"date\": \"d\", \"cpu\": \"AMD FX(tm)-6300 Six-Core Processor\"\}\}, \"perf\": \{\"timestamp\": \"t\", \"platform\": \"p\", \"cpu\": \"Other\"\}\}"))
        t |> success(cpu_only |> contains("Captured: s (Rust `r`, d, fx (AMD FX(tm)-6300 Six-Core Processor)). "), cpu_only)
        t |> success(cpu_only |> contains("Captured t on p, Other; "), cpu_only)
        let neither = compare_report(json_of(t, "\{\"perf\": \{\"timestamp\": \"t\", \"platform\": \"p\"\}, \"quality\": \{\"rust_commit\": \"q\", \"date\": \"d\"\}\}"))
        t |> success(neither |> contains("Captured t on p, unlabelled box; "), neither)
        t |> success(neither |> contains("Captured Rust `q`, d, unlabelled box, over every input"), neither)
    }
    t |> run("the whole report: every section in order, an empty capture rendered without a crash") @(t : T?) {
        let text = compare_report(json_of(t, full_capture()))
        var at = 0
        for (heading in ["### Suites", "### Speed", "Error cells:", "### Readability and size", "Left out of the totals:", "### Functions side by side", "### Lua and Doom", "### Where the Rust translator is ahead"]) {
            let next = find(text, heading)
            t |> success(next > at, "{heading}: {text}")
            at = next
        }
        t |> success(text |> contains("s1 (Rust `abcdef012345`, d1, unlabelled box)"), text)
        let empty_text = compare_report(json_of(t, "\{\}"))
        t |> success(empty_text |> contains("No suite is captured yet."), empty_text)
        t |> success(empty_text |> ends_with("Nowhere in this capture.\n"), empty_text)
        t |> success(!(empty_text |> contains("Error cells:")), empty_text)
    }
}

// `compare/run.das` run in folder `dir` with `args` after `--`; its exit code
def private run_compare_in(dir : string; args : array<string>; var out : string&) : int {
    var argv <- [get_das_root() + "/bin/daslang", "-load_module", get_full_file_name("c_runtime"), "-load_module", get_full_file_name("dasCRuntime"), get_full_file_name("compare/run.das"), "--"]
    argv |> push_from(args)
    return run_and_capture(in_folder(dir, argv), out, 300.0)
}

// a scratch folder holding the capture `results.json`, passed to `body`, removed after it
def private with_scratch(t : T?; name : string; body : block<(dir : string) : void>) {
    var dir_error : string
    let dir = create_temp_directory(name, dir_error)
    if (!empty(dir_error)) {
        t |> failure("no scratch folder: {dir_error}")
        return
    }
    fwrite(path_join(dir, "results.json"), full_capture())
    invoke(body, dir)
    rmdir_rec(dir)
}

[test]
def test_command_line(t : T?) {
    t |> run("--readme replaces the block between the markers and keeps the text around it") @(t : T?) {
        t |> with_scratch("cmp_render_readme") $(dir) {
            mkdir_rec(path_join(dir, "docs"))
            let readme = path_join(dir, "docs/rust-comparison.md")
            fwrite(readme, "# top\n\ncharter\n\n{COMPARE_BEGIN}\nstale\n{COMPARE_END}\n\ntail\n")
            var out : string
            t |> equal(run_compare_in(dir, ["--readme", "--out", "results.json"], out), 0, out)
            let text = fread(readme)
            t |> success(text |> starts_with("# top\n\ncharter\n\n{COMPARE_BEGIN}\nRendered from "), text)
            t |> success(!(text |> contains("stale")), text)
            t |> success(text |> ends_with("{COMPARE_END}\n\ntail\n"), text)
        }
    }
    t |> run("--readme refuses a document without the markers and leaves it") @(t : T?) {
        t |> with_scratch("cmp_render_nomarkers") $(dir) {
            mkdir_rec(path_join(dir, "docs"))
            let readme = path_join(dir, "docs/rust-comparison.md")
            fwrite(readme, "# top\n")
            var out : string
            t |> equal(run_compare_in(dir, ["--readme", "--out", "results.json"], out), 1, out)
            t |> success(out |> contains("docs/rust-comparison.md has no compare markers"), out)
            t |> equal(fread(readme), "# top\n")
        }
    }
    t |> run("--report writes the open rulings, then the comparison; without the rulings file none") @(t : T?) {
        t |> with_scratch("cmp_render_report") $(dir) {
            var out : string
            t |> equal(run_compare_in(dir, ["--report", "plain.md", "--out", "results.json"], out), 0, out)
            let plain = fread(path_join(dir, "plain.md"))
            t |> success(plain |> starts_with("# c2das-re against the Rust translator\n\n## Head-to-head\n\nRendered from "), plain)
            mkdir_rec(path_join(dir, "docs"))
            fwrite(path_join(dir, "docs/rulings-pending.md"), "# Rulings pending\n\nintro\n\n- P8.1: a question; 2026-11-01.\n")
            t |> equal(run_compare_in(dir, ["--report", "ruled.md", "--out", "results.json"], out), 0, out)
            let ruled = fread(path_join(dir, "ruled.md"))
            t |> success(ruled |> starts_with("# c2das-re against the Rust translator\n\n## Rulings pending\n\n- P8.1: a question; 2026-11-01.\n\n## Head-to-head\n\n"), ruled)
        }
    }
    t |> run("an unreadable capture, the rendering beside another mode, and an unknown --box are refused") @(t : T?) {
        t |> with_scratch("cmp_render_refused") $(dir) {
            var out : string
            t |> equal(run_compare_in(dir, ["--report", "r.md", "--out", "missing.json"], out), 1, out)
            t |> success(!fexist(path_join(dir, "r.md")), out)
            t |> equal(run_compare_in(dir, ["--readme", "--perf", "--out", "results.json"], out), 1, out)
            t |> success(out |> contains("runs alone"), out)
            t |> equal(run_compare_in(dir, ["--readme", "--box", "laptop", "--out", "results.json"], out), 1, out)
            t |> success(out |> contains("--box takes bench, PC, fx, not `laptop`"), out)
            let own = box_of(cpu_name())
            if (!empty(own)) {
                let other = own == "bench" ? "fx" : "bench"
                t |> equal(run_compare_in(dir, ["--readme", "--box", other, "--out", "results.json"], out), 1, out)
                t |> success(out |> contains("--box {other} names another box than this CPU's"), out)
            }
        }
    }
}
