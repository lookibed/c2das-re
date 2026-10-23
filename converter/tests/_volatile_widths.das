options gen2
require c_runtime/c_volatile

//! The program `test_tier_facts.das` runs at every tier: for each width `c_runtime/c_volatile`
//! overloads, a global read in a loop that never changes it and a global written in a loop with
//! the value it holds, plain and through `c_volatile_load`/`c_volatile_store`. A tier that
//! optimizes hoists the plain read and sinks the plain store, so each plain loop takes no time;
//! a volatile access is made on every pass. A line per width: its name, the nanoseconds of the
//! plain and the volatile read loop and of the plain and the volatile store loop, and the passes
//! each read loop counted.

var private count : int = 4000000
var private target = 1
var private g_i8 = int8(3)
var private g_u8 = uint8(3)
var private g_i16 = int16(3)
var private g_u16 = uint16(3)
var private g_i32 = 3
var private g_u32 = 3u
var private g_i64 = 3l
var private g_u64 = 3ul
var private g_f32 = 3.0f
var private g_f64 = 3.0lf
var private g_bool = true
var private g_ptr : int? = null

def private plain_load(g : auto(TT) const&; other : TT; n : int) : int {
    var c = 0
    for (_i in range(n)) {
        if (g != other) {
            c++
        }
    }
    return c
}

def private volatile_load(g : auto(TT) const&; other : TT; n : int) : int {
    var c = 0
    for (_i in range(n)) {
        if (c_volatile_load(g) != other) {
            c++
        }
    }
    return c
}

def private plain_store(var g : auto(TT)&; var v : TT; n : int) {
    for (_i in range(n)) {
        g = v
    }
}

def private volatile_store(var g : auto(TT)&; var v : TT; n : int) {
    for (_i in range(n)) {
        c_volatile_store(g, v)
    }
}

def private timed(name : string; var g : auto(TT)&; other : TT; n : int) {
    var t0 = ref_time_ticks()
    let plain_count = plain_load(g, other, n)
    let plain_load_ns = get_time_nsec(t0)
    t0 = ref_time_ticks()
    let volatile_count = volatile_load(g, other, n)
    let volatile_load_ns = get_time_nsec(t0)
    t0 = ref_time_ticks()
    plain_store(g, g, n)
    let plain_store_ns = get_time_nsec(t0)
    t0 = ref_time_ticks()
    volatile_store(g, g, n)
    let volatile_store_ns = get_time_nsec(t0)
    print("{name} {plain_load_ns} {volatile_load_ns} {plain_store_ns} {volatile_store_ns} {plain_count} {volatile_count}\n")
}

[export]
def main : int {
    let n = c_volatile_load(count)
    timed("int8", g_i8, int8(5), n)
    timed("uint8", g_u8, uint8(5), n)
    timed("int16", g_i16, int16(5), n)
    timed("uint16", g_u16, uint16(5), n)
    timed("int", g_i32, 5, n)
    timed("uint", g_u32, 5u, n)
    timed("int64", g_i64, 5l, n)
    timed("uint64", g_u64, 5ul, n)
    timed("float", g_f32, 5.0f, n)
    timed("double", g_f64, 5.0lf, n)
    timed("bool", g_bool, false, n)
    timed("pointer", g_ptr, unsafe(addr(target)), n)
    return 0
}
