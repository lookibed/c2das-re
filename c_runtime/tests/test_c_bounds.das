options gen2
require dastest/testing_boost public
require c_runtime/c_bounds
require strings
require daslib/rtti

var g_k : int

def checked(k : auto; n : int) : bool {
    var caught = false
    try {
        end_index(k, n)
    } recover {
        caught = true
    }
    return caught
}

[test]
def test_c_bounds(t : T?) {
    t |> run("end_index takes every index up to the length, in each index type") @(t : T?) {
        t |> equal(end_index(3, 3), 3)
        t |> equal(end_index(0u, 3), 0u)
        t |> equal(end_index(2l, 3), 2l)
        t |> equal(end_index(3ul, 3), 3ul)
    }
    t |> run("as converted: `&a[k]` is the decayed array plus the checked index (F45)") @(t : T?) {
        var a : int[3]
        g_k = 3
        unsafe {
            let p0 = addr(a[0])
            let end = addr(a[0]) + end_index(g_k, 3)
            t |> equal(end - p0, 3l)
        }
    }
    t |> run("end_index past the length or below zero panics as the range check does") @(t : T?) {
        t |> equal(checked(4, 3), true)
        t |> equal(checked(-1, 3), true)
        t |> equal(checked(-1l, 3), true)
        t |> equal(checked(4u, 3), true)
        t |> equal(checked(18446744073709551615ul, 3), true)
        t |> equal(checked(3, 3), false)
    }
    t |> run("the panic carries das's own range-check wording") @(t : T?) {
        var message = ""
        g_k = 5
        try {
            end_index(g_k, 3)
        } recover {
            message = "{this_context().last_exception}"
        }
        t |> equal(find(message, "index out of range, 5 of 3") >= 0, true, message)
    }
}
