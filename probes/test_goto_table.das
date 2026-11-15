options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require _daslang_child
require ../converter/tiers.das

//! `goto <table>?[cond - lo] ?? <label>`, the jump the converter writes for a dense switch whose
//! range has values no case holds (`switch_dispatch` `table`,
//! `converter/ARCHITECTURE_EMITTER_CONTROL.md`): daslang takes a `let private` global fixed array
//! of label numbers indexed by an `int`, `uint`, `int64` or `uint64`, an index outside it is null
//! and `??` gives the default's label, under the interpreter, the JIT and the AOT host alike.

let private PATTERN = "probes/_goto_table.das"
let private PROBE_TIERS = fixed_array("interp", "jit", "aot")
let private NO_MODULES : array<string>

def private last_line(out : string) : string {
    let lines <- [for (l in split(out, "\n")); strip(l); where !empty(strip(l))]
    return empty(lines) ? "" : lines[length(lines) - 1]
}

// a four-case switch over `x` in -2 .. 6 through the table of `labels`, jumping by `jump`, with `decls` before it
def private form(decls, labels, jump : string) : string =>
    "options gen2\n{decls}let private TAB = fixed_array<int>({labels})\ndef f(x : int) : int \{\n    var r = 0\n    goto {jump}\n    label 1:\n    r += 1\n    label 2:\n    r += 10\n    goto label 5\n    label 3:\n    r += 100\n    goto label 5\n    label 4:\n    r += 1000\n    label 5:\n    return r\n\}\n[export]\ndef main : int \{\n    for (i in range(-2, 7)) \{\n        print(\"\{f(i)\} \")\n    \}\n    print(\"\\n\")\n    return 0\n\}\n"

// the forms the compiler refuses, each with the text of its error: why the converter spells `??`
// after the index and `int(_cond)` for a condition that is no `int`, `uint`, `int64` or `uint64`
let private REFUSED <- [
    ("no_coalesce", "", "TAB?[x]", "error[30194]: label type has to be int, not int const?"),
    ("uint8_index", "", "TAB?[uint8(x)] ?? 4", "error[31011]: safe-index of fixed_array<> must be inside the 'unsafe' block"),
    ("enum_index", "enum E \{ a, b, c, d, e \}\n", "TAB?[unsafe(reinterpret<E>(x))] ?? 4", "error[31011]: safe-index of fixed_array<> must be inside the 'unsafe' block")
]

[test]
def test_goto_table(tt : T?) {
    let work = test_temp_dir()
    for (tier in PROBE_TIERS) {
        tt |> run("the dense switch as `goto <table>?[cond - lo] ?? <label>` runs what the structural form does under {tier}: a case falling into the next, a goto into a neighbouring case, `default` in the middle and missing, values no case holds, a negative low value, values outside the range, an enum, int64, uint, uint64 and uint8 subject, a switch in a loop with `continue` and `break`, a nested switch") @(t : T?) {
            var out : string
            let rc = run_tier(PATTERN, tier, path_join(work, "pattern_{tier}"), out, NO_MODULES, 600.0)
            t |> equal(rc, 0, "{tier}: {out}")
            t |> equal(last_line(out), "basic 11 50100 1000 1000 1000 bias 3 6040 0 loop 4878 nested 1110 1000 bad 0", "{tier}: {out}")
        }
    }
    for (case_name, decls, jump, error in [for (r in REFUSED); r._0], [for (r in REFUSED); r._1], [for (r in REFUSED); r._2], [for (r in REFUSED); r._3]) {
        tt |> run("the jump `goto {jump}` is refused: {error}") @(t : T?) {
            let child = daslang_child("goto_table_{case_name}", form(decls, "1, 2, 2, 3", jump), true)
            t |> success(child.rc != 0, child.out)
            t |> success(child.out |> contains(error), child.out)
        }
    }
    let bad_label = path_join(work, "goto_table_bad_label.das")
    fwrite(bad_label, form("", "1, 2, 99, 3", "TAB?[x] ?? 4"))
    for (tier in PROBE_TIERS) {
        tt |> run("a table entry that names no label of the function is a runtime `invalid label` under {tier}, after the cases before it ran: the compiler checks no entry") @(t : T?) {
            var out : string
            let rc = run_tier(bad_label, tier, path_join(work, "bad_label_{tier}"), out, NO_MODULES, 600.0)
            t |> success(rc != 0, "{tier}: {out}")
            t |> success(out |> contains("1000 1000 11 10 "), "{tier}: {out}")
            t |> success(out |> contains("invalid label"), "{tier}: {out}")
        }
    }
}
