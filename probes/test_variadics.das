options gen2
require dastest/testing_boost public
require daslib/apply
require _daslang_child
require strings
require daslib/fio

enum Kind {
    KA
    KB
}

variant CVal {
    i : int64
    d : double
    p : void?
}

typedef CVaList = array<CVal>

def to_cvalist(va : auto) : CVaList {
    var lst : CVaList
    apply(va) $(name, field) {
        static_if (typeinfo is_pointer(field)) {
            unsafe {
                lst |> push(CVal(p = reinterpret<void?>(field)))
            }
        } static_elif (typeinfo is_float(field)) {
            lst |> push(CVal(d = double(field)))
        } static_elif (typeinfo is_double(field)) {
            lst |> push(CVal(d = field))
        } else {
            lst |> push(CVal(i = int64(field)))
        }
    }
    return <- lst
}

def sum(n : int; va_tuple : auto) : double {
    let va <- to_cvalist(va_tuple)
    var acc = 0.0lf
    var vac = 0
    while (vac < n) {
        if (va[vac] is i) {
            acc += double(va[vac] as i)
        } else {
            acc += va[vac] as d
        }
        vac++
    }
    return acc
}

def field_names_const(va : auto) : string {
    var s = ""
    apply(va) $(name, field) {
        s += typeinfo typename(field) + ";"
    }
    return s
}

def field_names_var(var va : auto) : string {
    var s = ""
    apply(va) $(name, field) {
        s += typeinfo typename(field) + ";"
    }
    return s
}

// the cursor shape of a C `va_list`: the address of a list and a position
struct Cursor {
    list : CVaList const?
    at : int
}

def begin(va : CVaList) : Cursor => Cursor(list = unsafe(addr(va)), at = 0)

def pop_i(var c : Cursor) : int64 {
    let v = deref(c.list)[c.at] as i
    c.at++
    return v
}

def pops_two(var c : Cursor) : int64 => pop_i(c) + pop_i(c)

def nine(a : int) : int => a + 9

def as_void(f : auto) : void? {
    static_if (typeinfo is_function(f)) {
        return unsafe(reinterpret<void?>(f))
    } else {
        return null
    }
}

[test]
def test_variadics(t : T?) {
    t |> run("a tuple literal instantiates the generic per shape and the CVaList pops in order") @(t : T?) {
        t |> equal(sum(4, (10, 2.5, 20, 0.5)), 33.0lf)
        t |> equal(sum(2, (1, 2)), 3.0lf)
    }
    t |> run("apply dispatches pointer, float promotion, double and int-class arms by folded traits") @(t : T?) {
        var x = 5
        unsafe {
            let va <- to_cvalist((addr(x), 1.5f, int8(3), Kind.KB, uint16(7)))
            t |> equal(length(va), 5)
            t |> equal(va[0] is p, true)
            t |> equal(va[1] is d, true)
            t |> equal(va[1] as d, 1.5lf)
            t |> equal(va[2] as i, 3l)
            t |> equal(va[3] as i, 1l)
            t |> equal(va[4] as i, 7l)
        }
    }
    t |> run("typename reflects the binding's constness; a one-element tuple is a tuple") @(t : T?) {
        t |> equal(field_names_const((1.5f, 2)), "float const;int const;")
        var tup = (1.5f, 2)
        t |> equal(field_names_var(tup), "float;int;")
        let _one = (7,)
        t |> equal(typeinfo typename(_one), "tuple<int> const")
    }
    t |> run("a cursor: addr of a let array is a const pointer, a typed pop reads through deref, a var parameter is the caller's cursor, assignment copies it") @(t : T?) {
        let lst <- [CVal(i = 10l), CVal(i = 20l), CVal(i = 30l)]
        var c = begin(lst)
        t |> equal(typeinfo typename(c.list), "array<variant<i:int64;d:double;p:void?>> const?")
        var copy = c
        t |> equal(pops_two(c), 30l)
        t |> equal(c.at, 2)
        t |> equal(copy.at, 0)
        t |> equal(pop_i(copy), 10l)
        t |> equal(pop_i(c), 30l)
    }
    t |> run("as on the wrong variant arm panics") @(t : T?) {
        let v = CVal(d = 1.5lf)
        var caught = false
        try {
            let n = v as i
            t |> equal(n, 0l)
        } recover {
            caught = true
        }
        t |> equal(caught, true)
    }
    t |> run("is_function folds in static_if and a function value round-trips through void?") @(t : T?) {
        let p = as_void(@@nine)
        t |> equal(as_void(3) == null, true)
        let f = unsafe(reinterpret<function<(a : int) : int>>(p))
        t |> equal(invoke(f, 1), 10)
    }
    t |> run("is_pointer does not take a function value, so a to_cvalist without an is_function arm fails to instantiate on one") @(t : T?) {
        t |> equal(typeinfo is_pointer(@@nine), false)
        let src = "options gen2\nrequire daslib/apply\nvariant CVal \{\n    i : int64\n    p : void?\n\}\ndef to_list(va : auto) : array<CVal> \{\n    var lst : array<CVal>\n    apply(va) $(name, field) \{\n        static_if (typeinfo is_pointer(field)) \{\n            lst |> push(CVal(p = unsafe(reinterpret<void?>(field))))\n        \} else \{\n            lst |> push(CVal(i = int64(field)))\n        \}\n    \}\n    return <- lst\n\}\ndef nine(a : int) : int => a + 9\n[export]\ndef main \{\n    let lst <- to_list((@@nine, 1))\n\}\n"
        child_rejects(t, "cvalist_function", daslang_child("cvalist_function", src, true), "no matching functions or generics: int64")
    }
    t |> run("a module cache write refuses a same-module [variadic] call macro inside a generic body; the macro's own `va spelling writes cold") @(t : T?) {
        let head = "options gen2\nrequire c_runtime/variadic\n[variadic]\ndef inner(n : int; va : va_args) : int \{\n    var v = va_begin(va)\n    return n + int(va_i(v))\n\}\n[variadic]\ndef outer(n : int; va : va_args) : int \{\n    return "
        let tail = "\n\}\n[export]\ndef main \{\n    print(\"outer=\{outer`va(1, VaNone())\}\\n\")\n\}\n"
        let cache = "{temp_directory_result() as value}/c2das_probe_cold_cache"
        remove(cache)
        let by_macro = runtime_child_flags("cold_cache_macro", "{head}inner(n, 5){tail}", ["-module-cache", cache])
        remove(cache)
        t |> equal(by_macro.rc, 1, by_macro.out)
        t |> equal(by_macro.out |> find("did not expect to find macro from the current module") >= 0, true, by_macro.out)
        t |> equal(by_macro.out |> find("outer=6") < 0, true, by_macro.out)
        let spelled = runtime_child_flags("cold_cache_spelled", "{head}inner`va(n, (5,)){tail}", ["-module-cache", cache])
        remove(cache)
        t |> equal(spelled.rc, 0, spelled.out)
        t |> equal(spelled.out |> find("outer=6") >= 0, true, spelled.out)
    }
}
