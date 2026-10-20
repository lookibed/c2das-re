options gen2

var outside = 0

def rangeable(n : int) : int {
    var s = 0
    var i = 0
    while (i < n) {
        s += i
        i++
    }
    var j = 0
    while (j <= 10) {
        {
            if (j == 3) {
                continue
            }
            s += j
        } finally {
            j += 2
        }
    }
    var k = n
    while (k >= 0) {
        s += k
        k -= 3
    }
    var m = n
    while (m > 0) {
        --m
    }
    var u = 0
    while (u < n) {
        var w = 0
        while (w < 2) {
            w++
            continue
        }
        for (z in range(2)) {
            if (z == 1) {
                continue
            }
        }
        ++u
    }
    return s
}

// each loop misses one condition of the definition
def not_rangeable(n_in : int) : int {
    var n = n_in
    let s = 2
    var a = 0
    while (a < n) {
        a++
        if (a == 2) {
            continue
        }
        a++
    }
    var b = 0
    while (b < n) {
        b = b + 1
        b++
    }
    var c = 0
    while (c < n) {
        c += s
    }
    var d = 0
    while (d < n) {
        n -= 2
        d++
    }
    var e = 0
    while (e < n) {
        e--
    }
    var f = 0
    while (f != n) {
        f++
    }
    while (outside < 10) {
        outside++
    }
    var x = 0.0
    while (x < 3.0) {
        x++
    }
    return s
}

// each loop misses one condition of the definition, by its step
def not_rangeable_steps(n : int; flag : bool) : int {
    var s = 0
    var g = 0 // nolint:LINT003 - the loop never steps it, which is the case under test
    while (g < n) {
    }
    var h = 0
    while (h < n) {
        {
            s += h
        } finally {
            h++
            s++
        }
    }
    var i = 0 // nolint:LINT003 - the loop never steps it, which is the case under test
    while (i < n) {
        {
            s += i
        }
    }
    while (flag) {
        break
    }
    var j = 0
    while (j < n) {
        j += 0
    }
    var k = 0 // nolint:LINT003 - the loop never steps it, which is the case under test
    while (k < n) {
        s++
    }
    var l = 0
    while (l < n) {
        l *= 2
    }
    var m = 0
    while (m < n) {
        m := 3
        m++
    }
    var o = 0
    var other = 5 // nolint:LINT003 - a move takes a var source
    while (o < n) {
        o <- other
        o++
    }
    return s
}

def jumps(n : int) : int {
    var s = 0
    label 0:
    s++
    if (s < n) {
        goto label 0
    }
    label 1:
    return s
}

struct Box {
    n : int
}

def bump_ref(var x : int&) {
    x++
}

def bump_ptr(var x : int?) {
    deref(x)++
}

// a loop the counter must not count, one condition each, and one it must
def not_rangeable_reads(n : int; var ptr : int?) : int {
    var s = 0
    var p = 0
    while (p < n - p) {
        p++
    }
    var q = 0
    while (q <= n / (q + 1)) {
        q++
    }
    var r = 0
    while (r < n) {
        bump_ptr(unsafe(addr(r)))
        r++
    }
    var t = 0
    while (t < n) {
        bump_ref(t)
        t++
    }
    var u = 0
    while (u < n) {
        if (u == 3) {
            break
        }
        u++
    }
    s += u
    var a = 0
    while (a < n) {
        if (s > 100) {
            continue
        }
        a++
    }
    var b = 0
    while (b < n) {
        ++b
        b++
    }
    var w = 0 // nolint:LINT003 - the loop never steps it, which is the case under test
    while (w < n) {
        s += 2
    }
    var box = Box(n = n)
    var i = 0
    while (i < box.n) {
        box.n = 3
        i++
    }
    var arr = fixed_array(n, n)
    var j = 0
    while (j < arr[0]) {
        arr[0] = 2
        j++
    }
    var k = 0
    while (k < deref(ptr)) {
        deref(ptr) = 1
        k++
    }
    s += returns_early(n)
    var o = 0
    while (o < n) {
        if (o == 2) {
            break
        }
        o++
    }
    return s
}

def returns_early(n : int) : int {
    var v = 0
    while (v < n) {
        if (v == 5) {
            return 0
        }
        v++
    }
    return v
}

[export]
def main {
    print("{rangeable(outside)} {not_rangeable(outside)} {not_rangeable_steps(outside, false)} {jumps(outside)} {not_rangeable_reads(outside, unsafe(addr(outside)))}\n")
}
