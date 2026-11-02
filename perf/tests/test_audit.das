options gen2
// the pipeline parses clang's JSON dump below its own frames
options stack = 1048576
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require daslib/json_boost
require ../../converter/pipeline.das
require ../../converter/tiers.das
require ../../suites/suite_files.das
require ../perf_compose.das
require ../audit_constructs.das
require ../audit_tables.das

// fixtures spell JSON quotes as single quotes
def capture_of(t : T?; text : string) : JsonValue? {
    var error : string
    var js = read_json(replace(text, "'", "\""), error)
    t |> equal(error, "", "fixture is JSON")
    return js
}

def scratch(t : T?) : string {
    var error : string
    let dir = create_temp_directory("c2das_audit", error)
    t |> equal(error, "", "a temp directory")
    return dir
}

[test]
def test_rewrites(t : T?) {
    t |> run("if_chain: a case no goto enters tests the value alone; a goto target keeps its flag") @(t : T?) {
        let text = join(["    _flag ||= _goto == 0 && _cond == 3", "    if (_flag) \{", "        a()", "    _flag ||= _goto == 0 && _cond == 4", "    _flag ||= _goto == 1", "    if (_flag) \{"], "\n")
        var error : string
        let out = if_chain(text, error)
        t |> equal(error, "")
        t |> equal(out, join(["    if (_goto == 0 && _cond == 3) \{", "        a()", "    _flag ||= _goto == 0 && _cond == 4", "    _flag ||= _goto == 1", "    if (_flag) \{"], "\n"))
    }
    t |> run("if_chain: no flag case is an error") @(t : T?) {
        var error : string
        t |> equal(if_chain("if (x) \{\n\}", error), "")
        t |> success(error |> contains("no `_flag` switch case"), error)
    }
    t |> run("unwrap_addr_deref: each addr(deref(p)) is (p), nested parentheses kept") @(t : T?) {
        var error : string
        t |> equal(unwrap_addr_deref("x = addr(deref(t.node + int(h & (m - 1)))); y = addr(deref(p + addr(deref(q)).n))", error), "x = (t.node + int(h & (m - 1))); y = (p + (q).n)")
        t |> equal(error, "")
    }
    t |> run("unwrap_addr_deref: none, or one not closed by addr's own parenthesis, is an error") @(t : T?) {
        var error : string
        t |> equal(unwrap_addr_deref("p + 1", error), "")
        t |> success(error |> contains("no `addr(deref(`"), error)
        error = ""
        t |> equal(unwrap_addr_deref("addr(deref(p).f)", error), "")
        t |> success(error |> contains("unbalanced"), error)
    }
    t |> run("replaced_all stops at the first text it does not find") @(t : T?) {
        var error : string
        t |> equal(replaced_all("a b", [(old = "a", by = "c"), (old = "z", by = "y")], error), "")
        t |> equal(error, "no `z` in the converted module")
        error = ""
        t |> equal(replaced_all("a b a", [(old = "a", by = "c"), (old = "b", by = "d")], error), "c d c")
    }
    t |> run("occurrences") @(t : T?) {
        t |> equal(occurrences("aXbXcX", "X"), 3)
        t |> equal(occurrences("aaaa", "aa"), 2)
        t |> equal(occurrences("abc", "z"), 0)
    }
}

[test]
def test_rewrites_apply_to_the_kernels(t : T?) {
    let dir = scratch(t)
    for (name in c_file_ids(AUDIT_KERNELS, "")) {
        t |> run("{name} converts and each of its constructs rewrites it") @(t : T?) {
            let work = path_join(dir, name)
            let c_path = write_method_composed(AUDIT_KERNELS, name, work)
            let res <- convert(c_path, work, "linux")
            t |> success(res.ok, res.error)
            let text = fread(res.das_path)
            var taken = 0
            for (c in constructs()) {
                if (c.kernel == name) {
                    var error : string
                    let out = invoke(c.rewrite, text, error)
                    t |> equal(error, "", "{c.spelling}")
                    t |> success(!empty(out) && out != text, "{c.spelling} changes the module")
                    t |> success(occurrences(text, c.sites) > 0, "{c.spelling}: the kernel holds the site text `{c.sites}`")
                    taken++
                }
            }
            t |> success(taken > 0, "{name} isolates a construct")
        }
    }
}

[test]
def test_site_counts(t : T?) {
    let dir = scratch(t)
    t |> run("a missing hot module is the error naming it") @(t : T?) {
        let js = site_counts(dir)
        t |> success((js?["error"] ?? "") |> contains("no lvm in"), write_json(js))
    }
    t |> run("the scc fragment is counted before a module of the same stem") @(t : T?) {
        for (stem in HOT_FILES) {
            fwrite(path_join(dir, "{stem}.das"), "addr(deref(p)) addr(deref(q))")
        }
        fwrite(path_join(dir, "lvm.das.inc"), "addr(deref(p))")
        let js = site_counts(dir)
        t |> equal(js?["pointer"]?["lvm"] ?? -1l, 1l)
        t |> equal(js?["pointer"]?["ltable"] ?? -1l, 2l)
        t |> equal(js?["if-chain"]?["lgc"] ?? -1l, 0l)
    }
}

let CAPTURE = "\{'cpu': 'C', 'samples': 5, 'rust_commit': 'R', 'kernels': \{'trap_check': \{'native': \{'time': 0.001\}, 'converted': \{'interp': \{'time': 0.04\}, 'jit': \{'time': 0.002\}\}, 'plain-test': \{'interp': \{'time': 0.02\}, 'jit': \{'time': 0.002\}\}, 'plain-load': \{'interp': \{'time': 0.03\}, 'jit': \{'time': 0.00001\}\}, 'rust': \{'status': 'refused', 'error': 'volatile'\}\}, 'dispatch_switch': \{'native': \{'error': 'clang failed'\}\}, 'small_call': \{'native': \{'time': 0.001\}, 'converted': \{'error': 'convert: boom'\}, 'rust': \{'status': 'ran', 'interp': \{'time': 0.05\}\}\}\}, 'sites': \{'plain-test': \{'lvm': 61, 'ltable': 8, 'lgc': 2, 'ldo': 37\}\}\}"

// the row of the markdown table `text` whose first cell is `name`, its cells trimmed
def row_of(text, name : string) : array<string> {
    for (line in split(text, "\n")) {
        if (line |> starts_with("| {name} ")) {
            return <- [for (c in split(line, "|")); strip(c)]
        }
    }
    return <- array<string>()
}

[test]
def test_tables(t : T?) {
    let js = capture_of(t, CAPTURE)
    let rows = construct_table(js)
    t |> run("a construct row: native, the interp factor, the rewrite's cost per tier, Rust, the sites") @(t : T?) {
        let row <- row_of(rows, "`int64(x != 0 ? 1 : 0) != 0` test")
        t |> equal(join(row, "|"), "|`int64(x != 0 ? 1 : 0) != 0` test|trap_check (plain-test)|1000.0 us|40.00x|2.00x|1.00x|refused|61/8/2/37|")
    }
    t |> run("a JIT rewrite under a tenth of native is SUSPECT") @(t : T?) {
        let row <- row_of(rows, "`c_volatile_load` of a volatile field")
        t |> equal(row[6], "SUSPECT 0.010x native")
        t |> equal(row[8], "n/a")
    }
    t |> run("a failed native or conversion is that row's error") @(t : T?) {
        t |> equal(row_of(rows, "`_flag` switch chain")[3], "error: clang failed")
        let call <- row_of(rows, "a call of a small function (`luaH_get*`)")
        t |> equal(call[4], "error: convert: boom")
        t |> equal(call[5], "error: convert: boom")
        t |> equal(call[6], "error: convert: boom")
        t |> equal(call[7], "50.00x")
    }
    t |> run("a construct whose kernel the capture lacks is n/a throughout") @(t : T?) {
        t |> equal(row_of(rows, "`typeinfo sizeof` in a hot loop")[3], "n/a")
    }
    t |> run("no benches key, no bench table; with it, one row per bench measured") @(t : T?) {
        t |> success(!(audit_text(js) |> contains("| bench")), audit_text(js))
        let with_benches = capture_of(t, "\{'benches': \{'startup': \{'arg': '-e print(1)', 'native': 0.01, 'interp-scc': 5.0, 'interp-source': 1.0\}, 'fib': \{'arg': '27', 'native': 1.01, 'interp-scc': 45.0, 'interp-source': \{'error': 'exited 1: x'\}\}, 'nbody': \{'arg': '9', 'native': 0.11, 'interp-scc': 15.0, 'interp-source': 2.0\}\}\}")
        let text = bench_table(with_benches)
        t |> equal(join(row_of(text, "fib"), "|"), "|fib|27|1.010|45.00|error: exited 1: x|40.00x|n/a|n/a|")
        t |> equal(join(row_of(text, "nbody"), "|"), "|nbody|9|0.110|15.00|2.00|native under 1.0 s|native under 1.0 s|0.10x|")
        t |> equal(join(row_of(text, "startup"), "|"), "|startup|-e print(1)|0.010|5.00|1.00|n/a|n/a|n/a|")
        t |> equal(length(row_of(text, "binary_trees")), 0)
        t |> success(audit_text(with_benches) |> contains("| bench"))
        t |> success(audit_text(with_benches) |> contains("resolves to 0.1 s"))
    }
}

[test]
def test_driver(t : T?) {
    let dir = scratch(t)
    t |> run("-? prints the help") @(t : T?) {
        var out : string
        var argv <- daslang_cmd(CONVERTED_MODULES)
        argv |> push_from(["perf/audit_lua.das", "--", "-?"])
        t |> equal(run_and_capture(argv, out, 120.0), 0, out)
        t |> success(out |> contains("leave the whole Lua benchmarks out"), out)
    }
    t |> run("one sample of sizeof_scale writes every lane of the kernel, each reproducing native") @(t : T?) {
        let results = path_join(dir, "audit.json")
        var out : string
        var argv <- daslang_cmd(CONVERTED_MODULES)
        argv |> push_from(["perf/audit_lua.das", "--", "--filter", "sizeof", "--samples", "1", "--no-benches", "--lua-work", dir, "--out", results])
        t |> equal(run_and_capture(argv, out, 900.0), 0, out)
        var error : string
        let js = read_json(fread(results), error)
        t |> equal(error, "", out)
        let k = js?["kernels"]?["sizeof_scale"]
        let oracle = k?["native"]?["result"] ?? -1l
        for (lane in ["interp", "jit"]) {
            t |> equal(k?["converted"]?[lane]?["result"] ?? -2l, oracle, "converted/{lane}: {out}")
            t |> equal(k?["literal"]?[lane]?["result"] ?? -2l, oracle, "literal/{lane}: {out}")
        }
        t |> success((js?["sites"]?["error"] ?? "") |> contains("convert Lua first"), out)
        t |> success(out |> contains("| `typeinfo sizeof` in a hot loop"), out)
        t |> success(has_key(js, "kernels") && !has_key(js, "benches"), out)
    }
    t |> run("--table renders a stored capture; a missing one exits 1, as does --benches-only") @(t : T?) {
        let stored = path_join(dir, "stored.json")
        fwrite(stored, replace(CAPTURE, "'", "\""))
        var out : string
        var argv <- daslang_cmd(CONVERTED_MODULES)
        argv |> push_from(["perf/audit_lua.das", "--", "--table", "--out", stored])
        t |> equal(run_and_capture(argv, out, 120.0), 0, out)
        t |> success(out |> contains("| `int64(x != 0 ? 1 : 0) != 0` test"), out)
        var missing <- daslang_cmd(CONVERTED_MODULES)
        missing |> push_from(["perf/audit_lua.das", "--", "--table", "--out", path_join(dir, "none.json")])
        t |> equal(run_and_capture(missing, out, 120.0), 1, out)
        var benches <- daslang_cmd(CONVERTED_MODULES)
        benches |> push_from(["perf/audit_lua.das", "--", "--benches-only", "--out", path_join(dir, "none.json")])
        t |> equal(run_and_capture(benches, out, 120.0), 1, out)
        t |> success(out |> contains("--benches-only needs a stored capture"), out)
    }
}
