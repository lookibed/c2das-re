options gen2

module c_layout public

require math
require ../converter/cir.das
require ../converter/bit_units.das

//! The record layout of a C dialect (`frontend/ARCHITECTURE_LAYOUT.md`): from a record described
//! by its kind, its attributes, the `#pragma pack` in force and its members' sizes and alignments,
//! the record's size and alignment and each member's bit offset, as clang lays the record out for
//! the dialect's triple; and the record written into a C-IR type with its `packed` verdict.

//! What a member's type is beyond its size and alignment: the layout takes a `plain` type and
//! refuses the classes the C-IR has no type for.
enum CLayoutClass {
    plain
    vector
    int128
}

//! One member of a record, in declaration order. A bitfield's `size` and `align` are its declared
//! type's; a flexible array member's `align` is its element's and its `size` is not read.
struct CLayoutMember {
    name : string           //!< "" for an unnamed bitfield and an anonymous member
    size : int64            //!< bytes of the member's type
    align : int             //!< bytes, the type's alignment, a typedef's `aligned` included
    is_bitfield : bool
    width : int             //!< a bitfield's width in bits
    is_flexible : bool      //!< an array of unknown size, the last member
    packed : bool           //!< `__attribute__((packed))` on the member
    aligned : int           //!< the largest `aligned(N)` or `_Alignas` on the member, 0 for none
    type_class : CLayoutClass
    at : string             //!< `file:line:col` of the member, for a refusal
}

//! A record to lay out: `dialect` is a predefined-macro table's name (`linux`, `msvc`).
struct CLayoutRecord {
    dialect : string
    is_union : bool
    packed : bool           //!< `__attribute__((packed))` on the record
    aligned : int           //!< the largest `aligned(N)` on the record, 0 for none
    pack : int              //!< the `#pragma pack` value in force at the definition, 0 for none
    ms_struct : bool        //!< `__attribute__((ms_struct))` on the record
    members : array<CLayoutMember>
    at : string             //!< `file:line:col` of the record, for a refusal
}

//! A record's layout: its size and alignment in bytes and each member's offset in bits from the
//! record's first byte. A refusal sets `failed` and `err` (`file:line:col: what`) and nothing else.
struct CRecordLayout {
    size : int64
    align : int
    offsets : array<int64>
    failed : bool
    err : string
}

// the bookkeeping of one record's layout as clang's record layout builder keeps it, in bits
struct private Builder {
    data_bits : int64       // the end of the last member, rounded to a byte
    size_bits : int64
    unfilled_bits : int64   // the bits a bitfield left unused in its last byte
    align : int             // bytes
}

def private is_power_of_two(n : int) : bool => n > 0 && (n & (n - 1)) == 0

def private round_up_bits(n, to : int64) : int64 => (n + to - 1l) / to * to

def private refuse(var layout : CRecordLayout; at, what : string) {
    layout.failed = true
    layout.err = empty(at) ? what : "{at}: {what}"
}

// why member `m`, the `idx`th of `rec`, is not laid out; "" when it is
def private member_refusal(rec : CLayoutRecord; m : CLayoutMember; idx : int) : string {
    let name = empty(m.name) ? "an unnamed member" : "member `{m.name}`"
    if (m.type_class == CLayoutClass.vector) {
        return "{name} has a vector type, which the C-IR has no type for"
    }
    if (m.type_class == CLayoutClass.int128) {
        return "{name} has a 128-bit integer type, which the C-IR has no type for"
    }
    if (!is_power_of_two(m.align)) {
        return "{name} has an alignment of {m.align}, not a power of two"
    }
    if (m.aligned != 0 && !is_power_of_two(m.aligned)) {
        return "{name} is `aligned({m.aligned})`, not a power of two"
    }
    if (m.is_flexible) {
        if (m.is_bitfield || idx != length(rec.members) - 1) {
            return "{name}, an array of unknown size, is not the last member"
        }
        return ""
    }
    if (m.size < 0l) {
        return "{name} has an incomplete type"
    }
    if (m.is_bitfield && (m.width < 0 || int64(m.width) > m.size * 8l)) {
        return "{name} is {m.width} bits wide, outside its type of {m.size * 8l} bits"
    }
    if (m.is_bitfield && m.width == 0 && !empty(m.name)) {
        return "{name} is a named bitfield of width 0"
    }
    return ""
}

// a member that is no bitfield: at its alignment, the type's unless `packed`, raised by its own
// `aligned`, capped by `#pragma pack`; a union's at 0
[arch(at="ARCHITECTURE_LAYOUT.md#c-layout-members")]
def private place_member(rec : CLayoutRecord; m : CLayoutMember; var b : Builder) : int64 {
    b.unfilled_bits = 0l
    var field_align = rec.packed || m.packed ? 1 : m.align
    field_align = max(field_align, m.aligned)
    if (rec.pack > 0) {
        field_align = min(field_align, rec.pack)
    }
    let field_bits = m.is_flexible ? 0l : m.size * 8l
    var off = 0l
    if (rec.is_union) {
        b.data_bits = max(b.data_bits, field_bits)
    } else {
        off = round_up_bits(b.data_bits, int64(field_align) * 8l)
        b.data_bits = off + field_bits
    }
    b.size_bits = max(b.size_bits, b.data_bits)
    b.align = max(b.align, field_align)
    return off
}

// a bitfield: from the first unused bit, moved to its alignment when it is of width 0 or would
// cross a unit of its declared type (never under `#pragma pack`), or to its own `aligned`; an
// unnamed one leaves the record's alignment alone
[arch(at="ARCHITECTURE_LAYOUT.md#c-layout-bitfields")]
def private place_bitfield(rec : CLayoutRecord; m : CLayoutMember; var b : Builder) : int64 {
    let width = int64(m.width)
    let unit_bits = m.size * 8l
    let field_packed = rec.packed || m.packed
    let explicit_bits = int64(m.aligned) * 8l
    let pack_bits = int64(rec.pack) * 8l
    var unpacked_bits = int64(m.align) * 8l
    var align_bits = field_packed && width != 0l ? 1l : unpacked_bits
    if (explicit_bits > 0l) {
        align_bits = max(align_bits, explicit_bits)
        unpacked_bits = max(unpacked_bits, explicit_bits)
    }
    if (pack_bits > 0l && width != 0l) {
        unpacked_bits = min(unpacked_bits, pack_bits)
        align_bits = field_packed ? unpacked_bits : min(align_bits, pack_bits)
    }
    var off = rec.is_union ? 0l : b.data_bits - b.unfilled_bits
    if (width == 0l || (pack_bits == 0l && (off & (align_bits - 1l)) + width > unit_bits)) {
        off = round_up_bits(off, align_bits)
    } elif (explicit_bits > 0l && (pack_bits == 0l || explicit_bits <= pack_bits)) {
        off = round_up_bits(off, explicit_bits)
    }
    if (rec.is_union) {
        b.data_bits = max(b.data_bits, round_up_bits(width, 8l))
    } else {
        let end_bits = off + width
        b.data_bits = round_up_bits(end_bits, 8l)
        b.unfilled_bits = b.data_bits - end_bits
    }
    b.size_bits = max(b.size_bits, b.data_bits)
    if (!empty(m.name)) {
        b.align = max(b.align, int(align_bits / 8l))
    }
    return off
}

//! The layout of record `rec` under its dialect's rules; a refusal for the `msvc` dialect,
//! `ms_struct`, a member type the C-IR has no type for, and a malformed description.
[arch(at="ARCHITECTURE_LAYOUT.md#c-layout-record")]
def c_record_layout(rec : CLayoutRecord) : CRecordLayout {
    var layout : CRecordLayout
    if (rec.dialect == "msvc") {
        refuse(layout, rec.at, "the msvc record layout is not implemented")
        return <- layout
    }
    if (rec.dialect != "linux") {
        refuse(layout, rec.at, "unknown dialect '{rec.dialect}': linux or msvc")
        return <- layout
    }
    if (rec.ms_struct) {
        refuse(layout, rec.at, "an `ms_struct` record is not laid out")
        return <- layout
    }
    if (rec.pack != 0 && !is_power_of_two(rec.pack)) {
        refuse(layout, rec.at, "`#pragma pack({rec.pack})` is not a power of two")
        return <- layout
    }
    if (rec.aligned != 0 && !is_power_of_two(rec.aligned)) {
        refuse(layout, rec.at, "`aligned({rec.aligned})` is not a power of two")
        return <- layout
    }
    for (m, idx in rec.members, count()) {
        let why = member_refusal(rec, m, idx)
        if (!empty(why)) {
            refuse(layout, empty(m.at) ? rec.at : m.at, why)
            return <- layout
        }
    }
    var b = Builder(align = max(1, rec.aligned))
    layout.offsets |> reserve(length(rec.members))
    for (m in rec.members) {
        layout.offsets |> push(m.is_bitfield ? place_bitfield(rec, m, b) : place_member(rec, m, b))
    }
    layout.align = b.align
    layout.size = round_up_bits(b.size_bits, int64(b.align) * 8l) / 8l
    return <- layout
}

//! Layout `layout` written into record type `t` of `tu`, whose fields are `layout`'s members in
//! order: its size, alignment, each field's `off` and `bit_off`, and `packed` by the layout law of
//! `converter/bit_units.das`, which `memo` must not have measured `t` under. False, with `err`
//! set, for a refused layout, a field count other than the layout's, or a size past an `int`.
[arch(at="ARCHITECTURE_LAYOUT.md#c-layout-cir")]
def c_layout_into_cir(var tu : CirTu; var memo : LayoutMemo; t : int; layout : CRecordLayout; var err : string&) : bool {
    if (layout.failed) {
        err = layout.err
        return false
    }
    if (length(tu.types[t].fields) != length(layout.offsets)) {
        err = "record type {t} has {length(tu.types[t].fields)} fields, its layout {length(layout.offsets)}"
        return false
    }
    if (layout.size > int64(INT_MAX) / 8l) {
        err = "record type {t} is {layout.size} bytes, past the C-IR's bit offsets"
        return false
    }
    tu.types[t].size = int(layout.size)
    tu.types[t].align = layout.align
    for (f, bits in tu.types[t].fields, layout.offsets) {
        f.off = int(bits / 8l)
        f.bit_off = int(bits)
    }
    tu.types[t].packed = !natural_layout(tu, memo, t)
    return true
}
