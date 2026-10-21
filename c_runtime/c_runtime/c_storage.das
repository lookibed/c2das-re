options gen2

module c_storage public

require daslib/ast
require daslib/ast_boost
require daslib/templates_boost
require daslib/macro_boost

//! The unsigned storage types the C-layout annotations lay data out in: `[c_bitfields]` units and
//! `[c_union]` storage. Each is 1, 2, 4 or 8 bytes, aligned to its size. Also the bit arithmetic
//! both annotations generate: the property pair of one bitfield over the storage that holds it.

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

//! The index of field `name` in struct `st`, -1 when it has none.
def field_index(st : StructurePtr; name : string) : int {
    for (idx in range(length(st.fields))) {
        if (st.fields[idx].name == name) {
            return idx
        }
    }
    return -1
}

//! Where a bitfield's bits live: the struct field `field`, a scalar of `storage` when `count` is
//! 0, else an array of `storage` whose first `count` elements hold the bits, little-endian.
struct BitStore {
    field : string
    storage : CStorage
    count : int
}

//! One bitfield: its name, its declared das type, and its bit offset and width in the store.
struct BitAccess {
    name : string
    ftype : TypeDeclPtr
    off : int
    width : int
}

// the arithmetic a store's bits take: `uint` up to 32 of them, `uint64` past, since das defines
// no shift on the 8- and 16-bit storage types
struct private Arith {
    bits : int
    wide : bool
    name : string
}

def private arith_of(b : BitStore) : Arith {
    let wide = (b.count == 0 ? b.storage.bits : b.storage.bits * b.count) > 32
    return Arith(bits = wide ? 64 : 32, wide = wide, name = wide ? "uint64" : "uint")
}

// a constant of the arithmetic type
def private arith_const(a : Arith; v : uint64) : ExpressionPtr => a.wide ? qmacro($v(v)) : qmacro($v(uint(v)))

def private low_mask(width : int) : uint64 => width >= 64 ? ~0ul : (1ul << uint64(width)) - 1ul

// the store read in the arithmetic type: the field, or its elements assembled little-endian
def private store_read(b : BitStore; a : Arith) : ExpressionPtr {
    if (b.count == 0) {
        var read = qmacro(s.$f(b.field))
        return b.storage.name == a.name ? read : qmacro($c(a.name)($e(read)))
    }
    var e : ExpressionPtr
    for (i in range(b.count)) {
        var elem = qmacro(s.$f(b.field)[$v(i)])
        if (b.storage.name != a.name) {
            elem = qmacro($c(a.name)($e(elem)))
        }
        if (i > 0) {
            elem = qmacro($e(elem) << $e(arith_const(a, uint64(i * b.storage.bits))))
        }
        e = i == 0 ? elem : qmacro($e(e) | $e(elem))
    }
    return e
}

//! `operator . name` of bitfield `m` over store `b`, reported at `at` (the member's
//! declaration): shift and mask, a signed field shifting its top bit to the word's top and back,
//! which sign-extends.
def bit_getter(var st : StructurePtr; b : BitStore; m : BitAccess; at : LineInfo) : FunctionPtr {
    let a = arith_of(b)
    let t_name = describe(m.ftype)
    var e = store_read(b, a)
    if (m.ftype.isSignedInteger) {
        let up = a.bits - m.off - m.width
        if (up > 0) {
            e = qmacro($e(e) << $e(arith_const(a, uint64(up))))
        }
        let signed_name = a.wide ? "int64" : "int"
        e = qmacro($c(signed_name)($e(e)))
        if (a.bits - m.width > 0) {
            e = a.wide ? qmacro($e(e) >> $v(int64(a.bits - m.width))) : qmacro($e(e) >> $v(a.bits - m.width))
        }
        if (t_name != signed_name) {
            e = qmacro($c(t_name)($e(e)))
        }
    } else {
        if (m.off > 0) {
            e = qmacro($e(e) >> $e(arith_const(a, uint64(m.off))))
        }
        if (m.width < a.bits) {
            e = qmacro($e(e) & $e(arith_const(a, low_mask(m.width))))
        }
        if (m.ftype.isBool) {
            e = qmacro($e(e) != $e(arith_const(a, 0ul)))
        } elif (t_name != a.name) {
            e = qmacro($c(t_name)($e(e)))
        }
    }
    var fn <- qmacro_function(".`{m.name}") $(s : $t(st)) : $t(m.ftype) {
        return $e(e)
    }
    fn.flags.generated = true
    fn.at = at
    return <- fn
}

//! `operator . name :=` of bitfield `m` over store `b`, reported at `at`: clears the field's bits
//! and ors the masked value in, the word narrowing back into the store, one element at a time
//! for an array.
def bit_setter(var st : StructurePtr; b : BitStore; m : BitAccess; at : LineInfo) : FunctionPtr {
    let a = arith_of(b)
    let mask = low_mask(m.width)
    var v = qmacro(v)
    if (m.ftype.isBool) {
        v = qmacro($e(v) ? $e(arith_const(a, 1ul)) : $e(arith_const(a, 0ul)))
    } elif (describe(m.ftype) != a.name) {
        v = qmacro($c(a.name)($e(v)))
    }
    if (m.width < a.bits) {
        v = qmacro($e(v) & $e(arith_const(a, mask)))
    }
    if (m.off > 0) {
        v = qmacro($e(v) << $e(arith_const(a, uint64(m.off))))
    }
    let keep_mask = ~(mask << uint64(m.off)) & low_mask(a.bits)
    var e = qmacro(($e(store_read(b, a)) & $e(arith_const(a, keep_mask))) | $e(v))
    var body : array<ExpressionPtr>
    body |> reserve(b.count + 1)
    if (b.count == 0) {
        if (b.storage.name != a.name) {
            e = qmacro($c(b.storage.name)($e(e)))
        }
        body |> push <| qmacro_expr() {
            s.$f(b.field) = $e(e)
        }
    } else {
        body |> push <| qmacro_expr() {
            let w = $e(e)
        }
        for (i in range(b.count)) {
            var part = i == 0 ? qmacro(w) : qmacro(w >> $e(arith_const(a, uint64(i * b.storage.bits))))
            if (b.storage.name != a.name) {
                part = qmacro($c(b.storage.name)($e(part)))
            }
            body |> push <| qmacro_expr() {
                s.$f(b.field)[$v(i)] = $e(part)
            }
        }
    }
    var fn <- qmacro_function(".`{m.name}`clone") $(var s : $t(st); v : $t(m.ftype)) : void {
        $b(body)
    }
    // a `v : T` parameter is `T const`, as the parser makes it, so a hand-written twin collides
    fn.arguments[1]._type.flags.constant = true
    fn.flags.generated = true
    fn.at = at
    return <- fn
}

//! Adds the property pair of bitfield `m` over store `b`, declared at `at`, to the module being
//! compiled; false with `errors` set, prefixed by `annotation`, when the module already has
//! either operator.
def add_bit_pair(var st : StructurePtr; b : BitStore; m : BitAccess; at : LineInfo; annotation : string; var errors : das_string) : bool {
    var getter <- bit_getter(st, b, m, at)
    if (!(compiling_module() |> add_function(getter))) {
        errors := "{annotation}: {st.name} already has `operator . {m.name}`"
        return false
    }
    var setter <- bit_setter(st, b, m, at)
    if (!(compiling_module() |> add_function(setter))) {
        errors := "{annotation}: {st.name} already has `operator . {m.name} :=`"
        return false
    }
    return true
}
