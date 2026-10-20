options gen2

module c_sort public

//! C's `qsort` and `bsearch` over raw bytes, in C's own signatures: `n` elements of `size`
//! bytes each from `base`, ordered by the converted C comparator, which takes the two element
//! addresses as C declares them. The CRT's own `qsort` cannot call back into das, so `qsort` is
//! the runtime's byte sort (`__builtin_sort_any_cblock`, the engine under daslib's `sort`) with
//! the comparator in a block; it is unstable, as C allows. `bsearch` is a binary search.

//! The comparator C passes to `qsort` and `bsearch`: `int cmp(const void *, const void *)`
//! as the converter spells a function pointer, every data pointer position `var`.
typedef CCompare = function<(var a : void?; var b : void?) : int>

// the runtime's sort counts elements and bytes in `int`
let private SORT_LIMIT = 0x7fffffffu

//! C's `qsort`: sorts `n` elements of `size` bytes from `base` in place, by `cmp`.
def c_qsort(base : void?; n : uint64; size : uint64; cmp : CCompare) {
    if (n < 2ul) {
        return
    }
    if (n > uint64(SORT_LIMIT) || size > uint64(SORT_LIMIT)) {
        panic("c_qsort: {n:d} elements of {size:d} bytes exceed the runtime sort's int counts")
    }
    __builtin_sort_any_cblock(base, int(size), int(n)) $(var a, b : void?) : bool {
        return invoke(cmp, a, b) < 0
    }
}

// the address of element `i`
def private element_at(base : uint8?; i : int64; size : uint64) : void? {
    let at = unsafe(base + int64(uint64(i) * size))
    return unsafe(reinterpret<void?>(at))
}

//! C's `bsearch`: the address of an element of the `n` sorted ones from `base` that `cmp`
//! finds equal to `key`, called as `cmp(key, element)`; `null` when none is.
def c_bsearch(var key : void?; base : void?; n : uint64; size : uint64; cmp : CCompare) : void? {
    let bytes = unsafe(reinterpret<uint8?>(base))
    var lo = 0l
    var hi = int64(n)
    while (lo < hi) {
        let mid = lo + (hi - lo) / 2l
        var elem = element_at(bytes, mid, size)
        let r = invoke(cmp, key, elem)
        if (r == 0) {
            return elem
        }
        if (r < 0) {
            hi = mid
        } else {
            lo = mid + 1l
        }
    }
    return null
}
