options gen2
options _nolint = "STYLE025"
require dastest/testing_boost public
require strings
require daslib/fio
require c_runtime/c_function

[c_function]
def blit(src_in : uint8 const?; var dst_in : uint8?; n_in : int) {
    var src = src_in
    var dst = dst_in
    var n = n_in
    while (n != 0) {
        n = n - 1
        deref(dst) = deref(src)
        dst = dst + 1
        src = src + 1
    }
}

[c_function]
def sum_bytes(p_in : uint8 const?; n : int) : int {
    var acc = 0
    var p = p_in
    for (_i in range(n)) {
        acc += int(deref(p))
        p = p + 1
    }
    return acc
}

[c_function]
def scratch_square(v : int) : int {
    var cell = reinterpret<int?>(malloc(uint64(typeinfo sizeof(type<int>))))
    deref(cell) = v * v
    let out = deref(cell)
    free(cell)
    return out
}

def blit_without_annotation_source : string =>
    "options gen2\ndef blit(src_in : uint8 const?; var dst_in : uint8?; n_in : int) \{\n    var src = src_in\n    var dst = dst_in\n    var n = n_in\n    while (n != 0) \{\n        n = n - 1\n        deref(dst) = deref(src)\n        dst = dst + 1\n        src = src + 1\n    \}\n\}\n[export]\ndef main \{\n\}\n"

[test]
def test_c_function(t : T?) {
    t |> run("a pointer-walking body runs with no unsafe wrap of its own") @(t : T?) {
        var a : uint8[4] = fixed_array(uint8(1), uint8(2), uint8(3), uint8(4))
        var b : uint8[4]
        unsafe {
            blit(addr(a[0]), addr(b[0]), 4)
            t |> equal(sum_bytes(addr(b[0]), 4), 10)
        }
        t |> equal(int(b[3]), 4)
    }
    t |> run("reinterpret, malloc and free are covered by the body-wide unsafe") @(t : T?) {
        t |> equal(scratch_square(7), 49)
    }
    t |> run("the same body without the annotation is rejected by the compiler") @(t : T?) {
        let path = "{temp_directory_result() as value}/c2das_c_function_control.das"
        fopen(path, "wb") $(f) {
            fwrite(f, blit_without_annotation_source())
        }
        var out : string
        let rc = run_and_capture([get_das_root() + "/bin/daslang", "-compile-only", path], out, 60.0)
        remove(path)
        t |> equal(rc != 0, true)
        t |> equal(out |> find("unsafe") >= 0, true, out)
    }
}
