options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require ../../probes/_daslang_child.das
require ../../converter/tiers.das

//! `[c_macro]` under every tier: a header module of macro defs in the shapes the fn-macros fold
//! prints (a nested tag test, a `[c_function]` expression or statement body under `unsafe`, a void
//! statement body with or without a local, a bare `null` body, a parameter used twice and one never used) gives C's expansion results
//! under the interpreter, the JIT, the JIT-linked executable and AOT; the expansion leaves no call,
//! no argument copy and no result local; a body of no macro shape is a compile error; and the same
//! defs under `[inline]` evaluate an argument once, a call's semantics, not a macro's.

// the header module, as a header's macros are placed; `{CARRIER}` is the annotation under test
let private HEADER_SOURCE = "options gen2\nmodule cm_h public\n\nrequire c_runtime/c_macro\nrequire c_runtime/c_function\n\nstruct TValue \{\n    value_ : int64\n    tt_ : uint8\n\}\n\nstruct StackValue \{\n    val : TValue\n\}\n\n[\{CARRIER\}]\ndef rawtt(o) => o.tt_\n\n[\{CARRIER\}]\ndef checktag(o; t) => int(rawtt(o)) == t\n\n[\{CARRIER\}]\ndef ttisinteger(o) => checktag(o, 3)\n\n[\{CARRIER\}, c_function]\ndef s2v(var o) : TValue? => addr(o.val)\n\n[\{CARRIER\}]\ndef twice(x) => x + x\n\n[\{CARRIER\}]\ndef first(a; b) => a\n\n[\{CARRIER\}]\ndef setivalue(var obj; x) \{\n    var io : TValue? = obj\n    io.value_ = int64(x)\n    io.tt_ = uint8(3)\n\}\n\n[\{CARRIER\}]\ndef nilvalue(o) : TValue? => null\n\n[\{CARRIER\}]\ndef settt_(var o; t) \{\n    o.tt_ = uint8(t)\n\}\n\n[\{CARRIER\}, c_function]\ndef storeat(var p; i; v) \{\n    p[i] = v\n\}\n"

// the converted module: `io` is also the name of `setivalue`'s local; `bump` counts its calls
let private MAIN_SOURCE = "options gen2\n\nrequire cm_h\nrequire c_runtime/c_function\n\nvar calls = 0\n\ndef bump() : int \{\n    calls++\n    return calls\n\}\n\n[export, c_function]\ndef main : int \{\n    var a = StackValue()\n    var io = 5\n    var p = addr(a)\n    setivalue(s2v(p), io)\n    let t = ttisinteger(s2v(p)) ? 1 : 0\n    let d = twice(bump())\n    let f = first(7, bump())\n    var cells : int[4]\n    storeat(addr(cells[0]), 2, 9)\n    settt_(s2v(p), 19)\n    print(\"\{t\} \{a.val.value_\} \{d\} \{f\} \{calls\} \{nilvalue(p) == null\} \{cells[2]\} \{int(a.val.tt_)\}\\n\")\n    return 0\n\}\n"

// one file: the tag test of a stack slot, exported so its compiled text stays in the program log
let private LOG_SOURCE = "options gen2\noptions log = true\n\nrequire c_runtime/c_macro\nrequire c_runtime/c_function\n\nstruct TValue \{\n    value_ : int64\n    tt_ : uint8\n\}\n\nstruct StackValue \{\n    val : TValue\n\}\n\n[c_macro]\ndef private rawtt(o) => o.tt_\n\n[c_macro]\ndef private checktag(o; t) => int(rawtt(o)) == t\n\n[c_macro]\ndef private ttisinteger(o) => checktag(o, 3)\n\n[c_macro, c_function]\ndef private s2v(var o) : TValue? => addr(o.val)\n\n[c_macro]\ndef private setivalue(var obj; x) \{\n    var io : TValue? = obj\n    io.value_ = int64(x)\n    io.tt_ = uint8(3)\n\}\n\n[export, c_function]\ndef tag_kernel(var b : StackValue?) : int \{\n    setivalue(s2v(b), 4)\n    return ttisinteger(s2v(b)) ? 1 : 0\n\}\n\n[export]\ndef main \{\n    var a = StackValue()\n    print(\"\{tag_kernel(unsafe(addr(a)))\}\\n\")\n\}\n"

// a def whose body returns a value after a statement: no macro shape
let private SHAPE_SOURCE = "options gen2\nrequire c_runtime/c_macro\n\n[c_macro]\ndef private tonumber(o : int) : int \{\n    var n = o\n    n++\n    return n\n\}\n\n[export]\ndef main \{\n    print(\"\{tonumber(3)\}\\n\")\n\}\n"

// a def whose body is a bare `return`
let private EMPTY_RETURN_SOURCE = "options gen2\nrequire c_runtime/c_macro\n\n[c_macro]\ndef private nothing(o : int) \{\n    return\n\}\n\n[export]\ndef main \{\n    nothing(3)\n\}\n"

let private CM_TIERS = fixed_array("interp", "jit", "exe", "aot")

// the program's two files in `work`, the defs under `carrier`; the entry path
def private write_program(work, carrier : string) : string {
    fwrite(path_join(work, "cm_h.das"), replace(HEADER_SOURCE, "\{CARRIER\}", carrier))
    let entry = path_join(work, "cm_main.das")
    fwrite(entry, MAIN_SOURCE)
    return entry
}

// the last non-empty line of a run's output
def private last_line(out : string) : string {
    let lines <- [for (l in split(out, "\n")); strip(l); where !empty(strip(l))]
    return !empty(lines) ? lines[length(lines) - 1] : ""
}

// the text of the function `name` in a program log
def private function_text(log, name : string) : string {
    var lines : array<string>
    var inside = false
    for (l in split(log, "\n")) {
        inside = inside || l |> starts_with("def public {name}(")
        if (inside) {
            lines |> push(l)
            if (l == "\}") {
                break
            }
        }
    }
    return join(lines, "\n")
}

[test(description = "[c_macro] defs give the C expansion's results under every tier", timeout = 1200)]
def test_c_macro_tiers(tt : T?) {
    let work = test_temp_dir()
    let entry = write_program(work, "c_macro")
    for (tier in CM_TIERS) {
        tt |> run("the macro shapes run under {tier}: the tag set, `bump()` twice for `x + x`, never for an unused parameter") @(t : T?) {
            var out : string
            let rc = run_tier(entry, tier, path_join(work, tier), out, CONVERTED_MODULES)
            t |> equal(rc, 0, "{tier}: {out}")
            t |> equal(last_line(out), "1 5 3 7 2 true 9 19", "{tier}: {out}")
        }
    }
}

[test(description = "the same defs under [inline] keep a call's semantics: each argument evaluated once, an unused one too", timeout = 1200)]
def test_c_macro_control(t : T?) {
    let work = test_temp_dir()
    let entry = write_program(work, "inline")
    var out : string
    let rc = run_tier(entry, "interp", path_join(work, "interp"), out, CONVERTED_MODULES)
    t |> equal(rc, 0, out)
    t |> equal(last_line(out), "1 5 2 7 2 true 9 19", out)
}

[test(description = "an expansion leaves no call, argument copy or result local", timeout = 600)]
def test_c_macro_text(tt : T?) {
    let r = runtime_child_flags("c_macro_log", LOG_SOURCE, ["-no-module-cache"])
    let f = function_text(r.out, "tag_kernel")
    tt |> run("the program runs") @(t : T?) {
        t |> equal(r.rc, 0, r.out)
        t |> equal(last_line(r.out), "1", r.out)
    }
    tt |> run("the tag test reads the field in place") @(t : T?) {
        t |> equal(f |> find("int(addr(b.val).tt_) == 3") >= 0, true, f)
        for (name in ["rawtt(", "checktag(", "ttisinteger(", "s2v(", "setivalue(", "_inl", "_res", "_arg"]) {
            t |> equal(f |> find(name) >= 0, false, "{name} in {f}")
        }
    }
    tt |> run("a statement body's local is renamed apart from the caller's") @(t : T?) {
        t |> equal(f |> find("_io:TValue? -const = addr(b.val);") >= 0, true, f)
    }
}

[test(description = "a [c_macro] def whose body is no macro shape is a compile error", timeout = 600)]
def test_c_macro_shape(t : T?) {
    let r = runtime_child("c_macro_shape", SHAPE_SOURCE, true)
    child_rejects(t, "a value returned after a statement", r, "neither one expression nor a void def's statements")
    let e = runtime_child("c_macro_empty", EMPTY_RETURN_SOURCE, true)
    child_rejects(t, "a bare return", e, "a return without a value")
}
