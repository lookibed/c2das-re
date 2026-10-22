options gen2
require dastest/testing_boost public
require daslib/json_boost
require math

def cmp_desc(a, b : void?) : int {
    unsafe {
        return deref(reinterpret<int?>(b)) - deref(reinterpret<int?>(a))
    }
}

[test]
def test_stdlib(t : T?) {
    t |> run("malloc, free, memcpy and memset8 are builtins over raw memory") @(t : T?) {
        unsafe {
            var raw = reinterpret<uint8?>(malloc(64ul))
            t |> equal(raw != null, true)
            var src : uint8[4] = fixed_array(uint8(1), uint8(2), uint8(3), uint8(4))
            memcpy(raw, addr(src[0]), 4)
            t |> equal(int(deref(raw + 3)), 4)
            memset8(raw, uint8(9), 4)
            t |> equal(int(deref(raw + 3)), 9)
            free(raw)
        }
    }
    t |> run("json_boost's `?[]` of a missing key is a non-null sentinel, so `key_exists` tells a sidecar key's presence") @(t : T?) {
        var err : string
        var js = read_json("\{\"a\": \"x\"\}", err)
        let missing = js?["b"]
        t |> equal(missing != null, true)
        t |> equal(missing is _array, false)
        t |> equal(missing ?? "dflt", "dflt")
        t |> equal(key_exists(js, "a"), true)
        t |> equal(key_exists(js, "b"), false)
        delete_json(js)
    }
    t |> run("das sort takes a C comparator through a block adapter") @(t : T?) {
        var arr <- [5, 1, 4, 2, 3, 6]
        let cmp = @@cmp_desc
        arr |> sort() $(a, b : int) {
            var la = a
            var lb = b
            unsafe {
                return invoke(cmp, addr<void?>(la), addr<void?>(lb)) < 0
            }
        }
        t |> equal(arr[0], 6)
        t |> equal(arr[5], 1)
    }
    t |> run("raw C memory sorts as a fixed-array view") @(t : T?) {
        unsafe {
            var raw = reinterpret<int?>(malloc(24ul))
            for (i in range(6)) {
                deref(raw + i) = 6 - i
            }
            deref(reinterpret<int[6]?>(raw)) |> sort()
            t |> equal(deref(raw), 1)
            t |> equal(deref(raw + 5), 6)
            free(raw)
        }
    }
}

// <math.h>'s surface the converter spells as das math (converter/emit.das, C_RUNTIME_CALLS)
[test]
def test_math(t : T?) {
    t |> run("das math takes and gives double for each <math.h> function the emitter maps to it") @(t : T?) {
        t |> equal(typeinfo typename(math::floor(1.5lf)), "double const")
        t |> equal(typeinfo typename(math::pow(2.0lf, 3.0lf)), "double const")
        t |> equal(typeinfo typename(math::atan2(1.0lf, 1.0lf)), "double const")
        t |> equal(math::floor(-1.5lf), -2.0lf)
        t |> equal(math::ceil(-1.5lf), -1.0lf)
        t |> equal(math::abs(-2.5lf), 2.5lf)
        t |> equal(math::sqrt(2.25lf), 1.5lf)
        t |> equal(math::pow(2.0lf, 10.0lf), 1024.0lf)
        t |> equal(math::exp(0.0lf), 1.0lf)
        t |> equal(math::log(1.0lf), 0.0lf)
        t |> equal(math::log2(8.0lf), 3.0lf)
        t |> equal(math::log10(1000.0lf), 3.0lf)
        t |> equal(math::sin(0.0lf) + math::tan(0.0lf) + math::asin(0.0lf) + math::atan(0.0lf), 0.0lf)
        t |> equal(math::cos(0.0lf) + math::acos(1.0lf), 1.0lf)
        t |> equal(math::atan2(0.0lf, 1.0lf), 0.0lf)
    }
}
