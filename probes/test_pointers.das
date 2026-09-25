options gen2
require dastest/testing_boost public

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
