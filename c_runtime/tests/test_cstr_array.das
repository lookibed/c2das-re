options gen2
require dastest/testing_boost public
require strings
require daslib/strings_boost
require ../../probes/_daslang_child.das
require c_runtime/cstr_array

var name : uint8[8] = cstr_array("abc", 8)

def bytes_of(arr : uint8[8]) : string => join([for (b in arr); "{int(b)}"], " ")

// the rows of a C `char s4_2[2][4] = {"1234", "5678"}` and a record's `char` field, as the
// converter spells them
var rows : uint8[2][4] = fixed_array(cstr_array("1234", 4), cstr_array("5678", 4))

struct named {
    name : uint8[6]
    id : int
}

var nm : named = named(name = cstr_array("abc", 6), id = 3)

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
    t |> run("a row of a char matrix and a record's char field take the literal as a one-dimensional array does") @(t : T?) {
        t |> equal(join([for (row in rows); join([for (b in row); "{int(b)}"], " ")], " | "), "49 50 51 52 | 53 54 55 56")
        let part : uint8[3][4] = fixed_array(cstr_array("ab", 4), fixed_array(uint8(0), uint8(0), uint8(0), uint8(0)), fixed_array(uint8(0), uint8(0), uint8(0), uint8(0)))
        t |> equal(int(part[0][1]) + int(part[0][2]) + int(part[2][3]), 98)
        t |> equal(int(nm.name[2]) + int(nm.name[3]) + nm.id, 102)
    }
    t |> run("a string longer than the dimension is a compile error") @(t : T?) {
        let r = runtime_child("cstr_array_control", "options gen2\nrequire c_runtime/cstr_array\nvar buf : uint8[2] = cstr_array(\"abc\", 2)\n[export]\ndef main \{\n\}\n", true)
        t |> equal(r.rc != 0, true)
        t |> equal(r.out |> find("does not fit 2 bytes") >= 0, true, r.out)
    }
}
