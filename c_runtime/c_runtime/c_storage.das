options gen2

module c_storage public

require daslib/ast

//! The unsigned storage types the C-layout annotations lay data out in: `[c_bitfields]` units and
//! `[c_union]` storage. Each is 1, 2, 4 or 8 bytes, aligned to its size.

//! One storage type: its das name, its size in bytes (its alignment too), its width in bits
//! and its das base type.
struct CStorage {
    name : string
    bytes : int
    bits : int
    base : Type
}

//! The four storage types, narrowest first.
let C_STORAGES = fixed_array(CStorage(name = "uint8", bytes = 1, bits = 8, base = Type.tUInt8), CStorage(name = "uint16", bytes = 2, bits = 16, base = Type.tUInt16), CStorage(name = "uint", bytes = 4, bits = 32, base = Type.tUInt), CStorage(name = "uint64", bytes = 8, bits = 64, base = Type.tUInt64))

//! The storage type named `name`, or the one `bits` wide when `name` is empty; an empty name
//! when there is none.
def storage_of(name : string; bits : int) : CStorage {
    for (st in C_STORAGES) {
        if (empty(name) ? st.bits == bits : st.name == name) {
            return st
        }
    }
    return CStorage()
}

//! The storage type `bytes` wide, which is its alignment too; an empty name when there is none.
def storage_of_bytes(bytes : int) : CStorage {
    for (st in C_STORAGES) {
        if (st.bytes == bytes) {
            return st
        }
    }
    return CStorage()
}
