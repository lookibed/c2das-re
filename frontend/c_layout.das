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
    required_align : int    //!< msvc: the alignment its type requires (a typedef's `aligned`, a record's `required_align`), 0 for none
    type_class : CLayoutClass
    at : string             //!< `file:line:col` of the member, for a refusal
}

//! A record to lay out: `dialect` is a predefined-macro table's name (`linux`, `msvc`).
struct CLayoutRecord {
    dialect : string
    is_union : bool
    packed : bool           //!< `__attribute__((packed))` on the record
    aligned : int           //!< the largest `aligned(N)` or `__declspec(align(N))` on the record, 0 for none
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
    required_align : int    //!< msvc: the alignment no `#pragma pack` lowers, for a member of this record's type
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

// clang's largest record, in bytes: a member or a record of this size or more is refused, so no
// count of bits passes 2^63
let private RECORD_LIMIT = 1l << 60l

// whether member `m`, placed past `end` bytes, could reach `RECORD_LIMIT`: its size and the most
// padding its largest alignment can add, past `end`, all below the limit, so no sum overflows
def private reaches_limit(end : int64; m : CLayoutMember; rec : CLayoutRecord) : bool {
    let pad = int64(max(max(m.align, m.aligned), max(rec.aligned, 1))) - 1l
    return end + (m.is_flexible ? 0l : m.size) + pad >= RECORD_LIMIT
}

def private round_up_bits(n, to : int64) : int64 => (n + to - 1l) / to * to

def private refuse(var layout : CRecordLayout; at, what : string) {
    layout.offsets |> clear()
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
    if (m.required_align != 0 && !is_power_of_two(m.required_align)) {
        return "{name} requires an alignment of {m.required_align}, not a power of two"
    }
    if (m.is_flexible) {
        if (m.is_bitfield || idx != length(rec.members) - 1) {
            return "{name}, an array of unknown size, is not the last member"
        }
        return ""
    }
    if (m.size < 0l) {
        return "{name} has an incomplete type"
    } elif (m.size >= RECORD_LIMIT) {
        return "{name} is 2^60 bytes or more, past clang's limit of a record"
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

// the bookkeeping of one record's msvc layout as clang's Microsoft record layout builder keeps it
struct private MsBuilder {
    size : int64            // bytes
    align : int
    required : int          // the alignment no pack lowers
    max_field : int         // the pack in force, 0 for none
    in_run : bool           // the last member is a bitfield of nonzero width
    unit_size : int64       // the bytes of that bitfield's unit
    remaining_bits : int64  // the bits its unit has left
}

// a member's alignment under msvc: its type's, at most the pack, 1 when `packed`, never below what it
// requires (its own `aligned`, its type's); a plain member's requirement is the record's too
[arch(at="ARCHITECTURE_LAYOUT_MSVC.md#c-layout-msvc-members")]
def private ms_member_align(m : CLayoutMember; var b : MsBuilder) : int {
    let field_required = max(m.aligned, m.required_align)
    if (!m.is_bitfield) {
        b.required = max(b.required, field_required)
    }
    var a = m.align
    if (b.max_field > 0) {
        a = min(a, b.max_field)
    }
    if (m.packed) {
        a = 1
    }
    return max(a, field_required)
}

// a member's bit offset under msvc: a plain member at its alignment past the end; a bitfield in the
// unit of the run before it when its type has that unit's size and its bits fit, else in a new unit
// of its type at its alignment; a zero-width bitfield aligns only right after a run
[arch(at="ARCHITECTURE_LAYOUT_MSVC.md#c-layout-msvc-bitfields")]
def private ms_place(rec : CLayoutRecord; m : CLayoutMember; var b : MsBuilder) : int64 {
    let a = ms_member_align(m, b)
    let unit = m.is_flexible ? 0l : m.size
    if (!m.is_bitfield) {
        b.in_run = false
        b.align = max(b.align, a)
        let off = rec.is_union ? 0l : round_up_bits(b.size, int64(a))
        b.size = max(b.size, off + unit)
        return off * 8l
    }
    let width = int64(m.width)
    if (width == 0l && !b.in_run) {
        return rec.is_union ? 0l : b.size * 8l
    }
    if (width != 0l && !rec.is_union && b.in_run && b.unit_size == unit && width <= b.remaining_bits) {
        let at = b.size * 8l - b.remaining_bits
        b.remaining_bits -= width
        return at
    }
    b.in_run = width != 0l
    b.unit_size = unit
    if (rec.is_union) {
        b.size = max(b.size, unit)
        return 0l
    }
    let off = round_up_bits(b.size, int64(a))
    b.size = width == 0l ? off : off + unit
    b.align = max(b.align, a)
    b.remaining_bits = unit * 8l - width
    return off * 8l
}

// the record's msvc layout: the size rounded to the members' alignment, then to the record's alignment
// (its requirement included) capped by the pack but never below the requirement; a record of no bytes
// is 4 bytes, or its alignment when it requires 4 or more
[arch(at="ARCHITECTURE_LAYOUT_MSVC.md#c-layout-msvc-record")]
def private ms_layout(rec : CLayoutRecord; var layout : CRecordLayout) {
    var b = MsBuilder(align = 1, required = max(1, rec.aligned), max_field = rec.packed ? 1 : rec.pack)
    layout.offsets |> reserve(length(rec.members))
    for (m in rec.members) {
        if (reaches_limit(b.size, m, rec)) {
            refuse(layout, rec.at, "the record reaches 2^60 bytes, past clang's limit")
            return
        }
        layout.offsets |> push(ms_place(rec, m, b))
    }
    var size = round_up_bits(b.size, int64(b.align))
    let align = max(b.align, b.required)
    let rounding = max(b.max_field > 0 ? min(align, b.max_field) : align, b.required)
    size = round_up_bits(size, int64(rounding))
    if (size == 0l) {
        size = b.required >= 4 ? int64(align) : 4l
    } elif (size >= RECORD_LIMIT) {
        refuse(layout, rec.at, "the record reaches 2^60 bytes, past clang's limit")
        return
    }
    layout.size = size
    layout.align = align
    layout.required_align = b.required
}

//! The layout of record `rec` under its dialect's rules; a refusal for `ms_struct`, a member type
//! the C-IR has no type for, a malformed description, and a member or record of 2^60 bytes or more.
[arch(at="ARCHITECTURE_LAYOUT.md#c-layout-record")]
def c_record_layout(rec : CLayoutRecord) : CRecordLayout {
    var layout : CRecordLayout
    if (rec.dialect != "linux" && rec.dialect != "msvc") {
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
    if (rec.dialect == "msvc") {
        ms_layout(rec, layout)
        return <- layout
    }
    var b = Builder(align = max(1, rec.aligned))
    layout.offsets |> reserve(length(rec.members))
    for (m in rec.members) {
        if (reaches_limit(b.data_bits / 8l, m, rec)) {
            refuse(layout, rec.at, "the record reaches 2^60 bytes, past clang's limit")
            return <- layout
        }
        layout.offsets |> push(m.is_bitfield ? place_bitfield(rec, m, b) : place_member(rec, m, b))
    }
    let size = round_up_bits((b.size_bits + 7l) / 8l, int64(b.align))
    if (size >= RECORD_LIMIT) {
        refuse(layout, rec.at, "the record reaches 2^60 bytes, past clang's limit")
        return <- layout
    }
    layout.align = b.align
    layout.size = size
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
