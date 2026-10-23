options gen2
options persistent_heap

require dastest/testing_boost

//! The lowerings of a general C `for` (docs/lowering-examples.md, "General for") against each
//! other and against the native range loop: the increment-first flag that every `for` can take,
//! the body-block `finally` that a body without `break` can take, and the increment as the last
//! statement that a body without `continue` takes.

let N = 1000

// read at run time, so no call folds at compile time
var n_rt = N

def flag_form(n : int) : int {
    var acc = 0
    var i = 0
    var passed_once = false
    while (true) {
        if (passed_once) {
            i++
        }
        passed_once = true
        if (!(i < n)) {
            break
        }
        acc = (acc * 31 + i) & 0xFFFF
    }
    return acc
}

def finally_form(n : int) : int {
    var acc = 0
    var i = 0
    while (i < n) {
        {
            acc = (acc * 31 + i) & 0xFFFF
        } finally {
            i++
        }
    }
    return acc
}

def trailing_form(n : int) : int {
    var acc = 0
    var i = 0
    while (i < n) {
        acc = (acc * 31 + i) & 0xFFFF
        i++
    }
    return acc
}

def range_form(n : int) : int {
    var acc = 0
    for (i in range(n)) {
        acc = (acc * 31 + i) & 0xFFFF
    }
    return acc
}

[benchmark]
def for_shapes(b : B?) {
    let want = range_form(n_rt)
    b |> run("flag/{N}", N) {
        b |> equal(flag_form(n_rt), want)
    }
    b |> run("finally/{N}", N) {
        b |> equal(finally_form(n_rt), want)
    }
    b |> run("trailing/{N}", N) {
        b |> equal(trailing_form(n_rt), want)
    }
    b |> run("range/{N}", N) {
        b |> equal(range_form(n_rt), want)
    }
}
