options gen2
require dastest/testing_boost public
require strings
require c_runtime/c_volatile
require ../../probes/_daslang_child.das

var private counter : int = 41
var private flag : bool = true
var private small : uint8 = 200u8
var private wide : int64 = -3l
var private ratio : double = 0.5lf
var private where_to : int? = null

def private twice(v : int) : int => v * 2

def private thrice(v : int) : int => v * 3

def private plus_one(x : int) : int => c_volatile_load(x) + 1

// a program's own function under the fallback's name (a unit `c.c` with a `static volatile_read`
// lands here): the macro's expansion names the module's, never this one
def c_volatile_read(var p : int?) : int? {
    unsafe {
        return p + 1
    }
}

// a reinterpret of a crt call's `uint64` result straight to a pointer, which the interpreter
// refuses and `c_volatile_load` avoids by landing the bits in a local first
let REINTERPRET_SOURCE = "options gen2\nrequire crt\nvar g : int = 7\nvar p : int? = null\n[export]\ndef main \{\n    unsafe \{\n        p = addr(g)\n        let q = reinterpret<int?>(crt::c_volatile_load_u64(reinterpret<uint64 const?>(addr(p))))\n        print(\"\{*q\}\\n\")\n    \}\n\}\n"

// a store of a 16-byte value, which no forwarder width holds
let WIDE_STORE_SOURCE = "options gen2\nrequire c_runtime/c_volatile\nvar v : float4\n[export]\ndef main \{\n    c_volatile_store(v, float4(1.0))\n\}\n"

[test]
def test_c_volatile(t : T?) {
    t |> run("a by-value parameter's read takes the fallback: a constant argument from a plain caller compiles under the optimizer") @(t : T?) {
        t |> equal(plus_one(41), 42)
        let v = 2
        t |> equal(plus_one(v), 3)
    }
    t |> run("c_volatile_load and c_volatile_store take the object by reference, each C scalar width") @(t : T?) {
        t |> equal(c_volatile_load(counter), 41)
        c_volatile_store(counter, c_volatile_load(counter) + 1)
        t |> equal(counter, 42)
        t |> equal(c_volatile_load(flag), true)
        c_volatile_store(flag, false)
        t |> equal(flag, false)
        c_volatile_store(small, uint8(int(c_volatile_load(small)) + 60))
        t |> equal(small, 4u8)
        c_volatile_store(wide, c_volatile_load(wide) * 2l)
        t |> equal(wide, -6l)
        c_volatile_store(ratio, c_volatile_load(ratio) + 1.0lf)
        t |> equal(ratio, 1.5lf)
        var fields = fixed_array(int8(1), int8(2))
        c_volatile_store(fields[1], int8(int(c_volatile_load(fields[1])) - 3))
        t |> equal(fields[1], int8(-1))
        var halves = fixed_array(int16(1), int16(2))
        var uhalves = fixed_array(uint16(1), uint16(2))
        c_volatile_store(halves[0], int16(-7))
        c_volatile_store(uhalves[0], uint16(65535))
        t |> equal(c_volatile_load(halves[0]), int16(-7))
        t |> equal(c_volatile_load(uhalves[0]), uint16(65535))
        var unsigned = 3u
        var big = 5ul
        var single = 0.25f
        c_volatile_store(unsigned, c_volatile_load(unsigned) * 2u)
        c_volatile_store(big, c_volatile_load(big) + 1ul)
        c_volatile_store(single, c_volatile_load(single) * 4.0f)
        t |> equal(unsigned, 6u)
        t |> equal(big, 6ul)
        t |> equal(single, 1.0f)
    }
    t |> run("a pointer and a function value go through their eight bytes") @(t : T?) {
        var target = 9
        c_volatile_store(where_to, unsafe(addr(target)))
        t |> equal(*c_volatile_load(where_to), 9)
        var hook : function<(v : int) : int> = @@twice
        t |> equal(invoke(c_volatile_load(hook), 4), 8)
        c_volatile_store(hook, @@thrice)
        t |> equal(invoke(hook, 4), 12)
    }
    t |> run("the interpreter refuses a reinterpret of a crt call's uint64 result to a pointer; the JIT takes it") @(t : T?) {
        let interp = runtime_child("volatile_reinterpret", REINTERPRET_SOURCE, false)
        t |> equal(interp.out |> find("typed eval on wrong extern return kind") >= 0, true, interp.out)
        let jit = runtime_child_flags("volatile_reinterpret_jit", REINTERPRET_SOURCE, jit_flags())
        t |> equal(jit.rc, 0, jit.out)
        t |> equal(program_output(jit.out), "7\n", jit.out)
    }
    t |> run("a store of a width no forwarder holds is refused at compile time") @(t : T?) {
        child_rejects(t, "volatile_wide_store", runtime_child("volatile_wide_store", WIDE_STORE_SOURCE, true), "c_volatile_store: a scalar, a pointer or a function value")
    }
}
