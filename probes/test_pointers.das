options gen2
require dastest/testing_boost public
require _daslang_child

var next_cells = fixed_array(0, 0, 0)
var next_calls = 0

// a call whose pointer result a step and a compound store reach once each
def next_cell : int ? {
    next_calls++
    return unsafe(addr(next_cells[next_calls % 3]))
}

[test]
def test_pointers(t : T?) {
    t |> run("reinterpret between pointer types and void") @(t : T?) {
        var x = int(0x01020304)
        unsafe {
            let bp = addr<uint8?>(x)
            t |> equal(int(deref(bp)), 4)
            let vp = addr<void?>(x)
            let ip = reinterpret<int?>(vp)
            t |> equal(deref(ip), int(0x01020304))
        }
    }
    t |> run("intptr is 8 bytes and round-trips a pointer") @(t : T?) {
        var x = 7
        unsafe {
            let p = addr(x)
            let ip = intptr(p)
            t |> equal(typeinfo sizeof(ip), 8)
            t |> equal(deref(reinterpret<int?>(ip)), 7)
            t |> equal(intptr(p) < intptr(p + 1), true)
        }
    }
    t |> run("null compares and pointer equality") @(t : T?) {
        var np : int?
        var x = 1
        t |> equal(np == null, true)
        unsafe {
            np = addr(x)
            t |> equal(np != null, true)
            t |> equal(np == addr(x), true)
        }
    }
    t |> run("a pointer a call returned, held in a var temporary, takes a step, a compound store and a store through deref, and a read through it gives the stored value") @(t : T?) {
        next_calls = 0
        var held = next_cell()
        deref(held)++
        deref(held) += 5
        var again = next_cell()
        deref(again) = 33
        t |> equal(deref(again), 33)
        t |> equal(next_cells[1], 6)
        t |> equal(next_cells[2], 33)
        t |> equal(next_calls, 2)
    }
    t |> run("null deref panics and try/recover catches it") @(t : T?) {
        var np : int?
        var caught = false
        try {
            deref(np) = 1
        } recover {
            caught = true
        }
        t |> equal(caught, true)
    }
}

// the das facts the csmith differential found (docs/probe-findings.md F40 to F46)
[test]
def test_csmith_pointers(t : T?) {
    t |> run("pointers of two constnesses do not compare; their addresses do") @(t : T?) {
        child_rejects(t, "compare_const", daslang_child("compare_const", "options gen2\ndef same(p : int const?; q : int?) : bool => p == q\n[export]\ndef main \{\n    var x = 1\n    unsafe \{\n        assert(same(addr(x), addr(x)))\n    \}\n\}\n", true), "operations on incompatible pointers are prohibited")
        var x = 1
        unsafe {
            let p : int const? = addr(x)
            let q : int? = addr(x)
            t |> equal(intptr(p) == intptr(q), true)
            t |> equal(p != null, true)
        }
    }
    t |> run("a `let` pointer parameter neither returns as a pointer nor copies its pointee pointer out") @(t : T?) {
        child_rejects(t, "return_let", daslang_child("return_let", "options gen2\ndef pass_back(p : int?) : int? \{\n    return p\n\}\n", true), "incompatible return type")
        child_rejects(t, "copy_through_let", daslang_child("copy_through_let", "options gen2\nvar g : int?\ndef keep(pp : int??) \{\n    unsafe \{\n        g = deref(pp)\n    \}\n\}\n", true), "can only copy compatible type")
        let as_var = daslang_child("return_var", "options gen2\ndef pass_back(var p : int?) : int? \{\n    return p\n\}\nvar g : int?\ndef keep(var pp : int??) \{\n    unsafe \{\n        g = deref(pp)\n    \}\n\}\n", true)
        t |> equal(as_var.rc, 0, as_var.out)
    }
}
