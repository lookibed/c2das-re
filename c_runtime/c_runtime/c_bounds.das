options gen2

module c_bounds public

//! `end_index(k, n)`: the index of C's `&a[k]` into an array of `n` elements, checked the way
//! das checks `a[k]` but with `n` itself allowed, since C forms the address one past the end.
//! The compare is unsigned, so a negative `k` fails as das's own range check does.
def end_index(k : auto(I); n : int) : I {
    if (uint64(k) > uint64(n)) {
        panic("index out of range, {k} of {n}")
    }
    return k
}
