options gen2
require dastest/testing_boost public

var g_idx : int

def read_idx : int {
    return g_idx
}

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
