// The cost of one `[c_union]` member read under the interpreter: the generated `operator . i`
// (a cross-module call the inliner refuses, `generated` and a property) against the same read
// spelled inline as the accessor's own body, and against a plain struct field.
options gen2
require c_runtime/c_union

[c_union]
struct V {
    gc : void?
    i : int64
    n : double
}

struct TV {
    value_ : V
    tt_ : uint8
}

struct PV {
    i : int64
    tt_ : uint8
}

let ROUNDS = 40000

def via_accessor(var vals : TV[64]) : int64 {
    var acc = 0l
    for (r in range(ROUNDS)) {
        for (k in range(64)) {
            acc += vals[k].value_.i ^ int64(r)
        }
    }
    return acc
}

def via_inline(var vals : TV[64]) : int64 {
    var acc = 0l
    for (r in range(ROUNDS)) {
        for (k in range(64)) {
            unsafe {
                acc += *addr<int64?>(vals[k].value_._storage) ^ int64(r)
            }
        }
    }
    return acc
}

def via_plain(var vals : PV[64]) : int64 {
    var acc = 0l
    for (r in range(ROUNDS)) {
        for (k in range(64)) {
            acc += vals[k].i ^ int64(r)
        }
    }
    return acc
}

[export]
def main {
    var vals : TV[64]
    var plain : PV[64]
    for (k in range(64)) {
        vals[k].value_.i = int64(k)
        plain[k].i = int64(k)
    }
    var t0 = ref_time_ticks()
    let a = via_accessor(vals)
    let ta = get_time_usec(t0)
    t0 = ref_time_ticks()
    let b = via_inline(vals)
    let tb = get_time_usec(t0)
    t0 = ref_time_ticks()
    let c = via_plain(plain)
    let tc = get_time_usec(t0)
    print("accessor {ta} inline {tb} plain {tc} check {a == b && b == c}\n")
}
