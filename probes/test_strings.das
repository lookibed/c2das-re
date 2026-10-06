options gen2
require dastest/testing_boost public

[test]
def test_strings(t : T?) {
    t |> run("a das literal is a NUL-terminated byte-walkable interned C string") @(t : T?) {
        unsafe {
            let msg = reinterpret<uint8?>("hello")
            var n = 0
            while (deref(msg + n) != uint8(0)) {
                n++
            }
            t |> equal(n, 5)
            t |> equal(int(deref(msg)), 'h')
            let again = reinterpret<uint8?>("hello")
            t |> equal(intptr(msg) == intptr(again), true)
        }
    }
    t |> run("the empty das literal is a null pointer, not a pointer to a NUL") @(t : T?) {
        unsafe {
            t |> equal(reinterpret<uint8?>("") == null, true)
            t |> equal(reinterpret<uint8?>("x") != null, true)
        }
    }
    t |> run("reinterpret<string> bridges a NUL-terminated buffer as an alias") @(t : T?) {
        var buf : uint8[8]
        buf[0] = uint8('a')
        buf[1] = uint8('b')
        buf[2] = uint8('c')
        unsafe {
            let s = reinterpret<string>(addr(buf[0]))
            t |> equal(length(s), 3)
            t |> equal(s == "abc", true)
            buf[1] = uint8('X')
            t |> equal(s == "aXc", true)
        }
    }
}
