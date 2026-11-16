options gen2
require dastest/testing_boost public
require strings
require daslib/strings_boost
require _daslang_child

//! What the splice of an `[inline] def` leaves in the caller (docs/probe-findings.md F107 to F109):
//! an expression body is substituted as written at every nesting level, whether its parameter is
//! `var` or not, so an `&&` of two spliced calls stays an `&&`; a body under `unsafe` binds one
//! local for its `var` parameter and nothing else; a call under `addr(...)` is spliced as any
//! other; and a generic def with a `var` parameter given a `let` pointer is the mismatch error a
//! typed def reports.

// three defs nested as Lua's ttisfloat -> checktag -> rawtt, once with `var` parameters and once
// without; s2v's body under `unsafe`; each caller exported so its text stays in the log
let private SPLICE_SOURCE = "options gen2\noptions log = true\n\nstruct TValue \{\n    value_ : double\n    tt_ : uint8\n\}\n\nstruct StackValue \{\n    val : TValue\n\}\n\n[inline]\ndef private rawtt_v(var o) => o.tt_\n\n[inline]\ndef private checktag_v(var o; t) => int(rawtt_v(o)) == t\n\n[inline]\ndef private ttisfloat_v(var o) => checktag_v(o, 19)\n\n[inline]\ndef private rawtt(o) => o.tt_\n\n[inline]\ndef private checktag(o; t) => int(rawtt(o)) == t\n\n[inline]\ndef private ttisfloat(o) => checktag(o, 19)\n\n[inline]\ndef private s2v(var o) : TValue? \{\n    unsafe \{\n        return addr(o.val)\n    \}\n\}\n\n[export]\ndef var_chain(var p : TValue?) : int \{\n    var s = 0\n    if (ttisfloat_v(p)) \{\n        s++\n    \}\n    return s\n\}\n\n[export]\ndef const_var(var p : TValue?) : int \{\n    var s = 0\n    if (ttisfloat(p)) \{\n        s++\n    \}\n    return s\n\}\n\n[export]\ndef const_let(p : TValue?) : int \{\n    var s = 0\n    if (ttisfloat(p)) \{\n        s++\n    \}\n    return s\n\}\n\n[export]\ndef and_operand(var p : TValue?; var q : TValue?) : int \{\n    var s = 0\n    if (ttisfloat_v(p) && ttisfloat_v(q)) \{\n        s++\n    \}\n    return s\n\}\n\n[export]\ndef unsafe_body(var b : StackValue?) : int \{\n    var v = s2v(b)\n    return int(v.tt_)\n\}\n\n[export]\ndef main \{\n    var a = StackValue()\n    a.val.tt_ = uint8(19)\n    unsafe \{\n        var p = addr(a.val)\n        print(\"\{var_chain(p)\} \{const_var(p)\} \{const_let(p)\} \{and_operand(p, p)\} \{unsafe_body(addr(a))\}\\n\")\n    \}\n\}\n"

// an [inline] call under `addr(...)` beside the same call read plainly
let private ADDR_SOURCE = "options gen2\noptions log = true\noptions log_optimization = true\n\nstruct Node \{\n    arr : int[4]\n    n : int\n\}\n\n[inline]\ndef private getn(var o : Node?) : Node? => o\n\n[export]\ndef under_addr(var p : Node?; k : int) : int? \{\n    return unsafe(addr(getn(p).arr[k]))\n\}\n\n[export]\ndef plain_read(var p : Node?; k : int) : int \{\n    return getn(p).arr[k]\n\}\n\n[export]\ndef main \{\n    var a = Node(n = 2)\n    a.arr[1] = 7\n    unsafe \{\n        print(\"\{*under_addr(addr(a), 1)\} \{plain_read(addr(a), 1)\}\\n\")\n    \}\n\}\n"

// a generic def with a `var` parameter called with a `let` pointer; `TYPED` is the parameter's type
let private LOOP_SOURCE = "options gen2\n\nstruct SV \{\n    val : int\n\}\n\ndef get(var oTYPED) => o.val\n\n[export]\ndef main \{\n    var a = SV()\n    let ra : SV? = unsafe(addr(a))\n    print(\"\{get(ra)\}\\n\")\n\}\n"

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

def private count_of(text, needle : string) : int => length(split(text, needle)) - 1

[test(description = "the splice of an [inline] def with an expression body is the expression as written; a body under unsafe binds its var parameter once", timeout = 1200)]
def test_inline_splice_shapes(tt : T?) {
    let r = daslang_child_flags("inline_splice", SPLICE_SOURCE, ["-no-module-cache"])
    tt |> run("the program runs and every def is spliced (F107)") @(t : T?) {
        t |> equal(r.rc, 0, r.out)
        t |> success(r.out |> ends_with("1 1 1 1 19\n"), r.out)
    }
    tt |> run("a by-value var parameter the bodies only read binds no local at any of the three levels (F107)") @(t : T?) {
        let f = function_text(r.out, "var_chain")
        t |> equal(count_of(f, "_inl"), 0, f)
        t |> equal(count_of(f, "int(p.tt_) == 19"), 1, f)
    }
    tt |> run("a non-var parameter given a var variable or a let one binds no copy (F107)") @(t : T?) {
        let widened = function_text(r.out, "const_var")
        t |> equal(count_of(widened, "_inl"), 0, widened)
        t |> equal(count_of(widened, "int(p.tt_) == 19"), 1, widened)
        let as_written = function_text(r.out, "const_let")
        t |> equal(count_of(as_written, "_inl"), 0, as_written)
        t |> equal(count_of(as_written, "int(p.tt_) == 19"), 1, as_written)
    }
    tt |> run("an && of two spliced chains stays an &&, with no flag (F107)") @(t : T?) {
        let f = function_text(r.out, "and_operand")
        t |> equal(count_of(f, "_low"), 0, f)
        t |> equal(count_of(f, "(int(p.tt_) == 19) && (int(q.tt_) == 19)"), 1, f)
    }
    tt |> run("a body under unsafe is its expression over one local copy of the var parameter, with no result local (F107)") @(t : T?) {
        let f = function_text(r.out, "unsafe_body")
        t |> equal(count_of(f, "_res"), 0, f)
        t |> equal(count_of(f, "_arg_o:StackValue? = b;"), 1, f)
        t |> equal(count_of(f, "_arg_o.val);"), 1, f)
    }
}

[test(description = "an [inline] call under addr(...) is spliced and logged as a plain read is", timeout = 1200)]
def test_inline_under_addr(tt : T?) {
    let r = daslang_child_flags("inline_addr", ADDR_SOURCE, ["-no-module-cache"])
    tt |> run("the call under addr and the plain one are both spliced, nothing is declined (F108)") @(t : T?) {
        t |> equal(r.rc, 0, r.out)
        t |> success(r.out |> ends_with("7 7\n"), r.out)
        t |> equal(count_of(function_text(r.out, "under_addr"), "addr(p.arr[k])"), 1, r.out)
        t |> equal(count_of(function_text(r.out, "under_addr"), "getn("), 0, r.out)
        t |> equal(count_of(function_text(r.out, "plain_read"), "getn("), 0, r.out)
        t |> success(count_of(r.out, "INLINE getn into under_addr") >= 1, r.out)
        t |> success(count_of(r.out, "INLINE getn into plain_read") >= 1, r.out)
        t |> equal(count_of(r.out, " 0 declined in module"), count_of(r.out, " declined in module"), r.out)
    }
}

[test(description = "a let pointer given to a var parameter is the mismatch error, for a generic def as for a typed one", timeout = 1200)]
def test_generic_var_param_const_pointer(tt : T?) {
    tt |> run("the generic def: error 30341, no matching function (F109)") @(t : T?) {
        child_rejects(t, "loop_generic", daslang_child("loop_generic", LOOP_SOURCE |> replace("TYPED", ""), true), "30341")
    }
    tt |> run("the typed def: error 30341, no matching function (F109)") @(t : T?) {
        child_rejects(t, "loop_typed", daslang_child("loop_typed", LOOP_SOURCE |> replace("TYPED", " : SV?"), true), "30341")
    }
}
