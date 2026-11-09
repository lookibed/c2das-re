options gen2

module c_bitfields public

require daslib/cmp
require strings
require daslib/ast
require daslib/ast_boost
require daslib/templates_boost
require daslib/macro_boost
require c_runtime/c_storage

//! C bitfields over das storage. `[c_bitfields(a = 3, b = 5)] struct BF { a : uint; b : int; e : int16 }`
//! is written C-shaped; the annotation replaces each allocation unit's fields with one unsigned
//! storage field `_bits<N>` at the unit's place and generates, per bitfield, the property pair
//! `operator . a` / `operator . a :=` doing the mask and shift. The argument list is read in order:
//! `_bits<N> = "uint8"` (or `"uint16"`, `"uint"`, `"uint64"`, or `"uint8[k]"`, `k` bytes at
//! alignment 1) opens a unit, `_<K> = n` skips `n` bits of padding, any other `name = width`
//! places the field `name` at the unit's bit cursor. A bitfield with no unit open opens `_bits<K>`
//! sized by the field's own type. The property pairs are `c_storage`'s arithmetic, in `uint` or
//! `uint64`, since das defines no shift on the 8- and 16-bit storage types.

// a bitfield of a unit: its field's index in the struct and its place in the unit
struct private BitMember {
    fidx : int
    access : BitAccess
}

// a unit: its storage type, and for a byte unit (`"uint8[k]"`) its `count` of bytes, else 0
struct private BitUnit {
    name : string
    storage : string
    bits : int
    count : int
    cursor : int
    members : array<BitMember>
}

// the storage a bitfield of type `t` opens by default: the unsigned type of its width; an empty
// name for a type that cannot hold a bitfield
def private default_storage(t : TypeDeclPtr) : CStorage => t.isInteger || t.isBool ? storage_of("", t.sizeOf * 8) : CStorage()

def private all_digits(s : string; from : int) : bool {
    var digits = length(s) > from
    peek_data(s) $(bytes) {
        for (idx in range(from, length(bytes))) {
            digits = digits && is_number(int(bytes[idx]))
        }
    }
    return digits
}

// the `k` of a byte unit's storage `"uint8[k]"`, 1 to 8; 0 for any other spelling
def private byte_unit_count(spelled : string) : int {
    if (!(spelled |> starts_with("uint8[")) || !(spelled |> ends_with("]"))) {
        return 0
    }
    let digits = slice(spelled, 6, length(spelled) - 1)
    if (!all_digits(digits, 0)) {
        return 0
    }
    let count = to_int(digits)
    return count <= 8 ? count : 0
}

def private is_opener(name : string) : bool => name |> starts_with("_bits") && all_digits(name, 5)

def private is_padding(name : string) : bool => name |> starts_with("_") && all_digits(name, 1)

// opens unit `name` of `storage`, which must not be a field of the struct or another unit
def private open_unit(st : StructurePtr; var units : array<BitUnit>; name : string; storage : CStorage; count : int; var errors : das_string) : bool {
    if (field_index(st, name) >= 0) {
        errors := "c_bitfields: unit `{name}` collides with a field of {st.name}"
        return false
    }
    for (u in units) {
        if (u.name == name) {
            errors := "c_bitfields: unit `{name}` is opened twice"
            return false
        }
    }
    units |> emplace(BitUnit(name = name, storage = storage.name, bits = count == 0 ? storage.bits : 8 * count, count = count))
    return true
}

// advances the open unit's cursor past `bits` bits of padding
def private skip_padding(var units : array<BitUnit>; name : string; bits : int; var errors : das_string) : bool {
    if (empty(units)) {
        errors := "c_bitfields: padding `{name}` before any unit"
        return false
    }
    if (bits < 0) {
        errors := "c_bitfields: padding `{name}` of {bits} bits is negative"
        return false
    }
    assume pad_unit = units[length(units) - 1]
    pad_unit.cursor += bits
    if (pad_unit.cursor > pad_unit.bits) {
        errors := "c_bitfields: padding `{name}` runs past unit `{pad_unit.name}`"
        return false
    }
    return true
}

// the units the argument list describes, in order; false with `errors` set on any argument the
// grammar or the struct refuses
def private read_units(st : StructurePtr; args : AnnotationArgumentList; var units : array<BitUnit>; var errors : das_string) : bool {
    var named : table<string>
    for (a in args) {
        let name = string(a.name)
        if (is_opener(name)) {
            let spelled = a.basicType == Type.tString ? string(a.sValue) : "?"
            let count = byte_unit_count(spelled)
            let storage = count > 0 ? storage_of("uint8", 0) : storage_of(spelled, 0)
            if (empty(storage.name)) {
                errors := "c_bitfields: unit `{name}` names storage `{a.sValue}`; expecting \"uint8\", \"uint16\", \"uint\", \"uint64\" or \"uint8[k]\", k from 1 to 8"
                return false
            }
            if (!open_unit(st, units, name, storage, count, errors)) {
                return false
            }
            continue
        }
        if (a.basicType != Type.tInt) {
            errors := "c_bitfields: argument `{name}` is not a width"
            return false
        }
        if (is_padding(name)) {
            if (!skip_padding(units, name, a.iValue, errors)) {
                return false
            }
            continue
        }
        let fidx = field_index(st, name)
        if (fidx < 0) {
            errors := "c_bitfields: {st.name} has no field `{name}`"
            return false
        }
        if (key_exists(named, name)) {
            errors := "c_bitfields: field `{name}` is named twice"
            return false
        }
        named |> insert(name)
        let ftype = st.fields[fidx]._type
        let default_unit = default_storage(ftype)
        if (empty(default_unit.name)) {
            errors := "c_bitfields: field `{name}` of type {describe(ftype)} is not a bitfield type"
            return false
        }
        if (st.fields[fidx].init != null) {
            errors := "c_bitfields: field `{name}` has an initializer; a bitfield starts at zero"
            return false
        }
        if (empty(units) && !open_unit(st, units, "_bits0", default_unit, 0, errors)) {
            return false
        }
        assume unit = units[length(units) - 1]
        let width = a.iValue
        if (ftype.isBool && width != 1) {
            errors := "c_bitfields: bool field `{name}` is 1 bit wide, not {width}"
            return false
        }
        if (width < 1 || unit.cursor + width > unit.bits) {
            errors := "c_bitfields: field `{name}` of {width} bits does not fit unit `{unit.name}` of {unit.bits} bits at bit {unit.cursor}"
            return false
        }
        if (!empty(unit.members) && unit.members[length(unit.members) - 1].fidx + 1 != fidx) {
            errors := "c_bitfields: field `{name}` does not follow `{unit.members[length(unit.members) - 1].access.name}` in {st.name}; a unit's fields are adjacent"
            return false
        }
        unit.members |> push(BitMember(fidx = fidx, access = BitAccess(name = name, ftype = clone_type(ftype), off = unit.cursor, width = width)))
        unit.cursor += width
    }
    for (u in units) {
        if (empty(u.members)) {
            errors := "c_bitfields: unit `{u.name}` holds no field"
            return false
        }
    }
    return true
}

[structure_macro(name = "c_bitfields")]
class CBitfieldsAnnotation : AstStructureAnnotation {
    def override apply(var st : StructurePtr; var group : ModuleGroup; var args : AnnotationArgumentList; var errors : das_string) : bool {
        if (st.flags.isClass) {
            errors := "c_bitfields: {st.name} is a class; bitfields live in a struct"
            return false
        }
        var units : array<BitUnit>
        if (!read_units(st, args, units, errors)) {
            return false
        }
        if (empty(units)) {
            errors := "c_bitfields: {st.name} names no bitfield"
            return false
        }
        for (u in units) {
            let store = BitStore(field = u.name, storage = storage_of(u.storage, 0), count = u.count)
            for (m in u.members) {
                if (!add_bit_pair(st, store, m.access, st.fields[m.fidx].at, "c_bitfields", errors)) {
                    return false
                }
            }
        }
        // each unit's first field becomes its storage and the rest go, the unit furthest down
        // the struct first, so the indices of the units above it hold
        var order <- [for (ui in range(length(units))); ui]
        sort(order) <| cmp_by(-units[_].members[0].fidx)
        for (u in order) {
            let first = units[u].members[0].fidx
            for (mi in range(length(units[u].members) - 1)) {
                st.fields |> erase(units[u].members[length(units[u].members) - 1 - mi].fidx)
            }
            st.fields[first].name := units[u].name
            var unit_type = new TypeDecl(baseType = storage_of(units[u].storage, 0).base, at = st.fields[first].at)
            st.fields[first]._type = units[u].count == 0 ? unit_type : make_fixed_array_type(units[u].count, unit_type)
        }
        return true
    }
}

//! The bytes of a `uint8[k]` unit holding the word `w`, little-endian, `t` naming the unit's type
//! (`default<uint8[3]>`): the initializer of a byte unit. The type parameter is `UnitBytesT`, not
//! `T`: a generic's `auto(T)` binds a struct `T` visible where the generic is declared, its own
//! module or one it requires (`probes/test_bitfields.das`, "a generic's auto(T) binds a struct T
//! visible where the generic is declared").
def c_unit_bytes(w : uint64; t : auto(UnitBytesT)) : UnitBytesT {
    var r : UnitBytesT
    for (i in range(length(r))) {
        r[i] = uint8(w >> uint64(8 * i))
    }
    return r
}

def c_unit_bytes(w : uint; t : auto(UnitBytesT)) : UnitBytesT => c_unit_bytes(uint64(w), t)
