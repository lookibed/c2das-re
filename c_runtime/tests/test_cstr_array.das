options gen2
require dastest/testing_boost public
require strings
require daslib/strings_boost
require daslib/fio
require c_runtime/cstr_array

var name : uint8[8] = cstr_array("abc", 8)

def bytes_of(arr : uint8[8]) : string => join([for (b in arr); "{int(b)}"], " ")

[test]
def test_cstr_array(t : T?) {
    t |> run("the bytes, a NUL and zero padding fill the declared dimension") @(t : T?) {
        t |> equal(typeinfo dim(name), 8)
        t |> equal(bytes_of(name), "97 98 99 0 0 0 0 0")
        let local : uint8[8] = cstr_array("a\n\"", 8)
        t |> equal(bytes_of(local), "97 10 34 0 0 0 0 0")
    }
    t |> run("an exact fit carries no NUL, as in C") @(t : T?) {
        let tight : uint8[3] = cstr_array("abc", 3)
        t |> equal(int(tight[2]), 99)
        let empty_buf : uint8[4] = cstr_array("", 4)
        t |> equal(int(empty_buf[0]), 0)
    }
    t |> run("a string longer than the dimension is a compile error") @(t : T?) {
        let path = "{temp_directory_result() as value}/c2das_cstr_array_control.das"
        fopen(path, "wb") $(f) {
            fwrite(f, "options gen2\nrequire c_runtime/cstr_array\nvar buf : uint8[2] = cstr_array(\"abc\", 2)\n[export]\ndef main \{\n\}\n")
        }
        var out : string
        let rc = run_and_capture([get_das_root() + "/bin/daslang", "-load_module", "c_runtime", "-compile-only", path], out, 60.0)
        remove(path)
        t |> equal(rc != 0, true)
        t |> equal(out |> find("does not fit 2 bytes") >= 0, true, out)
    }
}
