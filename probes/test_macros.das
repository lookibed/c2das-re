options gen2
require dastest/testing_boost public
require _probe_macros
require daslib/apply

def vsum_impl(n : int; va : auto) : int {
    var acc = n   // nolint:LINT003 - written inside the apply block
    apply(va) $(name, field) {
        acc += int(field)
    }
    return acc
}

[c_function]
def blit(src_in : uint8?; var dst_in : uint8?; n_in : int) {
    var src = src_in
    var dst = dst_in
    var n = n_in
    while (n != 0) {
        n = n - 1
        deref(dst) = deref(src)
        dst = dst + 1
        src = src + 1
    }
}

def param_copy_types(src_in : uint8?; var dst_in : uint8?) : string {
    var _src = src_in
    var _dst = dst_in
    return "{typeinfo typename(src_in)}|{typeinfo typename(_src)}|{typeinfo typename(dst_in)}|{typeinfo typename(_dst)}"
}

[test]
def test_macros(t : T?) {
    t |> run("a function annotation wraps the whole body in unsafe") @(t : T?) {
        var a : uint8[4] = fixed_array(uint8(1), uint8(2), uint8(3), uint8(4))
        var b : uint8[4]
        unsafe {
            blit(addr(a[0]), addr(b[0]), 4)
        }
        t |> equal(int(b[3]), 4)
    }
    t |> run("a pointer written through must be a var parameter: a const pointer copies as const pointee") @(t : T?) {
        var a, b : uint8[1]
        unsafe {
            t |> equal(param_copy_types(addr(a[0]), addr(b[0])), "uint8? const|uint8 const?|uint8?|uint8?")
        }
    }
    t |> run("a call macro tuples the trailing arguments, including one and none") @(t : T?) {
        t |> equal(vsum(100, 1, 2, 3), 106)
        t |> equal(vsum(100, 5), 105)
        t |> equal(vsum(100), 100)
    }
}
