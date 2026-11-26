options gen2
require dastest/testing_boost public
require daslib/json_boost
require math
require _daslang_child
require strings
require daslib/fio
require daslib/strings_boost

def cmp_desc(a, b : void?) : int {
    unsafe {
        return deref(reinterpret<int?>(b)) - deref(reinterpret<int?>(a))
    }
}

// a marshal accessor's reads and write as the builtin `memcpy` with an `int` size, `crt` in scope
// (bytes 1..16: the byte at 3 is 4, the int at 1 is 0x05040302 = 84148994, 1.5 back, and the int16 at
// 0 read through crt::memcpy's uint64 size beside them, 0x0201 = 513)
let private BUILTIN_MEMCPY = "options gen2\nrequire crt\nrequire c_runtime/c_function\n\n[c_function]\ndef read_one(bytes : uint8?; ofs : int) : uint8 \{\n    var r : uint8\n    memcpy(reinterpret<void?>(addr(r)), reinterpret<void?>(bytes + ofs), 1)\n    return r\n\}\n\n[c_function]\ndef read_four(bytes : uint8?; ofs : int) : int \{\n    var r : int\n    memcpy(reinterpret<void?>(addr(r)), reinterpret<void?>(bytes + ofs), 4)\n    return r\n\}\n\n[c_function]\ndef write_eight(bytes : uint8?; ofs : int; v : double) \{\n    var copy = v\n    memcpy(reinterpret<void?>(bytes + ofs), reinterpret<void?>(addr(copy)), 8)\n\}\n\n[c_function]\ndef read_crt(bytes : uint8?; ofs : int) : int16 \{\n    var r : int16\n    crt::memcpy(reinterpret<void?>(addr(r)), reinterpret<void?>(bytes + ofs), uint64(2))\n    return r\n\}\n\n[export]\ndef main \{\n    var buf : uint8[16]\n    for (i in range(16)) \{\n        buf[i] = uint8(i + 1)\n    \}\n    let p = unsafe(addr(buf[0]))\n    write_eight(p, 5, 1.5lf)\n    var d : double\n    unsafe \{\n        memcpy(addr(d), p + 5, 8)\n    \}\n    print(\"\{read_one(p, 3)\} \{read_four(p, 1)\} \{d\} \{read_crt(p, 0)\}\\n\")\n\}\n"

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
    t |> run("memcpy with an `int` size is daslang's builtin beside crt's `uint64` one, right under the interpreter and the JIT, which folds a one-byte copy to one unaligned load (docs/probe-findings.md F81, F82)") @(t : T?) {
        let ir = "{test_temp_dir()}/c2das_probe_builtin_memcpy.ll"
        let interp = runtime_child("builtin_memcpy", BUILTIN_MEMCPY, false)
        t |> equal(interp.out, "0x4 84148994 1.5 513\n")
        let jit = daslang_run("builtin_memcpy_jit", BUILTIN_MEMCPY, jit_flags(), [for (m in RUNTIME_MODULES); m], "c2das_probe", ["--", "--jit-dump={ir}"])
        t |> equal(jit.out |> ends_with("0x4 84148994 1.5 513\n"), true, jit.out)
        let dump = fread(ir)
        let at = dump |> find("read_one")
        let body = at >= 0 ? slice(dump, at, dump |> find("\n\}\n", at)) : ""
        t |> success(body |> contains("load i8, ptr") && body |> contains("align 1") && !(body |> contains(" call ")), body)
        remove(ir)
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

[test]
def test_json_nesting(t : T?) {
    t |> run("json_boost's JV of a struct holding an array of structs that holds an array of structs converts (docs/probe-findings.md F64, fixed upstream), as one level less does") @(t : T?) {
        let cell = "struct Cell \{\n    time : double\n    samples : array<double>\n\}\n"
        let main = "[export]\ndef main \{\n    var c : Capture\n    print(\"\{write_json(JV(c))\}\\n\")\n\}\n"
        let nested = daslang_child("json_nested", "options gen2\nrequire daslib/json_boost\n{cell}struct Row \{\n    cells : array<Cell>\n\}\nstruct Capture \{\n    rows : array<Row>\n\}\n{main}", false)
        t |> equal(nested.rc, 0, nested.out)
        t |> success(nested.out |> find("\"rows\" : []") >= 0, nested.out)
        let flat = daslang_child("json_flat", "options gen2\nrequire daslib/json_boost\n{cell}struct Capture \{\n    cells : array<Cell>\n\}\n{main}", false)
        t |> equal(flat.rc, 0, flat.out)
        t |> success(flat.out |> find("\"cells\" : []") >= 0, flat.out)
    }
}
