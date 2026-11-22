options gen2
require dastest/testing_boost public
require strings
require _variadic_fixture
require ../../probes/_daslang_child.das

enum Kind {
    KA
    KB
}

[variadic]
def sum(n : int; va : va_args) : double {
    var acc = 0.0lf
    var vac = 0
    for (_k in range(n)) {
        if (va[vac] is i) {
            acc += double(va[vac] as i)
        } else {
            acc += va[vac] as d
        }
        vac++
    }
    return acc
}

[variadic]
def kinds(va : va_args) : string {
    return build_string() $(var w) {
        for (v in va) {
            if (v is p) {
                w |> write("p")
            } elif (v is d) {
                w |> write("d")
            } else {
                w |> write("i{v as i}")
            }
        }
    }
}

def total(lst : CVaList) : int64 {
    var acc = 0l
    for (v in lst) {
        acc += v as i
    }
    return acc
}

[variadic]
def forward(scale : int64; va : va_args) : int64 {
    return scale * total(va)
}

[variadic]
def copied(va : va_args) : int64 {
    let copy := va
    var cursor = 0
    cursor++
    return (va[0] as i) + (copy[cursor] as i)
}

// the cursor API as the converter emits it: `va_list v;` then `va_start(v, n)`, typed pops,
// `va_copy` as assignment, a `va_list` parameter that pops the caller's cursor
def take_int(a : int; var ap : CVaCursor) : int => a + int(va_i(ap))

[variadic]
def walk(n : int; va : va_args) : double {
    var v, w : CVaCursor
    v = va_begin(va)
    w = v
    var acc = double(take_int(n, v))
    acc += va_d(v)
    let s = unsafe(reinterpret<string>(va_p(v)))
    acc += double(length(s))
    acc += double(int(va_i(w)) * 1000)
    return acc
}

def fn_seven(a : int) : int => a + 7

[variadic]
def call_fn(va : va_args) : int {
    var v = va_begin(va)
    let f = unsafe(reinterpret<function<(a0 : int) : int>>(va_p(v)))
    return invoke(f, 1)
}

[variadic]
def rest_after(skip : int; va : va_args) : CVaList {
    var v = va_begin(va)
    for (_k in range(skip)) {
        va_i(v)
    }
    return <- va_rest(v)
}

struct Pair {
    a : int
    b : double
}

[variadic]
def pair_sum(n : int; va : va_args) : double {
    var v = va_begin(va)
    var acc = 0.0lf
    for (_k in range(n)) {
        var p : Pair
        unsafe {
            p = *reinterpret<Pair?>(va_r(v, typeinfo sizeof(type<Pair>)))
        }
        acc += double(p.a) + p.b + double(va_i(v))
    }
    return acc
}

[variadic]
def pop_double(va : va_args) : double {
    var v = va_begin(va)
    return va_d(v)
}

[variadic]
def pop_two(va : va_args) : int64 {
    var v = va_begin(va)
    return va_i(v) + va_i(v)
}

[test]
def test_variadic(t : T?) {
    t |> run("a call site keeps the C spelling and the body pops a typed cursor") @(t : T?) {
        t |> equal(sum(4, 10, 2.5, 20, 0.5), 33.0lf)
        t |> equal(sum(1, 5), 5.0lf)
        t |> equal(sum(0), 0.0lf)
    }
    t |> run("default argument promotions: float to double, bool and enums to int64, pointers to void") @(t : T?) {
        var x = 5
        t |> equal(kinds(unsafe(addr(x)), 1.5f, int8(3), Kind.KB, uint16(7), true, 2.0lf), "pdi3i1i7i1d")
    }
    t |> run("the list forwards to a non-variadic callee and clones as an array") @(t : T?) {
        t |> equal(forward(10l, 1, 2, 3), 60l)
        t |> equal(copied(4, 5), 9l)
    }
    t |> run("a [variadic] function declared in another module is callable through its macro") @(t : T?) {
        t |> equal(fixture_sum(3, 1, 2, 3), 6l)
    }
    t |> run("a record travels as the address of the tuple's copy and its size; va_r reads it back") @(t : T?) {
        var p = Pair(a = 1, b = 0.5lf)
        let q = Pair(a = 2, b = 0.25lf)
        t |> equal(pair_sum(2, p, 10, q, 20), 33.75lf)
        p.a = 100
        t |> equal(pair_sum(1, p, 0), 100.5lf)
    }
    t |> run("a list already built passes as the trailing arguments as it is, a copy (a late-bound variadic call forwarding its list)") @(t : T?) {
        var built <- [CVal(i = 4l), CVal(i = 5l)]
        t |> equal(fixture_sum`va(2, built), 9l)
        let copied_list <- to_cvalist(built)
        t |> equal(length(copied_list), 2)
    }
}

[test]
def test_cursor(t : T?) {
    t |> run("the cursor: va_begin, typed pops, a copy walking on its own, a va_list parameter popping the caller's cursor") @(t : T?) {
        // take_int pops 2 from v; v then reads 2.5 and "abc"; the copy w still reads 2
        t |> equal(walk(1, 2, 2.5lf, unsafe(reinterpret<uint8?>("abc"))), 3.0lf + 2.5lf + 3.0lf + 2000.0lf)
        t |> equal(call_fn(@@fn_seven), 8)
    }
    t |> run("va_rest is the list from the cursor on, for forwarding") @(t : T?) {
        let rest <- rest_after(2, 10, 20, 30, 4.5lf)
        t |> equal(length(rest), 2)
        t |> equal(rest[0] as i, 30l)
        t |> equal(rest[1] as d, 4.5lf)
        let none <- rest_after(1, 5)
        t |> equal(length(none), 0)
        let idle : CVaCursor
        t |> equal(length(va_rest(idle)), 0)
    }
    t |> run("a pop of the wrong class or past the arguments panics, the C undefined behavior made visible") @(t : T?) {
        var caught = 0
        try {
            pop_double(1)
        } recover {
            caught++
        }
        try {
            pop_two(1)
        } recover {
            caught++
        }
        var idle : CVaCursor
        try {
            va_i(idle)
        } recover {
            caught++
        }
        t |> equal(caught, 3)
        t |> equal(pop_two(1, 2), 3l)
    }
    t |> run("a pointer pop reads an integer zero as null and an integer pop reads a pointer's bits, as x86-64 registers do") @(t : T?) {
        var x = 3
        let px = unsafe(addr<void?>(x))
        let lst <- [CVal(i = 0l), CVal(p = px), CVal(i = 5l)]
        var v = va_begin(lst)
        t |> equal(va_p(v) == null, true)
        t |> equal(va_i(v), int64(intptr(px)))
        var caught = false
        try {
            va_p(v)
        } recover {
            caught = true
        }
        t |> equal(caught, true)
    }
    t |> run("each misread panics with its own message: the arm found, the end of the list, a list no va_start began") @(t : T?) {
        let cases <- [
            ("var v = va_begin([CVal(d = 1.5lf)])\n    va_i(v)", "va_arg reads an integer where trailing argument 0 is a double"),
            ("var v = va_begin([CVal(i = 1l)])\n    va_i(v)\n    va_d(v)", "va_arg reads a double at trailing argument 1, past the 1 passed"),
            ("var v : CVaCursor\n    va_p(v)", "va_arg reads a pointer from a va_list no va_start began"),
            ("var v = va_begin([CVal(i = 1l)])\n    va_d(v)", "va_arg reads a double where trailing argument 0 is an integer"),
            ("var v = va_begin([CVal(d = 1.5lf)])\n    va_p(v)", "va_arg reads a pointer where trailing argument 0 is a double"),
            ("var x = 1\n    var v = va_begin([CVal(p = unsafe(addr<void?>(x)))])\n    va_d(v)", "va_arg reads a double where trailing argument 0 is a pointer"),
            ("var v = va_begin([CVal(r = CVaRecord(size = 8))])\n    va_i(v)", "va_arg reads an integer where trailing argument 0 is a record"),
            ("var v = va_begin([CVal(i = 1l)])\n    va_r(v, 8)", "va_arg reads a record where trailing argument 0 is an integer"),
            ("var v = va_begin([CVal(r = CVaRecord(size = 8))])\n    va_r(v, 16)", "va_arg reads a record of 16 bytes where trailing argument 0 is one of 8")
        ]
        for (c in cases) {
            let src = "options gen2\nrequire c_runtime/variadic\n[export]\ndef main \{\n    {c._0}\n\}\n"
            let r = runtime_child("va_messages", src, false)
            t |> equal(r.out |> find(c._1) >= 0, true, r.out)
        }
    }
}

[test]
def test_call_order(t : T?) {
    t |> run("a macro call above the [variadic] definition or inside it does not resolve; the macro's own `va spelling does") @(t : T?) {
        let src = "options gen2\nrequire c_runtime/variadic\n[variadic]\ndef early(n : int; va : va_args) : int \{\n    return n + later(1, 2)\n\}\n[variadic]\ndef later(n : int; va : va_args) : int \{\n    var v = va_begin(va)\n    return n + int(va_i(v))\n\}\n[export]\ndef main \{\n    early(5)\n\}\n"
        child_rejects(t, "variadic_forward_call", runtime_child("variadic_forward_call", src, true), "no matching functions or generics: later")
        let ordered = "options gen2\nrequire c_runtime/variadic\n[variadic]\ndef later(n : int; va : va_args) : int \{\n    var v = va_begin(va)\n    return n + int(va_i(v))\n\}\n[variadic]\ndef early(n : int; va : va_args) : int \{\n    return n + later(1, 2)\n\}\n[export]\ndef main \{\n    early(5)\n\}\n"
        t |> equal(runtime_child("variadic_ordered_call", ordered, true).rc, 0)
        // a call inside the definition's own body is above the macro too
        let recursive = "options gen2\nrequire c_runtime/variadic\n[variadic]\ndef down(n : int; va : va_args) : int \{\n    return n > 0 ? down(n - 1) : 0\n\}\n[export]\ndef main \{\n    down(2)\n\}\n"
        child_rejects(t, "variadic_recursive_call", runtime_child("variadic_recursive_call", recursive, true), "no matching functions or generics: down")
        let spelled = "options gen2\nrequire c_runtime/variadic\n[variadic]\ndef early(n : int; va : va_args) : int \{\n    return n + later`va(1, (2,))\n\}\n[variadic]\ndef later(n : int; va : va_args) : int \{\n    var v = va_begin(va)\n    return n > 0 ? int(va_i(v)) + later`va(n - 1, (0,)) : 0\n\}\n[export]\ndef main \{\n    print(\"\{early`va(5, VaNone())\}\\n\")\n\}\n"
        let r = runtime_child("variadic_spelled_call", spelled, false)
        t |> equal(r.rc, 0, r.out)
        t |> equal(program_output(r.out) |> find("7") >= 0, true, r.out)
    }
}
