options gen2
require dastest/testing_boost public
require daslib/ast
require c_runtime/c_storage

//! The storage table `[c_bitfields]` and `[c_union]` share: four unsigned types, each aligned to
//! its size, found by name, by width or by size.

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
}
