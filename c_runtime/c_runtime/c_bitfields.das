options gen2

module c_bitfields public

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
//! `_bits<N> = "uint8"` (or `"uint16"`, `"uint"`, `"uint64"`) opens a unit, `_<K> = n` skips `n`
//! bits of padding, any other `name = width` places the field `name` at the unit's bit cursor.
//! A bitfield with no unit open opens `_bits<K>` sized by the field's own type. The bit math runs
//! in `uint` or `uint64`, since das defines no shift on the 8- and 16-bit storage types.

struct private BitMember {
    name : string
    fidx : int
    ftype : TypeDeclPtr
    off : int
    width : int
}

struct private BitUnit {
    name : string
    storage : string
    bits : int
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

def private is_opener(name : string) : bool => name |> starts_with("_bits") && all_digits(name, 5)

def private is_padding(name : string) : bool => name |> starts_with("_") && all_digits(name, 1)

def private field_index(st : StructurePtr; name : string) : int {
    for (idx in range(length(st.fields))) {
        if (st.fields[idx].name == name) {
            return idx
        }
    }
    return -1
}

// a constant of the arithmetic type: `uint` for a unit of up to 32 bits, `uint64` past it
def private arith_const(wide : bool; v : uint64) : ExpressionPtr => wide ? qmacro($v(v)) : qmacro($v(uint(v)))

def private low_mask(width : int) : uint64 => width >= 64 ? ~0ul : (1ul << uint64(width)) - 1ul

// the storage read in the arithmetic type: `s._bitsN`, through `uint(...)` for a narrow unit
def private storage_read(u : BitUnit; arith_type : string) : ExpressionPtr {
    var read = qmacro(s.$f(u.name))
    return u.storage == arith_type ? read : qmacro($c(arith_type)($e(read)))
}

def private make_getter(var st : StructurePtr; u : BitUnit; m : BitMember) : FunctionPtr {
    let wide = u.bits == 64
    let bits = wide ? 64 : 32
    let arith_type = wide ? "uint64" : "uint"
    let t_name = describe(m.ftype)
    var e = storage_read(u, arith_type)
    if (m.ftype.isSignedInteger) {
        // shift the field's top bit to the word's top, then an arithmetic shift back down
        let up = bits - m.off - m.width
        if (up > 0) {
            e = qmacro($e(e) << $e(arith_const(wide, uint64(up))))
        }
        let signed_name = wide ? "int64" : "int"
        e = qmacro($c(signed_name)($e(e)))
        if (bits - m.width > 0) {
            e = wide ? qmacro($e(e) >> $v(int64(bits - m.width))) : qmacro($e(e) >> $v(bits - m.width))
        }
        if (t_name != signed_name) {
            e = qmacro($c(t_name)($e(e)))
        }
    } else {
        if (m.off > 0) {
            e = qmacro($e(e) >> $e(arith_const(wide, uint64(m.off))))
        }
        if (m.width < bits) {
            e = qmacro($e(e) & $e(arith_const(wide, low_mask(m.width))))
        }
        if (m.ftype.isBool) {
            e = qmacro($e(e) != $e(arith_const(wide, 0ul)))
        } elif (t_name != arith_type) {
            e = qmacro($c(t_name)($e(e)))
        }
    }
    var fn <- qmacro_function(".`{m.name}") $(s : $t(st)) : $t(m.ftype) {
        return $e(e)
    }
    fn.flags.generated = true
    fn.at = st.at
    return <- fn
}

def private make_setter(var st : StructurePtr; u : BitUnit; m : BitMember) : FunctionPtr {
    let wide = u.bits == 64
    let bits = wide ? 64 : 32
    let arith_type = wide ? "uint64" : "uint"
    let mask = low_mask(m.width)
    var v = qmacro(v)
    if (m.ftype.isBool) {
        v = qmacro($e(v) ? $e(arith_const(wide, 1ul)) : $e(arith_const(wide, 0ul)))
    } elif (describe(m.ftype) != arith_type) {
        v = qmacro($c(arith_type)($e(v)))
    }
    if (m.width < bits) {
        v = qmacro($e(v) & $e(arith_const(wide, mask)))
    }
    if (m.off > 0) {
        v = qmacro($e(v) << $e(arith_const(wide, uint64(m.off))))
    }
    let keep_mask = ~(mask << uint64(m.off)) & low_mask(bits)
    var e = qmacro(($e(storage_read(u, arith_type)) & $e(arith_const(wide, keep_mask))) | $e(v))
    if (u.storage != arith_type) {
        e = qmacro($c(u.storage)($e(e)))
    }
    var fn <- qmacro_function(".`{m.name}`clone") $(var s : $t(st); v : $t(m.ftype)) : void {
        s.$f(u.name) = $e(e)
    }
    // a `v : T` parameter is `T const`, as the parser makes it, so a hand-written twin collides
    fn.arguments[1]._type.flags.constant = true
    fn.flags.generated = true
    fn.at = st.at
    return <- fn
}

// opens unit `name` of `storage`, which must not be a field of the struct or another unit
def private open_unit(st : StructurePtr; var units : array<BitUnit>; name : string; storage : CStorage; var errors : das_string) : bool {
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
    units |> emplace(BitUnit(name = name, storage = storage.name, bits = storage.bits))
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
            let storage = storage_of(a.basicType == Type.tString ? string(a.sValue) : "?", 0)
            if (empty(storage.name)) {
                errors := "c_bitfields: unit `{name}` names storage `{a.sValue}`; expecting \"uint8\", \"uint16\", \"uint\" or \"uint64\""
                return false
            }
            if (!open_unit(st, units, name, storage, errors)) {
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
        if (empty(units) && !open_unit(st, units, "_bits0", default_unit, errors)) {
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
            errors := "c_bitfields: field `{name}` does not follow `{unit.members[length(unit.members) - 1].name}` in {st.name}; a unit's fields are adjacent"
            return false
        }
        unit.members |> push(BitMember(name = name, fidx = fidx, ftype = clone_type(ftype), off = unit.cursor, width = width))
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
            for (m in u.members) {
                var getter = make_getter(st, u, m)
                if (!(compiling_module() |> add_function(getter))) {
                    errors := "c_bitfields: {st.name} already has `operator . {m.name}`"
                    return false
                }
                var setter = make_setter(st, u, m)
                if (!(compiling_module() |> add_function(setter))) {
                    errors := "c_bitfields: {st.name} already has `operator . {m.name} :=`"
                    return false
                }
            }
        }
        // each unit's first field becomes its storage and the rest go, the unit furthest down
        // the struct first, so the indices of the units above it hold
        var order <- [for (ui in range(length(units))); ui]
        sort(order) $(lhs, rhs) => units[lhs].members[0].fidx > units[rhs].members[0].fidx
        for (u in order) {
            let first = units[u].members[0].fidx
            for (mi in range(length(units[u].members) - 1)) {
                st.fields |> erase(units[u].members[length(units[u].members) - 1 - mi].fidx)
            }
            st.fields[first].name := units[u].name
            st.fields[first]._type = new TypeDecl(baseType = storage_of(units[u].storage, 0).base, at = st.fields[first].at)
        }
        return true
    }
}
