options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require ../readability_count.das
require ../readability_file.das
require ../readability_inputs.das
require ../../suites/suite_files.das
require ../../converter/tiers.das

let FIXTURES = "metrics/tests/fixtures"

def private lines_of(mc : ModuleCount; metric : string) : array<int> => <- [for (s in mc.sites); s.line; where s.metric == metric]

def private expect_counts(t : T?; mc : ModuleCount; want : table<string; int>) {
    t |> equal(mc.error, "")
    for (m in METRICS) {
        t |> equal(mc.counts?[m] ?? -1, want?[m] ?? 0, m)
    }
}

[test]
def test_pointer_counts(t : T?) {
    t |> run("each pointer, unsafe and reinterpret form counts once, the [c_function] wrap not at all") @(t : T?) {
        let mc <- count_module("{FIXTURES}/pointers.das")
        expect_counts(t, mc, {"c_function" => 1, "unsafe_block" => 1, "unsafe_expr" => 7, "pointer_arith" => 5, "pointer_index" => 5, "reinterpret" => 2})
    }
    t |> run("an index is deref of a step or [] on a pointer, and its step is no arithmetic site") @(t : T?) {
        let mc <- count_module("{FIXTURES}/pointers.das")
        t |> equal(lines_of(mc, "pointer_index"), [13, 13, 13, 17, 24])
        t |> equal(lines_of(mc, "pointer_arith"), [7, 14, 15, 16, 19])
    }
    t |> run("a global initializer's unsafe(...) counts, an unsafe(p + i) the inference unflags among them") @(t : T?) {
        let mc <- count_module("{FIXTURES}/pointers.das")
        t |> equal(lines_of(mc, "unsafe_expr"), [6, 7, 7, 37, 28, 33, 39])
    }
    t |> run("an unused global and an unused private function count: the compile keeps them") @(t : T?) {
        let mc <- count_module("{FIXTURES}/pointers.das")
        t |> equal(lines_of(mc, "reinterpret"), [18, 39])
    }
}

[test]
def test_cluster_counts(t : T?) {
    t |> run("a cluster module counts its own text, and with its fragments named their text too") @(t : T?) {
        let own <- count_module("{FIXTURES}/cluster/cluster.das")
        expect_counts(t, own, {"unsafe_expr" => 2, "reinterpret" => 1})
        let whole <- count_module("{FIXTURES}/cluster/cluster.das", ["{FIXTURES}/cluster/part.das.inc"])
        expect_counts(t, whole, {"c_function" => 1, "unsafe_expr" => 2, "reinterpret" => 1, "pointer_index" => 2})
    }
    t |> run("a program's modules summed, each with the fragments its include lines name, not its layout file") @(t : T?) {
        var failed : string
        let program <- count_program(["{FIXTURES}/cluster/cluster.das", "{FIXTURES}/pointers.das"], failed)
        let pointers <- count_module("{FIXTURES}/pointers.das")
        t |> equal(failed, "")
        t |> equal(program.error, "")
        t |> equal(program.counts?["pointer_index"] ?? -1, 2 + (pointers.counts?["pointer_index"] ?? 0))
        t |> equal(program.counts?["reinterpret"] ?? -1, 1 + (pointers.counts?["reinterpret"] ?? 0))
    }
}

[test]
def test_generated_counts(t : T?) {
    t |> run("generated functions and macro wraps uncounted, one instance per generic, an uncalled generic as written") @(t : T?) {
        let mc <- count_module("{FIXTURES}/generated.das")
        expect_counts(t, mc, {"c_function" => 1, "pointer_arith" => 1, "unsafe_expr" => 2, "reinterpret" => 2, "unsafe_block" => 1})
        t |> equal(lines_of(mc, "reinterpret"), [25, 21])
        t |> equal(lines_of(mc, "unsafe_expr"), [21, 35])
    }
}

[test]
def test_loop_counts(t : T?) {
    t |> run("the rangeable loops, the finally shape with its continue among them, and none of the others") @(t : T?) {
        let mc <- count_module("{FIXTURES}/loops.das")
        expect_counts(t, mc, {"while_rangeable" => 6, "goto" => 1, "label" => 2, "unsafe_expr" => 2})
        t |> equal(lines_of(mc, "while_rangeable"), [8, 13, 24, 29, 33, 230])
    }
}

[test]
def test_literal_counts(t : T?) {
    t |> run("every integer width matches an enumerator or a let constant, a generic instance from elsewhere uncounted") @(t : T?) {
        let mc <- count_module("{FIXTURES}/literals.das")
        expect_counts(t, mc, {"literal_named" => 8})
    }
    t |> run("a site names the first name of its value, an implicit enumerator's included") @(t : T?) {
        let mc <- count_module("{FIXTURES}/literals.das")
        let names <- [for (s in mc.sites); "{s.line} {s.suggested_name}"]
        t |> equal(names, ["17 ALSO_SEVEN", "18 Color.BLUE", "19 LIMIT", "20 ALSO_SEVEN", "21 Color.BLUE", "22 LIMIT", "23 ALSO_SEVEN", "24 Color.NEGATIVE"])
    }
}

[test]
def test_call_macro_counts(t : T?) {
    t |> run("a c_runtime call macro's expansion adds no site, its literal argument counts once, a spelled reinterpret beside it counts") @(t : T?) {
        let mc <- count_module("{FIXTURES}/call_macros.das")
        expect_counts(t, mc, {"reinterpret" => 1, "unsafe_expr" => 1, "goto" => 1, "label" => 1, "literal_named" => 1})
        let sites <- [for (s in mc.sites); "{s.line} {s.metric} {s.suggested_name}"]
        t |> equal(sites, ["24 label ", "28 goto ", "30 unsafe_expr ", "30 reinterpret ", "31 literal_named Color.GREEN"])
    }
}

[test]
def test_named_counts(t : T?) {
    t |> run("an unwritten var global names its value, a written one does not, a folded literal whose text is not its value and the dialect init do not count") @(t : T?) {
        let mc <- count_module("{FIXTURES}/named.das")
        expect_counts(t, mc, {"literal_named" => 3})
        let names <- [for (s in mc.sites); "{s.line} {s.suggested_name}"]
        t |> equal(names, ["25 cn__LIMIT", "26 BIG", "30 Mode.EIGHT"])
    }
}

[test]
def test_spelled_number(t : T?) {
    t |> run("a number after casts, signed or hex") @(t : T?) {
        var v = 0l
        t |> success(spelled_number("int8(7))", v))
        t |> equal(v, 7l)
        t |> success(spelled_number("-12 + x", v))
        t |> equal(v, -12l)
        t |> success(spelled_number("0x1F)", v))
        t |> equal(v, 31l)
        t |> success(spelled_number("uint(int64(5))", v))
        t |> equal(v, 5l)
        t |> success(spelled_number("5 + 7", v))
        t |> equal(v, 5l)
    }
    t |> run("no digit after the casts and the sign is no number") @(t : T?) {
        var v = 0l
        t |> success(!spelled_number("-int(E.A)", v))
        t |> success(!spelled_number("int(E.A)", v))
        t |> success(!spelled_number("", v))
    }
}

[test]
def test_inside_unsafe_call(t : T?) {
    t |> run("the nearest open parenthesis follows the word unsafe") @(t : T?) {
        t |> success(inside_unsafe_call("var gp = unsafe(unsafe(addr(arr[0])) + 3)", 37))
        t |> success(inside_unsafe_call("unsafe(p + 1)", 9))
    }
    t |> run("another call, a longer word or no parenthesis") @(t : T?) {
        t |> success(!inside_unsafe_call("x = deref(p + i)", 12))
        t |> success(!inside_unsafe_call("x = notunsafe(p + 1)", 16))
        t |> success(!inside_unsafe_call("x = p + 1", 6))
    }
}

[test]
def test_compile_failure(t : T?) {
    var dir_error : string
    let dir = create_temp_directory("c2das_readability", dir_error)
    t |> equal(dir_error, "")
    let path = path_join(dir, "broken.das")
    fwrite(path, "options gen2\n\ndef f : int \{\n    return missing\n\}\n")
    t |> run("a module that does not compile is an error with the compiler's words") @(t : T?) {
        let mc <- count_module(path)
        t |> success(mc.error |> contains("missing"), mc.error)
    }
    rmdir_rec(dir)
}

[test]
def test_count_text(t : T?) {
    t |> run("the worker file reads back as written") @(t : T?) {
        var mc : ModuleCount
        mc.counts <- {for (m in METRICS); m => 0}
        mc.counts["goto"] = 3
        mc.sites <- [Site(metric = "literal_named", line = 7, suggested_name = "Color.GREEN"), Site(metric = "goto", line = 9)]
        let back <- read_count_text(count_text(mc))
        t |> equal(back.error, "")
        t |> equal(back.counts?["goto"] ?? -1, 3)
        t |> equal(back.counts?["label"] ?? -1, 0)
        t |> equal(length(back.sites), 2)
        t |> equal(back.sites[0].suggested_name, "Color.GREEN")
        t |> equal(back.sites[1].suggested_name, "")
        t |> equal(back.sites[1].line, 9)
    }
    t |> run("an error keeps its first line") @(t : T?) {
        let back <- read_count_text(count_text(ModuleCount(error = "convert: no\nmore")))
        t |> equal(back.error, "convert: no more")
    }
    t |> run("a text with no status line is an error") @(t : T?) {
        t |> equal(read_count_text("").error, "no counts")
        t |> equal(read_count_text("goto 3\n").error, "no counts")
    }
}

def private sample_capture : Capture {
    var cap : Capture
    cap.inputs <- {for (g in INPUT_GROUPS); g => 0}
    cap.inputs["perf"] = 2
    cap.modules["perf/b"] <- {"goto" => 2, "label" => 1}
    cap.modules["perf/a"] <- {"goto" => 1}
    return <- cap
}

[test]
def test_capture_text(t : T?) {
    let text = capture_text(sample_capture())
    t |> run("keys sorted, two-space indent, one module per line, totals summed") @(t : T?) {
        t |> success(text |> starts_with("\{\n  \"inputs\": \{\n    \"c_testsuite\": 0,\n    \"csmith\": 0,\n    \"gcc_torture\": 0,\n    \"lua\": 0,\n    \"perf\": 2\n  \},\n  \"modules\": \{\n    \"perf/a\": \{\"c_function\": 0, \"goto\": 1,"), text)
        t |> success(find(text, "\"perf/a\"") < find(text, "\"perf/b\""), text)
        t |> success(text |> contains("  \"totals\": \{\n    \"c_function\": 0,\n    \"goto\": 3,\n    \"label\": 1,"), text)
        t |> success(text |> ends_with("\n  \}\n\}\n"), text)
    }
    t |> run("the text is a capture the shape check passes") @(t : T?) {
        t |> equal(check_capture(text), array<string>())
    }
    t |> run("an empty capture writes an empty modules object") @(t : T?) {
        let empty_cap : Capture
        t |> success(capture_text(empty_cap) |> contains("\"modules\": \{\},"))
    }
    t |> run("the text reads back") @(t : T?) {
        var error : string
        let back <- read_capture(text, error)
        t |> equal(error, "")
        t |> equal(back.inputs?["perf"] ?? -1, 2)
        t |> equal(length(back.modules), 2)
        t |> equal(totals_of(back.modules)?["goto"] ?? -1, 3)
    }
    t |> run("a text that is not JSON reads as an error") @(t : T?) {
        var error : string
        let back <- read_capture("not json", error)
        t |> success(!empty(error))
        t |> equal(length(back.modules), 0)
    }
}

def private findings_of(text : string) : string => join(check_capture(text), "\n")

[test]
def test_check_capture(t : T?) {
    let good = capture_text(sample_capture())
    t |> run("not a JSON object") @(t : T?) {
        t |> success(findings_of("[1]") |> contains("not a JSON object"))
    }
    t |> run("an unknown top-level key") @(t : T?) {
        t |> success(findings_of(replace(good, "\"inputs\":", "\"extra\": 1,\n  \"inputs\":")) |> contains("unknown top-level key `extra`"))
    }
    t |> run("an object that is not one") @(t : T?) {
        t |> success(findings_of(replace(good, "\"modules\": \{", "\"modules\": [], \"x\": \{")) |> contains("modules is not an object"))
        let no_inputs = "\{\"inputs\": 3, \"modules\": \{\}, \"totals\": \{\}\}"
        t |> success(findings_of(no_inputs) |> contains("inputs is not an object"))
    }
    t |> run("a count that is negative, fractional or not a number, an unknown key, a missing one") @(t : T?) {
        t |> success(findings_of(replace(good, "\"goto\": 2", "\"goto\": -2")) |> contains("modules.perf/b.goto is not a non-negative integer"))
        t |> success(findings_of(replace(good, "\"goto\": 2", "\"goto\": 2.5")) |> contains("modules.perf/b.goto is not a non-negative integer"))
        t |> success(findings_of(replace(good, "\"goto\": 2", "\"goto\": \"2\"")) |> contains("modules.perf/b.goto is not a non-negative integer"))
        t |> success(findings_of(replace(good, "\"perf\": 2", "\"perf\": 2,\n    \"zz\": 0")) |> contains("inputs has the unknown key `zz`"))
        t |> success(findings_of(replace(good, "    \"perf\": 2\n", "    \"zz\": 2\n")) |> contains("inputs lacks `perf`"))
    }
    t |> run("modules out of order or a changed indent is not the writer's spelling") @(t : T?) {
        let swapped = replace(replace(replace(good, "\"perf/a\"", "\"perf/x\""), "\"perf/b\"", "\"perf/a\""), "\"perf/x\"", "\"perf/b\"")
        t |> success(findings_of(swapped) |> contains("not the writer's spelling"), findings_of(swapped))
        t |> success(findings_of(replace(good, "  \"inputs\"", "   \"inputs\"")) |> contains("not the writer's spelling"))
    }
    t |> run("a total that is not the modules' sum, an input count that is not the group's") @(t : T?) {
        t |> success(findings_of(replace(good, "\"goto\": 3", "\"goto\": 4")) |> contains("totals.goto is 4, the modules sum to 3"))
        t |> success(findings_of(replace(good, "\"perf\": 2", "\"perf\": 5")) |> contains("inputs.perf is 5, the modules hold 2"))
    }
    t |> run("a module outside every input group") @(t : T?) {
        let stray = replace(good, "\"perf/a\":", "\"doom/a\": \{\"c_function\": 0, \"goto\": 0, \"label\": 0, \"literal_named\": 0, \"pointer_arith\": 0, \"pointer_index\": 0, \"reinterpret\": 0, \"unsafe_block\": 0, \"unsafe_expr\": 0, \"while_rangeable\": 0\},\n    \"perf/a\":")
        t |> success(findings_of(stray) |> contains("modules: `doom/a` names no input group"), findings_of(stray))
    }
}

[test]
def test_check_input_keys(t : T?) {
    let good = capture_text(sample_capture())
    t |> run("the capture holds exactly the listed input keys") @(t : T?) {
        t |> equal(check_input_keys(good, ["perf/a", "perf/b"]), array<string>())
    }
    t |> run("a listed key the capture lacks, a captured key no ratchet lists") @(t : T?) {
        t |> equal(join(check_input_keys(good, ["perf/a", "perf/b", "perf/c"]), "\n"), "`perf/c` is listed, but the capture lacks it: re-record with scripts/run_readability.sh --update")
        t |> equal(join(check_input_keys(good, ["perf/a"]), "\n"), "`perf/b` is in the capture, but no ratchet lists it")
    }
}

[test]
def test_ratchet_decisions(t : T?) {
    t |> run("the committed column sums the measured modules, a new one from zero") @(t : T?) {
        let committed <- committed_totals(sample_capture(), ["perf/b", "perf/new"])
        t |> equal(committed?["goto"] ?? -1, 2)
        t |> equal(committed?["label"] ?? -1, 1)
    }
    t |> run("an update is refused under --filter or a failed input, honoured otherwise") @(t : T?) {
        t |> equal(update_refusal(false, true, true), "")
        t |> equal(update_refusal(true, false, false), "")
        t |> equal(update_refusal(true, true, false), "a --filter run never records")
        t |> equal(update_refusal(true, false, true), "a run with a failed input never records")
    }
    t |> run("the exit code: a failure, a refusal, or a raise without --update") @(t : T?) {
        t |> equal(run_exit_code(false, false, false, false), 0)
        t |> equal(run_exit_code(false, false, true, true), 0)
        t |> equal(run_exit_code(false, false, true, false), 1)
        t |> equal(run_exit_code(true, false, false, false), 1)
        t |> equal(run_exit_code(false, true, false, true), 1)
    }
}

[test]
def test_totals_table(t : T?) {
    t |> run("a raised total is named, a lowered or equal one not") @(t : T?) {
        let committed <- {"goto" => 3, "label" => 2}
        let now <- {"goto" => 4, "label" => 1}
        t |> equal(raised_metrics(committed, now), ["goto"])
        t |> equal(raised_metrics(now, committed), ["label"])
    }
    t |> run("the table holds committed, now and the signed delta per metric") @(t : T?) {
        let table_text = render_totals({"goto" => 3, "label" => 2}, {"goto" => 4, "label" => 1})
        t |> success(table_text |> contains("| goto "), table_text)
        t |> success(table_text |> contains("|         3 |   4 |    +1 |"), table_text)
        t |> success(table_text |> contains("|         2 |   1 |    -1 |"), table_text)
        t |> success(table_text |> contains("|         0 |   0 |     0 |"), table_text)
    }
}

[test]
def test_group_of(t : T?) {
    t |> run("an input key's group is the text before its first slash") @(t : T?) {
        t |> equal(group_of("csmith/123"), "csmith")
        t |> equal(group_of("bare"), "bare")
    }
}

// the worker run on one input key, and the counts file it wrote
def private run_worker(key : string; var counts : string&) : int {
    var argv <- daslang_cmd(CONVERTED_MODULES)
    argv |> push_from(["metrics/readability.das", "--", "--one", key])
    var out : string
    let rc = run_and_capture(argv, out, 300.0)
    let path = "metrics/work/{key}/counts.txt"
    counts = fexist(path) ? fread(path) : out
    return rc
}

[test]
def test_worker(t : T?) {
    t |> run("--one converts and counts a kernel into its counts file") @(t : T?) {
        var counts : string
        t |> equal(run_worker("perf/fib_loop", counts), 0)
        t |> success(counts |> starts_with("ok\n"), counts)
        t |> success(counts |> contains("\nwhile_rangeable "), counts)
    }
    t |> run("--one converts a kernel's `@copy` key under --param-writes copy, the plain key in place") @(t : T?) {
        var counts : string
        t |> equal(run_worker("perf/blit@copy", counts), 0)
        t |> success(counts |> starts_with("ok\n"), counts)
        let copied = fread("metrics/work/perf/blit@copy/das/blit.das")
        t |> success(copied |> contains("(var src_in : uint8?; var dst_in : uint8?; n_in : int) \{\n    var src = src_in\n"), copied)
        t |> equal(run_worker("perf/blit", counts), 0)
        let in_place = fread("metrics/work/perf/blit/das/blit.das")
        t |> success(in_place |> contains("(var src : uint8?; var dst : uint8?; var n : int) \{\n"), in_place)
    }
    t |> run("--one converts a kernel's `@while` key under --loops while, the plain key with range loops") @(t : T?) {
        var counts : string
        t |> equal(run_worker("perf/primes@while", counts), 0)
        t |> success(counts |> starts_with("ok\n"), counts)
        let kept = fread("metrics/work/perf/primes@while/das/primes.das")
        t |> success(!(kept |> contains(" in range(")), kept)
        t |> equal(run_worker("perf/primes", counts), 0)
        let ranged = fread("metrics/work/perf/primes/das/primes.das")
        t |> success(ranged |> contains("for (i in range(2, n)) \{\n"), ranged)
    }
    t |> run("--one converts a kernel's `@reinterpret` key under --first-member reinterpret, the plain key with addr") @(t : T?) {
        var counts : string
        t |> equal(run_worker("perf/first_member@reinterpret", counts), 0)
        // the format literal's `cstr("...")` expands to a reinterpret its text does not spell
        // `s2v`, `gco2t` and `gco2cl` fold into defs (P9.20): each def's body holds its reinterpret once
        t |> success(counts |> contains("\nreinterpret 5\n"), counts)
        let reinterpreted = fread("metrics/work/perf/first_member@reinterpret/das/first_member.das")
        t |> success(reinterpreted |> contains("def private s2v(var o) : TValue? => reinterpret<TValue?>(o)\n"), reinterpreted)
        t |> success(reinterpreted |> contains("var v : TValue? = s2v(base + a)\n"), reinterpreted)
        t |> equal(run_worker("perf/first_member", counts), 0)
        t |> success(counts |> contains("\nreinterpret 4\n"), counts)
        let kept = fread("metrics/work/perf/first_member/das/first_member.das")
        t |> success(kept |> contains("def private s2v(var o) : TValue? => addr(o.val)\n"), kept)
        t |> success(kept |> contains("var v : TValue? = s2v(base + a)\n"), kept)
    }
    t |> run("--one converts a kernel's `@inline` key under --inline-helpers, the plain key with the helper's calls") @(t : T?) {
        var counts : string
        t |> equal(run_worker("perf/fixed_mandel@inline", counts), 0)
        t |> success(counts |> starts_with("ok\n"), counts)
        let inlined = fread("metrics/work/perf/fixed_mandel@inline/das/fixed_mandel.das")
        t |> success(!(inlined |> contains("fmul(z.x, z.x)")) && inlined |> contains("int((int64(z.x) * int64(z.x)) >> 16l)"), inlined)
        t |> equal(run_worker("perf/fixed_mandel", counts), 0)
        let kept = fread("metrics/work/perf/fixed_mandel/das/fixed_mandel.das")
        t |> success(kept |> contains("fmul(z.x, z.x)"), kept)
    }
    t |> run("a Lua key's `@inline` names the source layout under --inline-helpers") @(t : T?) {
        var layout : string
        t |> equal(lua_key_parts("lua/luac@inline", layout), "luac")
        t |> equal(layout, "source")
        t |> equal(lua_key_parts("lua/luac@single", layout), "luac")
        t |> equal(layout, "single")
        t |> equal(lua_key_parts("lua/lua@goto", layout), "lua")
        t |> equal(layout, "source")
    }
    t |> run("an input that does not convert, and a seed csmith refuses, are errors") @(t : T?) {
        var counts : string
        t |> equal(run_worker("c_testsuite/no_such_test", counts), 0)
        t |> success(counts |> starts_with("error convert: "), counts)
        t |> equal(run_worker("csmith/not-a-seed", counts), 0)
        t |> success(counts |> starts_with("error csmith refused the seed"), counts)
    }
}

// P7.0t: the `@goto` keys under `--switch-dispatch goto`
[test]
def test_worker_goto(t : T?) {
    t |> run("--one converts a Lua `@goto` key under --switch-dispatch goto in the source layout: lstrlib's match is flat") @(t : T?) {
        var counts : string
        t |> equal(run_worker("lua/lua@goto", counts), 0)
        t |> success(counts |> starts_with("ok\n"), counts)
        let lstrlib = fread("metrics/work/lua/lua@goto/das/lstrlib.das")
        t |> success(!(lstrlib |> contains("re-dispatch")) && lstrlib |> contains("  // case 36\n"), lstrlib)
    }
    t |> run("--one converts a kernel's `@goto` key under --switch-dispatch goto: switch_goto's cases are labels, the plain key's the re-dispatch loop") @(t : T?) {
        var counts : string
        t |> equal(run_worker("perf/switch_goto@goto", counts), 0)
        let flat = fread("metrics/work/perf/switch_goto@goto/das/switch_goto.das")
        t |> success(flat |> contains("        goto _cond + 4\n") && !(flat |> contains("re-dispatch")), flat)
        t |> equal(run_worker("perf/switch_goto", counts), 0)
        let kept = fread("metrics/work/perf/switch_goto/das/switch_goto.das")
        t |> success(kept |> contains("label 4:  // re-dispatch\n"), kept)
    }
}

// ruling 36 section 2: the `@checks-off` and `@past-end-inline` keys under `--checks off` and
// `--past-end inline`
[test]
def test_worker_checks_past_end(t : T?) {
    t |> run("--one converts a kernel's `@checks-off` key under --checks off, the plain key with das's checks") @(t : T?) {
        var counts : string
        t |> equal(run_worker("perf/first_member@checks-off", counts), 0)
        t |> success(counts |> starts_with("ok\n"), counts)
        let unchecked = fread("metrics/work/perf/first_member@checks-off/das/first_member.das")
        t |> success(unchecked |> contains("[c_function, unsafe_deref, hint(unsafe_range_check)]\n"), unchecked)
        t |> equal(run_worker("perf/first_member", counts), 0)
        let kept = fread("metrics/work/perf/first_member/das/first_member.das")
        t |> success(!(kept |> contains("unsafe_deref")), kept)
    }
    t |> run("--one converts a Lua `@checks-off` key under --checks off in the source layout") @(t : T?) {
        var counts : string
        t |> equal(run_worker("lua/luac@checks-off", counts), 0)
        t |> success(counts |> starts_with("ok\n"), counts)
        let lapi = fread("metrics/work/lua/luac@checks-off/das/lapi.das")
        t |> success(lapi |> contains("[c_function, unsafe_deref, hint(unsafe_range_check)]\n"), lapi)
    }
    t |> run("a key's suffix names its --checks and --past-end values, else the defaults") @(t : T?) {
        t |> equal(checks_of("perf/blit@checks-off"), "off")
        t |> equal(checks_of("lua/lua@past-end-inline"), "")
        t |> equal(past_end_of("lua/lua@past-end-inline"), "inline")
        t |> equal(past_end_of("perf/blit@inline"), "")
        var layout : string
        t |> equal(lua_key_parts("lua/lua@checks-off", layout), "lua")
        t |> equal(layout, "source")
        layout = ""
        t |> equal(lua_key_parts("lua/luac@past-end-inline", layout), "luac")
        t |> equal(layout, "source")
        t |> equal(kernel_of_key("blit@past-end-inline"), "blit")
        t |> equal(kernel_of_key("blit@checks-off"), "blit")
    }
}

// ruling 38 addendum 14: the `@fn-macros-expand` keys under `--fn-macros expand`
[test]
def test_worker_fn_macros(t : T?) {
    t |> run("--one converts a Lua `@fn-macros-expand` key under --fn-macros expand in the source layout: no macro's def, where the plain key folds") @(t : T?) {
        var counts : string
        t |> equal(run_worker("lua/luac@fn-macros-expand", counts), 0)
        t |> success(counts |> starts_with("ok\n"), counts)
        let expanded = fread("metrics/work/lua/luac@fn-macros-expand/das/lapi.das")
        t |> success(!(expanded |> contains("[c_macro]\ndef ")), expanded)
        t |> equal(run_worker("lua/luac", counts), 0)
        let folded = fread("metrics/work/lua/luac/das/lapi.das")
        t |> success(folded |> contains("[c_macro]\ndef private "), folded)
    }
    t |> run("a key's suffix names its --fn-macros value, else the default; it is a kernel mode and a Lua opt-in") @(t : T?) {
        t |> equal(fn_macros_of("lua/lua@fn-macros-expand"), "expand")
        t |> equal(fn_macros_of("perf/blit@past-end-inline"), "")
        var layout : string
        t |> equal(lua_key_parts("lua/luac@fn-macros-expand", layout), "luac")
        t |> equal(layout, "source")
        t |> equal(kernel_of_key("blit@fn-macros-expand"), "blit")
        let keys <- expected_input_keys()
        t |> success(has_value(keys, "lua/lua@fn-macros-expand") && has_value(keys, "perf/blit@fn-macros-expand"))
    }
}

// ruling 38 addendum 19: the `@<form>-off` keys under `--forms-off <form>`
[test]
def test_worker_forms_off(t : T?) {
    t |> run("--one converts a kernel's `@pointer-steps-off` key under --forms-off pointer_steps: the sum spelled, where the plain key steps") @(t : T?) {
        var counts : string
        t |> equal(run_worker("perf/compound_lit@pointer-steps-off", counts), 0)
        t |> success(counts |> starts_with("ok\n"), counts)
        t |> success(fread("metrics/work/perf/compound_lit@pointer-steps-off/das/compound_lit.das") |> contains(" = row + 1\n"))
        t |> equal(run_worker("perf/compound_lit", counts), 0)
        t |> success(fread("metrics/work/perf/compound_lit/das/compound_lit.das") |> contains("row++\n"))
    }
    t |> run("a key's suffix names its --forms-off form, else none; each is a kernel mode and a Lua opt-in") @(t : T?) {
        t |> equal(forms_off_of("perf/blit@pointer-steps-off"), "pointer_steps")
        t |> equal(forms_off_of("lua/lua@ranged-loops-off"), "ranged_loops")
        t |> equal(forms_off_of("lua/luac@c-switch-off"), "c_switch")
        t |> equal(forms_off_of("perf/blit@fn-macros-expand"), "")
        var layout : string
        t |> equal(lua_key_parts("lua/luac@c-switch-off", layout), "luac")
        t |> equal(layout, "source")
        t |> equal(kernel_of_key("blit@ranged-loops-off"), "blit")
        let keys <- expected_input_keys()
        for (suffix in FORMS_OFF_KEY_SUFFIXES) {
            t |> success(has_value(keys, "lua/lua{suffix}") && has_value(keys, "perf/blit{suffix}"), suffix)
        }
    }
}

[test]
def test_gate(t : T?) {
    var dir_error : string
    let dir = create_temp_directory("c2das_readability_gate", dir_error)
    t |> equal(dir_error, "")
    mkdir_rec(path_join(dir, "metrics"))
    fwrite(path_join(dir, "metrics/readability_linux.json"), "[1]")
    t |> run("the gate names a broken capture as a finding and exits 1") @(t : T?) {
        var out : string
        let daslang = get_das_root() + "/bin/daslang"
        let rc = run_and_capture(["bash", "-c", "root=$(pwd); cd \"$1\" && \"$2\" \"$root/metrics/REVIEW.das\"", "gate", dir, daslang], out, 120.0)
        t |> equal(rc, 1, out)
        t |> success(out |> contains("metrics/readability_linux.json: not a JSON object"), out)
    }
    rmdir_rec(dir)
}

[test]
def test_run_help(t : T?) {
    t |> run("-? prints the help without fetching and exits before any input converts") @(t : T?) {
        var out : string
        let rc = run_and_capture(["bash", "scripts/run_readability.sh", "-?", "--filter", "no/such-input"], out, 120.0)
        t |> equal(rc, 0, out)
        t |> success(out |> contains("show this help and exit"), out)
        t |> success(!(out |> contains("**Readability**")), out)
        t |> success(!(out |> contains("fetch:")), out)
    }
}
