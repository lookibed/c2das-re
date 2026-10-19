options gen2

module bit_units public

require math
require daslib/math_boost
require cir

//! The layout law over the C-IR: the natural layout das computes for a record's fields - each
//! at `(off + align - 1) & ~(align - 1)` in declaration order, the size tail-padded to the
//! largest alignment - and the allocation units that cover its bitfields, each an unsigned
//! storage field of 1, 2, 4 or 8 bytes placed naturally. Dialect-free: the facts come from
//! the record's clang offsets, sizes and bit positions. Every answer about a record is kept
//! in a `LayoutMemo` the caller owns, so a nest of records is measured once per record.

//! One bitfield allocation unit: its byte offset and size, and the record's fields it holds,
//! `first` to `last` inclusive (`first` is always a named bitfield; unnamed ones inside are
//! padding).
struct BitUnit {
    off : int
    size : int
    first : int
    last : int
}

//! What the layout law concluded about each record, by type index: whether das lays it out as
//! clang does, the alignment its das mirror has (clang's for a record it does not), whether that
//! alignment is below clang's, and its bitfield units.
struct LayoutMemo {
    known : array<bool>
    natural : array<bool>
    align : array<int>
    underaligned : array<bool>
    units : array<array<BitUnit>>
}

// the bytes of a scalar type, which are its alignment too; -1 for any other type
def private scalar_bytes(tu : CirTu; t : int) : int {
    let k = tu.types[t].k
    if (k == "int" || k == "float") {
        return tu.types[t].w / 8
    }
    if (k == "ptr" || k == "func") {
        return tu.target.ptr_w / 8
    }
    return k == "enum" ? 4 : -1
}

//! The C size of type `t` as clang lays it out; -1 for a type without one.
def type_size(tu : CirTu; t : int) : int64 {
    let scalar = scalar_bytes(tu, t)
    if (scalar >= 0) {
        return int64(scalar)
    }
    let k = tu.types[t].k
    if (k == "array") {
        let n = tu.types[t].count
        return n < 0 ? -1l : int64(n) * type_size(tu, tu.types[t].elem)
    }
    if (k == "struct" || k == "union") {
        return int64(tu.types[t].size)
    }
    return -1l
}

//! The alignment das gives a value of type `t`: a record's is its das mirror's, which for a
//! record holding bitfields can be below clang's (`docs/probe-findings.md` F5), so a record
//! nested in another is placed by the alignment its mirror has; a union's is clang's, which
//! `[c_union]` gives its storage.
def natural_align(tu : CirTu; var memo : LayoutMemo; t : int) : int {
    let scalar = scalar_bytes(tu, t)
    if (scalar >= 0) {
        return scalar
    }
    let k = tu.types[t].k
    if (k == "array") {
        return natural_align(tu, memo, tu.types[t].elem)
    }
    if (k == "struct") {
        measure(tu, memo, t)
        return memo.align[t]
    }
    return max(tu.types[t].align, 1)
}

//! The size and alignment union `t`'s members give under das's natural layout: the largest
//! member size rounded up to the largest member alignment, each member by the alignment its das
//! mirror has; what a bare `[c_union]` derives.
def union_member_layout(tu : CirTu; var memo : LayoutMemo; t : int) : tuple<size : int64; align : int> {
    var size = 0l
    var align = 1
    for (f in tu.types[t].fields) {
        size = max(size, type_size(tu, f.t))
        align = max(align, natural_align(tu, memo, f.t))
    }
    return (size = round_up(size, int64(align)), align = align)
}

//! The sizes an unsigned storage type has, which are its alignments too: a bitfield unit's and
//! `[c_union]`'s storage.
let STORAGE_SIZES = fixed_array(1, 2, 4, 8)

// whether an unsigned storage type has alignment `align`
def private storage_spells_align(align : int) : bool {
    for (size in STORAGE_SIZES) {
        if (size == align) {
            return true
        }
    }
    return false
}

//! Why union `t` is not natural, "" when it is: `[c_union]` gives its storage clang's size and
//! alignment, so every member must sit at 0 and fit them, measured by its das alignment, and a
//! member record must itself be natural.
def union_flaw(tu : CirTu; var memo : LayoutMemo; t : int) : string {
    let size = tu.types[t].size
    let align = max(tu.types[t].align, 1)
    if (empty(tu.types[t].fields)) {
        return "has no member"
    }
    if (!storage_spells_align(align) || size <= 0 || size % align != 0) {
        return "of size {size} and alignment {align} is not laid out naturally: das storage is a positive multiple of an alignment of 1, 2, 4 or 8"
    }
    for (f in tu.types[t].fields) {
        let name = empty(f.name) ? "an anonymous member" : "member `{f.name}`"
        if (f.off != 0) {
            return "puts {name} at {f.off}, not 0"
        }
        let rec = record_under(tu, f.t)
        if (rec >= 0 && !natural_layout(tu, memo, rec)) {
            return "holds {name}, a record das cannot lay out as clang does"
        }
        let member_align = natural_align(tu, memo, f.t)
        if (member_align > align) {
            return "aligns to {align}, below {name}'s alignment {member_align}"
        }
        if (type_size(tu, f.t) > int64(size) || type_size(tu, f.t) < 0l) {
            return "of size {size} does not fit {name}"
        }
    }
    return ""
}

//! Whether record `t` has a bitfield that needs storage: a named one of nonzero width.
def has_named_bitfield(tu : CirTu; t : int) : bool {
    for (f in tu.types[t].fields) {
        if (is_storage_bitfield(f)) {
            return true
        }
    }
    return false
}

//! The units that cover record `t`'s bitfields (into `out`); false for a record das cannot lay
//! out as clang does.
def bit_units(tu : CirTu; var memo : LayoutMemo; t : int; var out : array<BitUnit>) : bool {
    measure(tu, memo, t)
    out := memo.units[t]
    return memo.natural[t]
}

//! Whether das's natural layout of record `t` is clang's (`converter/ARCHITECTURE.md` section
//! 2, `packed`): every field at its offset and the same size, through bitfield units; the
//! alignment clang's, or below it where bitfield units make it so (F5).
def natural_layout(tu : CirTu; var memo : LayoutMemo; t : int) : bool {
    measure(tu, memo, t)
    return memo.natural[t]
}

//! Whether field `f` is a bitfield that needs storage: named, of nonzero width; unnamed and
//! zero-width ones are padding and never open a unit.
def is_storage_bitfield(f : CirField) : bool => f.is_bitfield && !empty(f.name) && f.bit_w > 0

// whether bitfield `f` lies inside the unit of `size` bytes at byte `unit_off`
def private inside(f : CirField; unit_off, size : int) : bool => f.bit_off >= unit_off * 8 && f.bit_off + f.bit_w <= (unit_off + size) * 8

// one search for a unit assignment whose record ends with alignment `target`: the units chosen
// so far, and the states known to fail (field, byte offset, alignment so far), which keeps the
// backtracking linear in the record's size
struct private Search {
    target : int
    chosen : array<BitUnit>
    failed_states : table<int64>
}

// the fields from `idx` on, placed from byte `off`: a non-bitfield where das puts it, which must
// be clang's offset; the first bitfield needing storage opens a unit (`sizes_from`) holding its
// bits and every bitfield after it whose bits also lie inside, a later failure retrying the next
// size; the end must give clang's size with the target alignment
def private place(tu : CirTu; var memo : LayoutMemo; t, idx, off, max_align : int; var search : Search) : bool {
    let n = length(tu.types[t].fields)
    if (idx == n) {
        return round_up(off, max_align) == tu.types[t].size && max_align == search.target
    }
    let state = (int64(idx) << 40l) | (int64(off) << 16l) | int64(max_align)
    if (key_exists(search.failed_states, state)) {
        return false
    }
    if (place_from(tu, memo, t, idx, off, max_align, search)) {
        return true
    }
    search.failed_states |> insert(state)
    return false
}

def private place_from(tu : CirTu; var memo : LayoutMemo; t, idx, off, max_align : int; var search : Search) : bool {
    let n = length(tu.types[t].fields)
    assume f = tu.types[t].fields[idx]
    if (!f.is_bitfield) {
        let a = natural_align(tu, memo, f.t)
        let at = round_up(off, a)
        var sz = type_size(tu, f.t)
        if (sz < 0l && idx == n - 1 && tu.types[f.t].k == "array") {
            // a flexible array member adds no bytes
            sz = 0l
        }
        return at == f.off && sz >= 0l && place(tu, memo, t, idx + 1, at + int(sz), max(max_align, a), search)
    }
    if (!is_storage_bitfield(f)) {
        return place(tu, memo, t, idx + 1, off, max_align, search)
    }
    for (size in sizes_from(int(type_size(tu, f.t)))) {
        let unit_off = round_up(off, size)
        if (inside(f, unit_off, size)) {
            var last = idx
            while (last + 1 < n && tu.types[t].fields[last + 1].is_bitfield && inside(tu.types[t].fields[last + 1], unit_off, size)) {
                last++
            }
            search.chosen |> push(BitUnit(off = unit_off, size = size, first = idx, last = last))
            if (place(tu, memo, t, last + 1, unit_off + size, max(max_align, size), search)) {
                return true
            }
            search.chosen |> pop()
        }
    }
    return false
}

// the unit sizes a bitfield of a `declared`-byte type tries: its own first (the unit MSVC
// allocates, and the storage `[c_bitfields]` opens by default), then the others ascending
def private sizes_from(declared : int) : array<int> {
    var sizes <- [declared]
    for (size in STORAGE_SIZES) {
        if (size != declared) {
            sizes |> push(size)
        }
    }
    return <- sizes
}

// one search of record `t` ending with alignment `target`, its units into the memo when it
// succeeds
def private assign(tu : CirTu; var memo : LayoutMemo; t, target : int) : bool {
    var inscope search <- Search(target = target)
    if (!place(tu, memo, t, 0, 0, 1, search)) {
        return false
    }
    delete memo.units[t]
    memo.units[t] <- search.chosen
    return true
}

// whether a field's record type (through arrays) won an alignment below clang's
def private has_underaligned_record_field(tu : CirTu; var memo : LayoutMemo; t : int) : bool {
    for (f in tu.types[t].fields) {
        let ft = record_under(tu, f.t)
        if (ft >= 0) {
            measure(tu, memo, ft)
            if (memo.underaligned[ft]) {
                return true
            }
        }
    }
    return false
}

//! The type an array type holds at its bottom, through every dimension; the type itself when it
//! is no array.
def element_under(tu : CirTu; t : int) : int {
    var ft = t
    while (tu.types[ft].k == "array") {
        ft = tu.types[ft].elem
    }
    return ft
}

//! The record (a struct or a union) an array type holds at its bottom, or the type itself when
//! it is a record; -1 else.
def record_under(tu : CirTu; t : int) : int {
    let ft = element_under(tu, t)
    return tu.types[ft].k == "struct" || tu.types[ft].k == "union" ? ft : -1
}

// the alignment clang would give record `t` with no alignment attribute: the largest of its
// named bitfields' declared types and its other fields, a nested record by clang's own
// alignment; a record whose clang alignment is larger carries an attribute das cannot spell
def private attribute_free_align(tu : CirTu; var memo : LayoutMemo; t : int) : int {
    var a = 1
    for (f in tu.types[t].fields) {
        if (f.is_bitfield && !is_storage_bitfield(f)) {
            continue
        }
        let rec = record_under(tu, f.t)
        a = max(a, rec >= 0 ? max(tu.types[rec].align, 1) : natural_align(tu, memo, f.t))
    }
    return a
}

// the layout law on record `t`, once: a union by its members at offset 0 and an alignment a
// storage type has; a struct by the alignment targets from clang's downward in powers of two,
// the first whose units reproduce clang's offsets and size winning; a target below clang's only
// for a record with bitfields (its own or a nested record's) whose clang alignment carries no
// attribute
def private measure(tu : CirTu; var memo : LayoutMemo; t : int) {
    if (t < length(memo.known) && memo.known[t]) {
        return
    }
    if (length(memo.known) < length(tu.types)) {
        let n = length(tu.types)
        memo.known |> resize(n)
        memo.natural |> resize(n)
        memo.align |> resize(n)
        memo.underaligned |> resize(n)
        memo.units |> resize(n)
    }
    let clang_align = max(tu.types[t].align, 1)
    memo.align[t] = clang_align
    if (tu.types[t].k == "union") {
        memo.natural[t] = empty(union_flaw(tu, memo, t))
        memo.known[t] = true
        return
    }
    if (assign(tu, memo, t, clang_align)) {
        memo.natural[t] = true
        memo.known[t] = true
        return
    }
    if ((has_named_bitfield(tu, t) || has_underaligned_record_field(tu, memo, t)) && attribute_free_align(tu, memo, t) == clang_align) {
        var target = clang_align / 2
        while (target >= 1) {
            if (assign(tu, memo, t, target)) {
                memo.natural[t] = true
                memo.align[t] = target
                memo.underaligned[t] = true
                memo.known[t] = true
                return
            }
            target /= 2
        }
    }
    memo.known[t] = true
}
