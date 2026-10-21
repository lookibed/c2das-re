options gen2
require dastest/testing_boost public
require daslib/ast
require daslib/fio
require strings
require ../../probes/_daslang_child.das
require c_runtime/c_storage

//! The storage table `[c_bitfields]` and `[c_union]` share: four unsigned types, each aligned to
//! its size, found by name, by width or by size; and the bit arithmetic, `bit_getter` and
//! `bit_setter` over each store shape, called directly from a structure annotation of the test's
//! own whose arguments name the store and the bitfield.

// `[bits_pair(field = "_bits0", storage = "uint16", count = 3, name = "f", off = 4, width = 40,
// signed = true)]`: the property pair `add_bit_pair` builds, a signed field typed `int64`, an
// unsigned one `uint64`
let BITS_MODULE = "options gen2
module bits_pair_mod public
require daslib/ast
require daslib/ast_boost
require c_runtime/c_storage
[structure_macro(name = \"bits_pair\")]
class BitsPair : AstStructureAnnotation \{
    def override apply(var st : StructurePtr; var group : ModuleGroup; var args : AnnotationArgumentList; var errors : das_string) : bool \{
        let signed = (find_arg(args, \"signed\") ?as tBool) ?? false
        let store = BitStore(field = (find_arg(args, \"field\") ?as tString) ?? \"\", storage = storage_of((find_arg(args, \"storage\") ?as tString) ?? \"\", 0), count = (find_arg(args, \"count\") ?as tInt) ?? 0)
        let access = BitAccess(name = (find_arg(args, \"name\") ?as tString) ?? \"\", ftype = new TypeDecl(baseType = signed ? Type.tInt64 : Type.tUInt64), off = (find_arg(args, \"off\") ?as tInt) ?? 0, width = (find_arg(args, \"width\") ?as tInt) ?? 0)
        return add_bit_pair(st, store, access, st.at, \"bits_pair\", errors)
    \}
\}
"

// a child program over one struct of `storage_field` under `annotation`, exiting 0 when `body`'s
// checks hold
def bits_source(annotation, storage_field, body : string) : string => "options gen2\nrequire bits_pair_mod\n{annotation}\nstruct S \{\n    {storage_field}\n\}\n[export]\ndef main : int \{\n    var s : S\n{body}    return 0\n\}\n"

def bits_run(t : T?; name, annotation, storage_field, body : string) {
    let dir = temp_directory_result() as value
    let module_path = "{dir}/bits_pair_mod.das"
    fopen(module_path, "wb") $(f) {
        fwrite(f, BITS_MODULE)
    }
    let r = runtime_child(name, bits_source(annotation, storage_field, body), false)
    t |> equal(r.rc, 0, r.out)
    remove(module_path)
}

[test]
def test_c_storage(t : T?) {
    t |> run("the four rows are the unsigned types of 1, 2, 4 and 8 bytes") @(t : T?) {
        t |> equal(length(C_STORAGES), 4)
        for (st, bytes, name in C_STORAGES, fixed_array(1, 2, 4, 8), fixed_array("uint8", "uint16", "uint", "uint64")) {
            t |> equal(st.bytes, bytes)
            t |> equal(st.bits, bytes * 8)
            t |> equal(st.name, name)
        }
        t |> equal(C_STORAGES[0].base == Type.tUInt8, true)
        t |> equal(C_STORAGES[3].base == Type.tUInt64, true)
    }
    t |> run("a row is found by name, by width and by size; a missing one has an empty name") @(t : T?) {
        t |> equal(storage_of("uint16", 0).bytes, 2)
        t |> equal(storage_of("", 32).name, "uint")
        t |> equal(storage_of_bytes(8).name, "uint64")
        t |> equal(storage_of("int", 0).name, "")
        t |> equal(storage_of_bytes(16).name, "")
    }
    t |> run("bit_getter and bit_setter over a scalar store shift, mask and keep the other bits") @(t : T?) {
        bits_run(t, "scalar", "[bits_pair(field = \"_bits0\", storage = \"uint\", count = 0, name = \"f\", off = 5, width = 9, signed = true)]", "_bits0 : uint", "    s._bits0 = 0xffffffffu\n    s.f = -256l\n    if (s.f != -256l || s._bits0 != 0xffffe01fu) \{\n        return 1\n    \}\n    s.f = s.f - 1l\n    if (s.f != 255l) \{\n        return 2\n    \}\n")
    }
    t |> run("bit_getter and bit_setter over a uint8 array assemble and store the bytes little-endian") @(t : T?) {
        bits_run(t, "bytes", "[bits_pair(field = \"_bits0\", storage = \"uint8\", count = 3, name = \"f\", off = 3, width = 17)]", "_bits0 : uint8[3]", "    s._bits0[0] = 0x07u8\n    s._bits0[2] = 0xf0u8\n    s.f = 0x1abcdul\n    if (s.f != 0x1abcdul || s._bits0[0] != 0x6fu8 || s._bits0[1] != 0x5eu8 || s._bits0[2] != 0xfdu8) \{\n        return 1\n    \}\n")
    }
    t |> run("bit_getter and bit_setter over a uint16 array sign-extend a field at a nonzero bit") @(t : T?) {
        bits_run(t, "halves", "[bits_pair(field = \"_bits0\", storage = \"uint16\", count = 2, name = \"f\", off = 4, width = 20, signed = true)]", "_bits0 : uint16[2]", "    s._bits0[0] = uint16(0x000f)\n    s.f = -524288l\n    if (s.f != -524288l || s._bits0[0] != uint16(0x000f) || s._bits0[1] != uint16(0x0080)) \{\n        return 1\n    \}\n    s.f = s.f - 1l\n    if (s.f != 524287l) \{\n        return 2\n    \}\n")
    }
    t |> run("a store past 32 bits runs the arithmetic in uint64") @(t : T?) {
        bits_run(t, "wide", "[bits_pair(field = \"_bits0\", storage = \"uint8\", count = 6, name = \"f\", off = 3, width = 44)]", "_bits0 : uint8[6]", "    s.f = 0xffffffffffful\n    if (s.f != 0xffffffffffful || s._bits0[0] != 0xf8u8 || s._bits0[5] != 0x7fu8) \{\n        return 1\n    \}\n    s.f = s.f + 1ul\n    if (s.f != 0ul) \{\n        return 2\n    \}\n")
    }
    t |> run("add_bit_pair reports an operator the struct already has") @(t : T?) {
        let dir = temp_directory_result() as value
        let module_path = "{dir}/bits_pair_mod.das"
        fopen(module_path, "wb") $(f) {
            fwrite(f, BITS_MODULE)
        }
        let r = runtime_child("twice", "options gen2\nrequire bits_pair_mod\n[bits_pair(field = \"a\", storage = \"uint\", name = \"f\", width = 3), bits_pair(field = \"a\", storage = \"uint\", name = \"f\", width = 3)]\nstruct S \{\n    a : uint\n\}\n[export]\ndef main \{\n\}\n", true)
        t |> equal(r.rc != 0, true, r.out)
        t |> equal(r.out |> find("bits_pair: S already has `operator . f`") >= 0, true, r.out)
        remove(module_path)
    }
}
