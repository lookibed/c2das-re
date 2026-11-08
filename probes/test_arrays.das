options gen2
require dastest/testing_boost public
require _daslang_child

var g_idx : int

def read_idx : int => g_idx

[test]
def test_arrays(t : T?) {
    t |> run("fixed_array literal, multi-dim literal and zero init") @(t : T?) {
        let full : int[3] = fixed_array(1, 2, 3)
        t |> equal(full[2], 3)
        let m : int[2][3] = fixed_array(fixed_array(1, 2, 3), fixed_array(4, 5, 6))
        t |> equal(m[1][2], 6)
        var sparse : int[8]
        t |> equal(sparse[5], 0)
        sparse[5] = 9
        t |> equal(sparse[5], 9)
        let _bracket = [1, 2, 3]
        t |> equal(typeinfo typename(_bracket), "array<int> const")
    }
    t |> run("row pointer to a fixed array strides by the row size") @(t : T?) {
        var m : int[2][3] = fixed_array(fixed_array(1, 2, 3), fixed_array(4, 5, 6))
        unsafe {
            let row = addr(m[1])
            t |> equal(deref(row)[2], 6)
            let row0 = addr(m[0])
            t |> equal(int(intptr(row) - intptr(row0)), 12)
            t |> equal(deref(row0 + 1)[0], 4)
        }
    }
    t |> run("decay to element pointer, scaled arithmetic and negative index") @(t : T?) {
        var m : int[2][3] = fixed_array(fixed_array(1, 2, 3), fixed_array(4, 5, 6))
        unsafe {
            let p0 = addr(m[0][0])
            let p5 = p0 + 5
            t |> equal(deref(p5), 6)
            t |> equal(p5 - p0, 5l)
            t |> equal(deref(p5 + (-2)), 4)
        }
    }
    t |> run("out-of-bounds index panics and try/recover catches it") @(t : T?) {
        var big : int[3]
        var caught = false
        g_idx = 5
        try {
            big[read_idx()] = 1
        } recover {
            caught = true
        }
        t |> equal(caught, true)
    }
}

// the das facts the csmith differential found (docs/probe-findings.md F40 to F46)
[test]
def test_csmith_arrays(t : T?) {
    t |> run("an all-null fixed_array is a void? array no pointer array takes; fixed_array<T?> names its element") @(t : T?) {
        child_rejects(t, "null_array", daslang_child("null_array", "options gen2\nvar g : int? [2] = fixed_array(null, null)\n[export]\ndef main \{\n    assert(g[0] == null)\n\}\n", true), "int?[2] -const = void?[2]")
        var x = 7
        var ptrs : int? [2] = fixed_array<int?>(null, null)
        var nested : int? [2][2] = fixed_array(fixed_array<int?>(null, null), fixed_array<int?>(null, null))
        unsafe {
            ptrs[1] = addr(x)
            nested[1][0] = addr(x)
        }
        t |> equal(ptrs[0] == null && deref(ptrs[1]) == 7, true)
        t |> equal(deref(nested[1][0]), 7)
    }
    t |> run("das indexes by int, int64, uint or uint64 alone: a small integer widens to int") @(t : T?) {
        child_rejects(t, "index_int8", daslang_child("index_int8", "options gen2\n[export]\ndef main \{\n    let a = fixed_array(1, 2, 3)\n    let i = int8(1)\n    assert(a[i] == 2)\n\}\n", true), "index type must be 'int', 'int64', 'uint', or 'uint64', not 'int8")
        let a = fixed_array(1, 2, 3)
        let i = uint8(2)
        t |> equal(a[int(i)], 3)
    }
    t |> run("addr(a[N]) one past the end trips the range check; the decayed array plus N is the address") @(t : T?) {
        var big : int[3]
        var caught = false
        g_idx = 3
        unsafe {
            try {
                let end = addr(big[read_idx()])
                t |> equal(end == null, false)
            } recover {
                caught = true
            }
            t |> equal(caught, true)
            let p0 = addr(big[0])
            let end = addr(big[0]) + g_idx
            t |> equal(end - p0, 3l)
            t |> equal(int(intptr(end) - intptr(p0)), 12)
            let wide = addr(big[0]) + int64(g_idx)
            t |> equal(intptr(wide) == intptr(end), true)
        }
    }
    t |> run("k == N ? addr(a[0]) + N : addr(a[k]) is the address one past the end at N and range-checks a negative or past index (F45)") @(t : T?) {
        var big : int[3]
        unsafe {
            for (k in [3, 2, -1, 4]) {
                g_idx = k
                var caught = false
                try {
                    let p = g_idx == 3 ? addr(big[0]) + 3 : addr(big[g_idx])
                    t |> equal(int(intptr(p) - intptr(addr(big[0]))), 4 * k)
                } recover {
                    caught = true
                }
                t |> equal(caught, k < 0 || k > 3, "{k}")
            }
        }
    }
    t |> run("a pointer steps by an int, uint, int64 or uint64 offset; uint64 of a negative is past any length") @(t : T?) {
        var big : int[3]
        g_idx = 3
        unsafe {
            let p0 = addr(big[0])
            t |> equal(addr(big[0]) + g_idx - p0, 3l)
            t |> equal(addr(big[0]) + uint(g_idx) - p0, 3l)
            t |> equal(addr(big[0]) + int64(g_idx) - p0, 3l)
            t |> equal(addr(big[0]) + uint64(g_idx) - p0, 3l)
        }
        t |> equal(uint64(-1) > uint64(3), true)
        t |> equal(uint64(-1l) > uint64(3), true)
        t |> equal(uint64(3u) > uint64(3), false)
    }
    t |> run("in a global initializer an address under `+` takes its own unsafe") @(t : T?) {
        child_rejects(t, "global_past_end", daslang_child("global_past_end", "options gen2\nvar a : int[3] = fixed_array(1, 2, 3)\nvar e : int? = unsafe(addr(a[0]) + 3)\n[export]\ndef main \{\n    assert(e != null)\n\}\n", true), "31000")
        let nested = daslang_child("global_past_end_nested", "options gen2\nvar a : int[3] = fixed_array(1, 2, 3)\nvar e : int? = unsafe(unsafe(addr(a[0])) + 3)\n[export]\ndef main \{\n    assert(int(intptr(e) - intptr(unsafe(addr(a[0])))) == 12)\n\}\n", false)
        t |> equal(nested.rc, 0, nested.out)
    }
}
