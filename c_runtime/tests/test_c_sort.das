options gen2
require dastest/testing_boost public
require ../../probes/_daslang_child.das
require crt
require strings
require daslib/algorithm
require c_runtime/c_function
require c_runtime/c_sort

//! `qsort` and `bsearch` as the converter emits them: the C call with its arguments as C gives
//! them and the converted C comparator.

struct Rec {
    key : int
    name : uint8[12]
}

// the array an inconsistent comparator runs over, and how many addresses it saw within a page
// past either end: a scan that ran off the array (the runtime's sort also passes the address
// of its own pivot copy, which lies elsewhere)
var watched_base : uint64
var watched_end : uint64
var strays : int

// `int cmp_int(const void *a, const void *b) { return *(const int *)a - *(const int *)b; }`
[c_function]
def cmp_int(var a : void?; var b : void?) : int {
    return deref(reinterpret<int?>(a)) - deref(reinterpret<int?>(b))
}

[c_function]
def cmp_rec(var a : void?; var b : void?) : int {
    let x : Rec? = reinterpret<Rec?>(a)
    let y : Rec? = reinterpret<Rec?>(b)
    return x.key < y.key ? -1 : x.key > y.key ? 1 : 0
}

// `int cmp_str(const void *a, const void *b) { return strcmp(*(char **)a, *(char **)b); }`
[c_function]
def cmp_str(var a : void?; var b : void?) : int {
    return crt::strcmp(deref(reinterpret<uint8 ??>(a)), deref(reinterpret<uint8 ??>(b)))
}

// orders elements of any size by their first byte
[c_function]
def cmp_first_byte(var a : void?; var b : void?) : int {
    return int(deref(reinterpret<uint8?>(a))) - int(deref(reinterpret<uint8?>(b)))
}

def note(a, b : void?) {
    for (p in fixed_array(intptr(a), intptr(b))) {
        if ((p < watched_base && p + 4096ul >= watched_base) || (p >= watched_end && p < watched_end + 4096ul)) {
            strays++
        }
    }
}

// comparators inconsistent with themselves: always less, always greater
def cmp_less(var a : void?; var b : void?) : int {
    note(a, b)
    return -1
}

def cmp_greater(var a : void?; var b : void?) : int {
    note(a, b)
    return 1
}

// a comparator that sorts a small array of its own on every call
[c_function]
def cmp_reentrant(var a : void?; var b : void?) : int {
    var inner = fixed_array(3, 1, 2)
    c_qsort(addr<void?>(inner[0]), 3ul, 4ul, @@cmp_int)
    return inner[0] == 1 ? cmp_int(a, b) : 99
}

// `(i * 7919) % 1009` for `i < n`: distinct for n up to 1009, with no run in order
def scrambled(n : int) : array<int> {
    var arr <- [for (i in range(n)); (i * 7919) % 1009]
    return <- arr
}

def sort_ints(var arr : array<int>; cmp : CCompare) {
    if (!empty(arr)) {
        c_qsort(unsafe(addr<void?>(arr[0])), uint64(long_length(arr)), 4ul, cmp)
    }
}

// sorts `n` elements of `size` bytes, every byte of each its key, and checks they are ordered
// and moved whole
[c_function]
def sorts_elements(t : T?; n, size : int) {
    var bytes = reinterpret<uint8?>(crt::malloc(uint64(n * size)))
    for (i in range(n)) {
        for (j in range(size)) {
            bytes[i * size + j] = uint8((i * 7919) % 251)
        }
    }
    c_qsort(reinterpret<void?>(bytes), uint64(n), uint64(size), @@cmp_first_byte)
    var ok = true
    for (i in range(n)) {
        let key = int(bytes[i * size])
        ok = ok && (i == 0 || int(bytes[(i - 1) * size]) <= key)
        for (j in range(size)) {
            ok = ok && int(bytes[i * size + j]) == key
        }
    }
    t |> success(ok, "n = {n}, size = {size}")
    crt::free(bytes)
}

// sorts `n` ints with a comparator that never agrees with itself; no address it sees lies just
// outside the array
def stays_inside(t : T?; n : int; cmp : CCompare) {
    var arr <- scrambled(n)
    watched_base = intptr(unsafe(addr(arr[0])))
    watched_end = watched_base + uint64(n * 4)
    strays = 0
    sort_ints(arr, cmp)
    t |> equal(strays, 0, "n = {n}")
}

[test]
def test_c_qsort(t : T?) {
    t |> run("qsort orders ints from no element to past any small-array threshold") @(t : T?) {
        for (n in fixed_array(0, 1, 2, 5, 15, 16, 17, 41, 1000)) {
            var inscope arr <- scrambled(n)
            sort_ints(arr, @@cmp_int)
            t |> success(is_sorted(arr), "n = {n}: {arr}")
            t |> equal(length(arr), n)
        }
    }
    t |> run("qsort keeps every key of a run of equal ones and of a reversed array") @(t : T?) {
        var arr <- [for (i in range(64)); i % 3 == 0 ? 7 : 64 - i]
        sort_ints(arr, @@cmp_int)
        t |> success(is_sorted(arr), "{arr}")
        t |> equal(length([for (v in arr); v; where v == 7]), 22)
    }
    t |> run("qsort moves a record holding an array by its bytes, sorted by a field") @(t : T?) {
        var recs : Rec[20]
        for (i in range(20)) {
            recs[i].key = (i * 13) % 20
            recs[i].name[0] = uint8('a' + recs[i].key)
        }
        unsafe {
            c_qsort(addr<void?>(recs[0]), 20ul, uint64(typeinfo sizeof(type<Rec>)), @@cmp_rec)
        }
        for (i in range(20)) {
            t |> equal(recs[i].key, i)
            t |> equal(int(recs[i].name[0]), 'a' + i)
        }
    }
    t |> run("qsort orders C strings through strcmp from the CRT") @(t : T?) {
        var words : uint8? [4]
        unsafe {
            words[0] = reinterpret<uint8?>("pear")
            words[1] = reinterpret<uint8?>("apple")
            words[2] = reinterpret<uint8?>("fig")
            words[3] = reinterpret<uint8?>("banana")
            c_qsort(addr<void?>(words[0]), 4ul, 8ul, @@cmp_str)
            t |> equal(crt::strcmp(words[0], reinterpret<uint8?>("apple")), 0)
            t |> equal(crt::strcmp(words[1], reinterpret<uint8?>("banana")), 0)
            t |> equal(crt::strcmp(words[3], reinterpret<uint8?>("pear")), 0)
        }
    }
    t |> run("qsort moves elements of 1, 3, 7, 257 and 4096 bytes whole") @(t : T?) {
        for (size in fixed_array(1, 3, 7, 257, 4096)) {
            sorts_elements(t, 40, size)
        }
    }
    t |> run("a comparator that never agrees with itself drives no scan off either end of the array") @(t : T?) {
        for (n in range(2, 18)) {
            stays_inside(t, n, @@cmp_less)
            stays_inside(t, n, @@cmp_greater)
        }
        stays_inside(t, 1000, @@cmp_less)
        stays_inside(t, 1000, @@cmp_greater)
    }
    t |> run("qsort of one element returns whatever its size, and past the runtime's int counts panics in decimal") @(t : T?) {
        var one = 5
        unsafe {
            c_qsort(addr<void?>(one), 1ul, 0x100000000ul, @@cmp_int)
        }
        t |> equal(one, 5)
        var message = ""
        try {
            unsafe {
                c_qsort(addr<void?>(one), 2ul, 0x100000000ul, @@cmp_int)
            }
        } recover {
            message = "panicked"
        }
        t |> equal(message, "panicked")
        let r = runtime_child("sort_limit", "options gen2\nrequire c_runtime/c_sort\ndef cmp(var a : void?; var b : void?) : int => 0\n[export]\ndef main \{\n    var x = 1\n    unsafe \{\n        c_qsort(addr<void?>(x), 2ul, 4294967296ul, @@cmp)\n    \}\n\}\n", false)
        t |> equal(r.out |> find("2 elements of 4294967296 bytes") >= 0, true, r.out)
    }
    t |> run("a comparator may sort an array of its own") @(t : T?) {
        var arr <- scrambled(50)
        sort_ints(arr, @@cmp_reentrant)
        t |> success(is_sorted(arr), "{arr}")
    }
}

[c_function]
def find_int(key : int; arr : array<int>) : int {
    var k = key
    if (empty(arr)) {
        return c_bsearch(addr<void?>(k), null, 0ul, 4ul, @@cmp_int) == null ? -1 : -2
    }
    let hit = c_bsearch(addr<void?>(k), addr<void?>(arr[0]), uint64(long_length(arr)), 4ul, @@cmp_int)
    return hit == null ? -1 : int(intptr(hit) - intptr(addr(arr[0]))) / 4
}

[test]
def test_c_bsearch(t : T?) {
    t |> run("bsearch finds the first, the last and a middle key, and misses below, above and between") @(t : T?) {
        var arr <- [for (i in range(41)); i * 2]
        t |> equal(find_int(0, arr), 0)
        t |> equal(find_int(80, arr), 40)
        t |> equal(find_int(34, arr), 17)
        t |> equal(find_int(-1, arr), -1)
        t |> equal(find_int(81, arr), -1)
        t |> equal(find_int(35, arr), -1)
    }
    t |> run("bsearch of no element misses, and among duplicates finds one of them") @(t : T?) {
        var none : array<int>
        t |> equal(find_int(3, none), -1)
        var dups <- [1, 2, 2, 2, 3]
        let at = find_int(2, dups)
        t |> success(at >= 1 && at <= 3, "{at}")
    }
}

[test]
def test_c_sort_controls(t : T?) {
    t |> run("a comparator with `let` pointer parameters does not type against qsort") @(t : T?) {
        let r = runtime_child("sort_let_cmp", "options gen2\nrequire c_runtime/c_sort\ndef cmp(a : void?; b : void?) : int => 0\n[export]\ndef main \{\n    var x = 1\n    unsafe \{\n        c_qsort(addr<void?>(x), 1ul, 4ul, @@cmp)\n    \}\n\}\n", true)
        child_rejects(t, "sort_let_cmp", r, "no matching functions or generics: c_qsort")
    }
    t |> run("the CRT binds no qsort, since it cannot call back into das") @(t : T?) {
        let r = runtime_child("sort_crt", "options gen2\nrequire crt\ndef cmp(a : void?; b : void?) : int => 0\n[export]\ndef main \{\n    var x = 1\n    unsafe \{\n        crt::qsort(addr<void?>(x), 1ul, 4ul, @@cmp)\n    \}\n\}\n", true)
        child_rejects(t, "sort_crt", r, "no matching functions or generics: crt::qsort")
    }
}
