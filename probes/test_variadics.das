options gen2
require dastest/testing_boost public
require daslib/apply

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
}
