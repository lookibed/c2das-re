options gen2
require dastest/testing_boost public
require strings
require _variadic_fixture

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
    t |> run("the list forwards to a non-variadic callee and va_copy is an array clone") @(t : T?) {
        t |> equal(forward(10l, 1, 2, 3), 60l)
        t |> equal(copied(4, 5), 9l)
    }
    t |> run("a [variadic] function declared in another module is callable through its macro") @(t : T?) {
        t |> equal(fixture_sum(3, 1, 2, 3), 6l)
    }
}
