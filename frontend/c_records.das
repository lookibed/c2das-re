options gen2
options indenting = 4

module c_records public

require math
require strings
require daslib/strings_boost
require c_types public

//! The struct, union and enum types of a unit (`ARCHITECTURE_RECORDS.md`): a tag's definition built
//! into a pool type with its fields, layout and enumerators, a tag's use bound to its one
//! definition, the walk that interns a definition and writes its `record` or `enumdef` anchor in
//! Dumper A's order, and the `dims` of a declarator whose array sizes name enumerators.

// the kind of specifier node `n` with its article, as a message spells it
def private kind_name(p : CParser; n : int) : string {
    let node = p.ast.nodes[n]
    return node.kind == CNode.SPEC_ENUM ? "an enum" : "a {c_kind_name(node.op)}"
}

// the C-IR kind of specifier node `n`: `struct`, `union` or `enum`
def private tag_kind(p : CParser; n : int) : string {
    let node = p.ast.nodes[n]
    return node.kind == CNode.SPEC_ENUM ? "enum" : node.op == int(CTok.UNION) ? "union" : "struct"
}

// the token of specifier node `n`'s tag, its keyword's when it has none: its anchor's place
def private tag_tok(var p : CParser; n : int) : int {
    let node = p.ast.nodes[n]
    return node.tok if (node.a < 0)
    let tag = c_symbol_text(p.unit, node.a)
    // the tag follows its keyword, attributes perhaps between
    var t = node.tok + 1
    while (c_spelling(p.unit, t) != tag) {
        t++
    }
    return t
}

// a new pool record or enum of `kind` named `name`, of an identity of its own; a record with no
// layout yet
def private new_tag(var b : CTypes; kind, name : string) : int {
    var t = CirType(k = kind, name = name, count = b.next_tag, size = -1, align = -1, w = 32)
    b.next_tag++
    return c_pool_type(b, t)
}

// the value of integer literal spelling `s` (decimal, octal or hexadecimal, a suffix aside); -1 for
// any other spelling
def private literal_value(s : string) : int {
    let lower = to_lower(s)
    var end = length(lower)
    peek_data(lower) $(text) {
        while (end > 0 && (text[end - 1] == uint8('u') || text[end - 1] == uint8('l'))) {
            end--
        }
    }
    let digits = slice(lower, 0, end)
    let hex = starts_with(digits, "0x")
    let base = hex ? 16 : starts_with(digits, "0") && length(digits) > 1 ? 8 : 10
    var v = 0
    for (ch in hex ? slice(digits, 2) : digits) {
        let d = is_number(ch) ? ch - '0' : ch >= 'a' && ch <= 'f' ? ch - 'a' + 10 : 99
        return -1 if (d >= base || v > 0x7FFFFFF)
        v = v * base + d
    }
    return empty(digits) ? -1 : v
}

// whether an attribute of list `at` holds the word `word`
def private has_word(p : CParser; at : int; word : string) : bool {
    var n = at
    while (n >= 0) {
        let node = p.ast.nodes[n]
        if (node.kind == CNode.ATTRIBUTE) {
            for (t in range(node.a, node.b + 1)) {
                return true if (c_spelling(p.unit, t) == word)
            }
        }
        n = node.next
    }
    return false
}

//! What the attributes of list `at` say of a layout: `packed`, and the largest `aligned(N)`
//! (`aligned` alone is 16, x86-64's largest alignment). False with the error set for an `aligned`
//! of other than an integer literal and for an attribute that changes a type.
[arch(at="ARCHITECTURE_RECORDS.md#c-records-attributes")]
def c_layout_attributes(var b : CTypes; var p : CParser; at : int; var packed : bool&; var aligned : int&) : bool {
    return false if (!c_plain_attributes(b, p, at))
    var n = at
    while (n >= 0) {
        let node = p.ast.nodes[n]
        if (node.kind == CNode.ATTRIBUTE) {
            for (t in range(node.a, node.b + 1)) {
                let word = c_spelling(p.unit, t)
                if (word == "packed" || word == "__packed__") {
                    packed = true
                } elif (word == "aligned" || word == "__aligned__") {
                    var v = 16
                    if (t + 1 <= node.b && c_spelling(p.unit, t + 1) == "(") {
                        v = t + 3 <= node.b && c_spelling(p.unit, t + 3) == ")" ? literal_value(c_spelling(p.unit, t + 2)) : -1
                        if (v < 0) {
                            c_refuse(b, p, t, "an `aligned` attribute of other than an integer literal")
                            return false
                        }
                    }
                    aligned = max(aligned, v)
                }
            }
        }
        n = node.next
    }
    return true
}

//! The `dims` of a declarator `d` of pool type `t` (`docs/c-ir-spec.md` section 3): per array level
//! from the outermost, the sizes the source spells taken in order (a level with no size spells
//! none, so the sizes after it meet the levels before theirs, as Dumper A meets them), the
//! enumerator a size names alone when its value is that level's count (`enum_t` its pool enum),
//! else `enum_t` 0 and no item; none when no size names one so, as Dumper A records them.
[arch(at="ARCHITECTURE_RECORDS.md#c-records-dims")]
def c_dims(b : CTypes; var p : CParser; d, t : int) : array<CirDim> {
    var sizes : array<int>
    var at = d
    while (at >= 0) {
        let node = p.ast.nodes[at]
        if (node.kind == CNode.D_ARRAY && node.b >= 0) {
            sizes |> push(node.b)
        }
        at = node.kind == CNode.D_NAME ? -1 : node.a
    }
    var dims : array<CirDim>
    var named = false
    var level = b.unqualified[t]
    for (i in range(length(sizes))) {
        break if (level < 0 || b.pool[level].k != "array")
        let size = p.ast.nodes[sizes[length(sizes) - 1 - i]]
        var dim = CirDim()
        if (size.kind == CNode.IDENT) {
            let id = b.ids?[size.a] ?? CId()
            if (id.enum_t >= 0 && id.enum_v == int64(b.pool[level].count)) {
                dim = CirDim(enum_t = id.enum_t, item = c_symbol_text(p.unit, size.a))
                named = true
            }
        }
        dims |> push(dim)
        level = b.unqualified[b.pool[level].elem]
    }
    if (!named) {
        dims |> clear()
    }
    return <- dims
}

// whether token `tok` stands in a file under the own libc headers' folder
def private in_library_file(b : CTypes; p : CParser; tok : int) : bool => !empty(b.library_dir) && starts_with(c_file_name(p.unit, p.unit.toks[tok].file), b.library_dir)

// the layout requirement of pool type `t` under msvc: a record's, through arrays; 0 for any other
[arch(at="ARCHITECTURE_RECORDS.md#c-records-members")]
def private required_align(b : CTypes; t : int) : int {
    let u = b.unqualified[t]
    let k = b.pool[u].k
    if (k == "array") {
        return required_align(b, b.pool[u].elem)
    }
    var req = 0
    if (k == "struct" || k == "union") {
        get(b.layouts, u) $(l) {
            req = l.required_align
        }
    }
    return req
}

// whether pool type `t` is linux's x87 `long double` or an array of them, whose `long double` is
// 16 bytes aligned to 16 in a record, where the C-IR's type and `sizeof` have 8
def private is_x87(b : CTypes; t : int) : bool {
    var u = b.unqualified[t]
    while (b.pool[u].k == "array") {
        u = b.unqualified[b.pool[u].elem]
    }
    return !is_msvc(b.tu.target) && b.pool[u].k == "float" && b.pool[u].spell == "long double"
}

// the bytes clang lays a member of pool type `t` out in: an x87 `long double`'s 16
def private member_size(b : CTypes; t : int) : int64 {
    let size = c_type_size(b, t)
    return is_x87(b, t) && size > 0l ? size * 2l : size
}

// the alignment clang gives a member of pool type `t` below any `aligned` typedef: an x87 `long
// double`'s 16
def private member_align(b : CTypes; t : int) : int => is_x87(b, t) ? 16 : max(c_type_align(b, t), 1)

//! The `aligned` value a typedef declaration's specifier list `specs` and its init-declarator's
//! attribute list `attrs` give it, 0 for none; -1 with the error set for one the builder refuses.
[arch(at="ARCHITECTURE_RECORDS.md#c-records-members")]
def c_typedef_aligned(var b : CTypes; var p : CParser; specs, attrs : int) : int {
    var packed = false
    var aligned = 0
    return -1 if (!c_layout_attributes(b, p, specs, packed, aligned) || !c_layout_attributes(b, p, attrs, packed, aligned))
    return aligned
}

//! What an `aligned` typedef makes of pool type `t`, declared over specifier list `specs` of pool
//! type `base`, with the `aligned` value `own` of a typedef declaring it (0 for none): `x` the
//! alignment clang gives `t` (0 when no `aligned` typedef names it through arrays and typedefs:
//! the outermost one's value, which can lower the type's), `y` the alignment of `t` below its own
//! typedef names, by which msvc lays out a member of it.
[arch(at="ARCHITECTURE_RECORDS.md#c-records-members")]
def c_typedef_alignment(var b : CTypes; var p : CParser; specs, base, t, own : int) : int2 {
    var named = int2(0, 0)
    var at = specs
    while (at >= 0) {
        if (p.ast.nodes[at].kind == CNode.SPEC_TYPEDEF_NAME) {
            named = typedef_name_alignment(b, p, p.ast.nodes[at].a)
        }
        at = p.ast.nodes[at].next
    }
    let ub = b.unqualified[base]
    var elem = b.unqualified[t]
    while (elem != ub && b.pool[elem].k == "array") {
        elem = b.unqualified[b.pool[elem].elem]
    }
    // the base's `aligned` typedef reaches `t` when only arrays lie between them
    let reaches = elem == ub && named.x > 0
    let under = !reaches ? member_align(b, t) : b.unqualified[t] == ub ? named.y : named.x
    return int2(own > 0 ? own : reaches ? named.x : 0, under)
}

// `c_typedef_alignment`'s answer for typedef name `sym`: its binding's, or for one a use reaches
// before its declaration binds it, its declaration's
def private typedef_name_alignment(var b : CTypes; var p : CParser; sym : int) : int2 {
    return b.typedef_aligns?[sym] ?? int2(0, 0) if (key_exists(b.typedefs, sym))
    let ahead = b.typedef_defs?[sym] ?? int2(-1, -1)
    return int2(0, 0) if (ahead.x < 0)
    let specs = p.ast.nodes[ahead.x].a
    var id = p.ast.nodes[ahead.x].b
    while (id >= 0 && p.ast.nodes[id].a != ahead.y) {
        id = p.ast.nodes[id].next
    }
    let own = c_typedef_aligned(b, p, specs, id >= 0 ? p.ast.nodes[id].d : -1)
    let base = own >= 0 ? c_specifier_type(b, p, specs) : -1
    let t = base >= 0 ? c_declarator_type(b, p, base, ahead.y, false) : -1
    return t < 0 ? int2(0, 0) : c_typedef_alignment(b, p, specs, base, t, own)
}

// the field and the layout member of one member of type `t`, named `name` ("" for an unnamed
// bitfield and an anonymous member), of bit width `width` (-1 for no bitfield), declared at
// token `tok` with the attributes `packed` and `aligned`, what an `aligned` typedef makes of `t`
// `aligns` (`c_typedef_alignment`): linux lays the member out by its alignment, msvc by the type's
// below the typedefs and keeps it as a requirement
[arch(at="ARCHITECTURE_RECORDS.md#c-records-members")]
def private add_member(var b : CTypes; var p : CParser; t : int; name : string; width, tok : int; packed : bool; aligned : int; aligns : int2; var dims : array<CirDim>; var fields : array<CirField>; var rec : CLayoutRecord) {
    c_tag_complete(b, p)
    let u = b.unqualified[t]
    let flexible = width < 0 && b.pool[u].k == "array" && b.pool[u].count < 0
    let align = aligns.x <= 0 ? member_align(b, t) : is_msvc(b.tu.target) ? aligns.y : aligns.x
    var m = CLayoutMember(name = name, size = member_size(b, t), align = align, is_bitfield = width >= 0, width = max(width, 0), is_flexible = flexible, packed = packed, aligned = aligned, required_align = max(required_align(b, t), aligns.x), at = c_where(p.unit, tok))
    rec.members |> push(m)
    var f = CirField(name = name, t = t, is_bitfield = width >= 0, bit_w = max(width, 0))
    f.dims <- dims
    fields |> emplace(f)
}

// member declaration `m` of a record into `fields` and `rec`: its specifiers' type, then each
// member declarator's type, name and bit width; one with no declarator is an anonymous member,
// a record with no tag; false with the error set for any other member it does not type
[arch(at="ARCHITECTURE_RECORDS.md#c-records-members")]
def private member_declaration(var b : CTypes; var p : CParser; m : int; var fields : array<CirField>; var rec : CLayoutRecord) : bool {
    let md = p.ast.nodes[m]
    let base = c_specifier_type(b, p, md.a)
    return false if (base < 0)
    var packed = false
    var aligned = 0
    return false if (!c_layout_attributes(b, p, md.a, packed, aligned))
    if (md.b < 0) {
        let u = b.unqualified[base]
        var spec = md.a
        while (spec >= 0 && p.ast.nodes[spec].kind != CNode.SPEC_RECORD) {
            spec = p.ast.nodes[spec].next
        }
        if ((b.pool[u].k != "struct" && b.pool[u].k != "union") || spec < 0 || p.ast.nodes[spec].a >= 0) {
            c_refuse(b, p, md.tok, "a member declaration that declares no member")
            return false
        }
        var none : array<CirDim>
        add_member(b, p, base, "", -1, md.tok, packed, aligned, int2(0, 0), none, fields, rec)
        return true
    }
    var x = md.b
    while (x >= 0) {
        let node = p.ast.nodes[x]
        let t = node.a >= 0 ? c_declarator_type(b, p, base, node.a, false) : base
        return false if (t < 0)
        var own_packed = packed
        var own_aligned = aligned
        return false if (!c_layout_attributes(b, p, node.c, own_packed, own_aligned))
        var width = -1
        if (node.b >= 0) {
            let k = b.pool[b.unqualified[t]].k
            var v = 0l
            if (k != "int" && k != "enum") {
                c_refuse(b, p, node.tok, "a bit-field of other than an integer type")
                return false
            } elif (!invoke(b.fold, b, p, node.b, v) || v < 0l || v > 64l) {
                c_refuse(b, p, p.ast.nodes[node.b].tok, "a bit-field width other than an integer constant from 0 to 64")
                return false
            }
            width = int(v)
        }
        let sym = node.a >= 0 ? c_declarator_name(p.ast, node.a) : -1
        let name = sym >= 0 ? c_symbol_text(p.unit, sym) : ""
        var dims <- node.a >= 0 ? c_dims(b, p, node.a, t) : array<CirDim>()
        add_member(b, p, t, name, width, node.tok, own_packed, own_aligned, c_typedef_alignment(b, p, md.a, base, t, 0), dims, fields, rec)
        x = node.next
    }
    return true
}

// record specifier `n`'s body built into pool record `pt`: its fields in order, then its layout
// under the dialect; false with the error set for a member or a layout it refuses
[arch(at="ARCHITECTURE_RECORDS.md#c-records-definitions")]
def private build_record(var b : CTypes; var p : CParser; n, pt : int) : bool {
    b.tag_built[n] = pt
    let node = p.ast.nodes[n]
    if (node.a >= 0 && c_symbol_text(p.unit, node.a) == "__jmp_buf_tag") {
        c_refuse(b, p, node.tok, "glibc's `struct __jmp_buf_tag`, which the C-IR holds as the opaque `jmp_buf`,")
        return false
    }
    if (in_library_file(b, p, node.tok)) {
        b.library_tags[pt] = true
    }
    var rec = CLayoutRecord(dialect = is_msvc(b.tu.target) ? "msvc" : "linux", is_union = node.op == int(CTok.UNION), at = c_where(p.unit, node.tok))
    return false if (!c_layout_attributes(b, p, node.d, rec.packed, rec.aligned))
    rec.ms_struct = has_word(p, node.d, "ms_struct") || has_word(p, node.d, "__ms_struct__")
    var fields : array<CirField>
    // every caller has raised `defining`: a member's own definition is built where it stands
    var m = node.c
    var ok = true
    while (ok && m >= 0) {
        if (p.ast.nodes[m].kind == CNode.MEMBER_DECL) {
            ok = member_declaration(b, p, m, fields, rec)
        }
        m = p.ast.nodes[m].next
    }
    return false if (!ok || !empty(b.err))
    var layout = c_record_layout(rec)
    if (layout.failed) {
        b.err = layout.err
        return false
    }
    b.pool[pt].fields <- fields
    b.pool[pt].size = int(layout.size)
    b.pool[pt].align = layout.align
    b.layouts[pt] <- layout
    return true
}

// the value `v` held in a 32-bit `int`
def private as_int(v : int64) : int64 {
    let low = v & 4294967295l
    return low >= 2147483648l ? low - 4294967296l : low
}

// enum specifier `n`'s body built into pool enum `pt`: each enumerator's value, the one before plus
// one where none is written, bound as it is read; then the dialect's type: msvc's `int`, under
// linux `unsigned int` with no negative value, else `int`. An enumerator is an `int`, or under
// linux the enum's `unsigned int` when a value is past INT_MAX; false with the error set for a
// value that is no integer constant expression or no type of 32 bits holds
[arch(at="ARCHITECTURE_RECORDS.md#c-records-enums")]
def private build_enum(var b : CTypes; var p : CParser; n, pt : int) : bool {
    b.tag_built[n] = pt
    let node = p.ast.nodes[n]
    if (in_library_file(b, p, node.tok)) {
        b.library_tags[pt] = true
    }
    var packed = false
    var aligned = 0
    return false if (!c_layout_attributes(b, p, node.d, packed, aligned))
    if (packed || aligned != 0) {
        c_refuse(b, p, node.tok, "a packed or aligned enum")
        return false
    }
    let msvc = is_msvc(b.tu.target)
    let int_t = c_builtin(b, "int")
    // the type an enumerator has while the body is read: `int` for a value `int` holds, else its
    // initializer's, or with none the one before's (clang's rule under linux)
    var prev_t = int_t
    var items : array<CirEnumItem>
    var next = 0l
    var lowest = 0l
    var highest = 0l
    var e = node.c
    while (e >= 0) {
        let en = p.ast.nodes[e]
        var v = next
        var init_t = prev_t
        if (en.b >= 0 && !invoke(b.fold_type, b, p, en.b, v, init_t)) {
            c_refuse(b, p, p.ast.nodes[en.b].tok, "an enumerator value other than an integer constant expression")
            return false
        }
        // under msvc an initializer's value is converted to the enum's `int` at once; one counted on
        // from the one before is read unwrapped in the body, and wrapped in the enum
        if (msvc && en.b >= 0) {
            v = as_int(v)
        }
        let held = msvc ? as_int(v) : v
        let name = c_symbol_text(p.unit, en.a)
        items |> push(CirEnumItem(name = name, v = held))
        let own_t = v >= -2147483648l && v <= 2147483647l ? int_t : en.b >= 0 ? init_t : prev_t == int_t ? c_builtin(b, "unsigned int") : prev_t
        c_ir_bind(b, en.a, CId(t = own_t, old_style = -1, enum_t = pt, enum_v = v, name = name))
        prev_t = own_t
        lowest = min(lowest, held)
        highest = max(highest, held)
        next = v + 1l
        e = en.next
    }
    let is_signed = msvc || lowest < 0l
    if ((is_signed && (lowest < -2147483648l || highest > 2147483647l)) || (!is_signed && highest > 4294967295l)) {
        c_refuse(b, p, node.tok, "an enum whose values no 32-bit type holds")
        return false
    }
    b.pool[pt].is_signed = is_signed
    b.pool[pt].items <- items
    bind_enumerators(b, p, n, pt)
    return true
}

// the enumerators of enum specifier `n`, built into pool enum `pt`, bound in the innermost scope:
// each an `int`, or under linux the enum's `unsigned int` when one of its values is past INT_MAX
[arch(at="ARCHITECTURE_RECORDS.md#c-records-enums")]
def private bind_enumerators(var b : CTypes; p : CParser; n, pt : int) {
    var wide = false
    for (item in b.pool[pt].items) {
        wide ||= item.v > 2147483647l
    }
    let t = c_builtin(b, wide && !b.pool[pt].is_signed ? "unsigned int" : "int")
    var e = p.ast.nodes[n].c
    for (item in b.pool[pt].items) {
        c_ir_bind(b, p.ast.nodes[e].a, CId(t = t, old_style = -1, enum_t = pt, enum_v = item.v, name = item.name))
        e = p.ast.nodes[e].next
    }
}

// specifier `n` with a body defined: its pool type, the tag's earlier incomplete one where a use
// came first, built now, named as `c_tag_names` names it. False with the error set for a tag
// defined again in its own scope, an enum defined again in another and a tag of another kind
[arch(at="ARCHITECTURE_RECORDS.md#c-records-definitions")]
def private define_tag(var b : CTypes; var p : CParser; n : int) : int {
    let node = p.ast.nodes[n]
    let kind = tag_kind(p, n)
    let tag = b.tag_names_of?[n] ?? ""
    var pt = -1
    if (node.a >= 0 && c_tag_in_scope(b, node.a)) {
        pt = b.tags?[node.a] ?? -1
        if (b.pool[pt].k != kind || kind == "enum" || key_exists(b.layouts, pt) || b.used[pt] >= 0) {
            c_refuse(b, p, node.tok, "{kind_name(p, n)} tag defined again")
        } else {
            // only a block reaches here: a file-scope definition is the look-ahead's
            c_refuse(b, p, node.tok, "{kind_name(p, n)} declared in its block before its definition there, a new incomplete type Dumper A does not lower,")
        }
        return -1
    } else {
        if (kind == "enum" && node.a >= 0 && key_exists(b.defined_tags, "enum {c_symbol_text(p.unit, node.a)}")) {
            c_refuse(b, p, node.tok, "an enum tag defined again in another scope")
            return -1
        }
        pt = new_tag(b, kind, tag)
        if (kind == "enum") {
            b.pool[pt].spell = !empty(tag) ? "enum {tag}" : "enum (unnamed at {c_where(p.unit, node.tok)})"
        }
        if (node.a >= 0) {
            c_types_bind_tag(b, node.a, pt)
        }
    }
    if (node.a >= 0) {
        b.defined_tags["{kind} {c_symbol_text(p.unit, node.a)}"] = true
    }
    let ok = kind == "enum" ? build_enum(b, p, n, pt) : build_record(b, p, n, pt)
    if (!ok) {
        b.tag_built |> erase(n)
    }
    return ok ? pt : -1
}

// the name a record or enum with no tag takes from typedef declaration `decl`, as clang gives one
// for linkage: the first declarator that is the name alone (in parentheses or not), when the
// specifiers carry no qualifier; "" for any other
def private typedef_hint(var p : CParser; decl : int) : string {
    var spec = p.ast.nodes[decl].a
    while (spec >= 0) {
        let s = p.ast.nodes[spec]
        return "" if (s.kind == CNode.SPEC_KEYWORD && (s.op == int(CTok.CONST) || s.op == int(CTok.VOLATILE) || s.op == int(CTok.RESTRICT)))
        spec = s.next
    }
    var id = p.ast.nodes[decl].b
    while (id >= 0) {
        var d = p.ast.nodes[id].a
        while (d >= 0 && p.ast.nodes[d].kind == CNode.D_PAREN) {
            d = p.ast.nodes[d].a
        }
        return c_symbol_text(p.unit, p.ast.nodes[d].a) if (d >= 0 && p.ast.nodes[d].kind == CNode.D_NAME)
        id = p.ast.nodes[id].next
    }
    return ""
}

// what `c_tag_names` gathers over the unit: the record definitions with a tag in source order,
// the names a numbered tag avoids, each untagged definition's typedef name
struct private TagNaming {
    records : array<int>
    taken : table<string>
}

// node `n` and the nodes under it, in source order, into `naming` and `b.tag_names_of`
def private gather_names(var b : CTypes; var p : CParser; n : int; var naming : TagNaming) {
    return if (n < 0)
    let node = p.ast.nodes[n]
    let library = in_library_file(b, p, node.tok)
    if ((node.kind == CNode.SPEC_RECORD || node.kind == CNode.SPEC_ENUM) && node.b == 1) {
        if (node.a >= 0) {
            b.tag_names_of[n] = c_symbol_text(p.unit, node.a)
            if (!library) {
                naming.taken |> insert(b.tag_names_of[n])
                if (node.kind == CNode.SPEC_RECORD) {
                    naming.records |> push(n)
                }
            }
        } elif (!key_exists(b.tag_names_of, n)) {
            b.tag_names_of[n] = ""
        }
    } elif (node.kind == CNode.DECL || node.kind == CNode.FUNC_DEF) {
        let typedef_decl = node.kind == CNode.DECL && c_declares_typedef(p, node.a)
        if (typedef_decl) {
            let hint = typedef_hint(p, n)
            var spec = node.a
            while (spec >= 0) {
                let s = p.ast.nodes[spec]
                if ((s.kind == CNode.SPEC_RECORD || s.kind == CNode.SPEC_ENUM) && s.b == 1 && s.a < 0) {
                    b.tag_names_of[spec] = hint
                }
                spec = s.next
            }
        }
        var id = node.kind == CNode.DECL ? node.b : -1
        while (id >= 0) {
            let sym = c_declarator_name(p.ast, p.ast.nodes[id].a)
            if (sym >= 0 && (typedef_decl || !library)) {
                naming.taken |> insert(c_symbol_text(p.unit, sym))
            }
            id = p.ast.nodes[id].next
        }
        if (node.kind == CNode.FUNC_DEF && !library && node.b >= 0) {
            let sym = c_declarator_name(p.ast, p.ast.nodes[node.b].a)
            if (sym >= 0) {
                naming.taken |> insert(c_symbol_text(p.unit, sym))
            }
        }
    }
    let form = NODE_FORMS[int(node.kind)]._1
    peek_data(form) $(roles) {
        for (k, child in range(1, 5), fixed_array(node.a, node.b, node.c, node.d)) {
            let role = int(roles[k])
            if (role == 'n') {
                gather_names(b, p, child, naming)
            } elif (role == 'l' || role == 'a') {
                var at = child
                while (at >= 0) {
                    gather_names(b, p, at, naming)
                    at = p.ast.nodes[at].next
                }
            }
        }
    }
}

//! The name each record and enum definition of unit node `u` takes, as Dumper A names them
//! (`converter/dumper_a.das`'s `name_shared_tags`): a tagged one its tag, but the second and later
//! definitions of one `struct T` or `union T` in source order the first `T<n>` from 1 that no
//! record or enum definition's tag, typedef name (the own headers' too) or variable or function name
//! of the unit spells; one with no tag the name a typedef gives it for linkage (`typedef_hint`),
//! else "".
[arch(at="ARCHITECTURE_RECORDS.md#c-records-definitions")]
def c_tag_names(var b : CTypes; var p : CParser; u : int) {
    var naming : TagNaming
    gather_names(b, p, u, naming)
    var first : table<string>
    for (n in naming.records) {
        let tag = b.tag_names_of?[n] ?? ""
        let spelling = "{tag_kind(p, n)} {tag}"
        if (!key_exists(first, spelling)) {
            first |> insert(spelling)
            continue
        }
        var k = 1
        while (key_exists(naming.taken, "{tag}{k}")) {
            k++
        }
        naming.taken |> insert("{tag}{k}")
        b.tag_names_of[n] = "{tag}{k}"
    }
}

//! The pool type of struct, union or enum specifier `n` (`CTypes.tag_type`): a definition's, built
//! where a definition may stand; a use's, the tag's definition, which its one file-scope definition
//! completes at the first use (an incomplete record where it has none). -1 with the error set for
//! a definition elsewhere (a parameter, a type name), an enum used before its definition and a tag
//! of another kind.
[arch(at="ARCHITECTURE_RECORDS.md#c-records-definitions")]
def c_tag_type(var b : CTypes; var p : CParser; n : int) : int {
    let node = p.ast.nodes[n]
    let kind = tag_kind(p, n)
    if (node.b == 1) {
        let built = b.tag_built?[n] ?? -1
        return built if (built >= 0)
        if (b.defining == 0 || b.in_type_name > 0) {
            c_refuse(b, p, node.tok, "{kind_name(p, n)} defined in this place")
            return -1
        }
        return define_tag(b, p, n)
    }
    let why = b.untyped_tags?[node.a] ?? ""
    if (!empty(why)) {
        c_refuse(b, p, node.tok, "the tag '{c_symbol_text(p.unit, node.a)}'", ": {why}")
        return -1
    }
    let known = b.tags?[node.a] ?? -1
    if (known >= 0) {
        if (b.pool[known].k != kind) {
            c_refuse(b, p, node.tok, "{kind_name(p, n)} tag of another kind's")
            return -1
        }
        return known
    }
    let defined = b.tag_defs?[node.a] ?? -1
    if (kind == "enum" && (defined < 0 || p.ast.nodes[defined].kind != CNode.SPEC_ENUM)) {
        c_refuse(b, p, node.tok, "an enum used before its definition")
        return -1
    } elif (defined >= 0 && tag_kind(p, defined) != kind) {
        c_reject(b, p, node.tok, "{kind_name(p, n)} tag whose definition is of another kind")
        return -1
    }
    let built = defined >= 0 ? b.tag_built?[defined] ?? -1 : -1
    if (built >= 0) {
        c_types_bind_tag(b, node.a, built)
        return built
    }
    let pt = new_tag(b, kind, defined >= 0 ? b.tag_names_of?[defined] ?? "" : c_symbol_text(p.unit, node.a))
    if (kind == "enum") {
        b.pool[pt].spell = "enum {b.pool[pt].name}"
    }
    c_types_bind_tag(b, node.a, pt)
    if (defined >= 0) {
        b.tag_built[defined] = pt
        b.tag_pending |> push(int2(defined, pt))
    }
    return pt
}

//! Build the records whose one file-scope definition a use reached before it (`c_tag_type`), now
//! that the declaration of the use is bound: before a type is interned, a member is read or a size
//! taken. False with the error set for a definition the builder refuses.
[arch(at="ARCHITECTURE_RECORDS.md#c-records-definitions")]
def c_tag_complete(var b : CTypes; var p : CParser) : bool {
    while (!empty(b.tag_pending)) {
        let next = b.tag_pending[0]
        b.tag_pending |> erase(0)
        var ok = false
        // the definition stands at file scope: its members read the file scope's names
        c_in_file_scope(b) $(var fb) {
            // the definition stands where a declaration does, not in the type name of the use, whose
            // specifiers were read before any array size could complete it
            fb.in_type_name = 0
            fb.defining++
            ok = p.ast.nodes[next.x].kind == CNode.SPEC_ENUM ? build_enum(fb, p, next.x, next.y) : build_record(fb, p, next.x, next.y)
            fb.complete_from[next.y] = p.ast.nodes[next.x].tok
            fb.defining--
        }
        return false if (!ok)
    }
    return true
}

// the file-scope record definitions of specifier list `specs` and of the members under them into
// `b.tag_defs` by tag; a tag defined twice gets none
def private look_ahead(var b : CTypes; var p : CParser; specs : int) {
    var at = specs
    while (at >= 0) {
        let n = p.ast.nodes[at]
        if ((n.kind == CNode.SPEC_RECORD || n.kind == CNode.SPEC_ENUM) && n.b == 1) {
            if (n.a >= 0) {
                b.tag_defs[n.a] = at
            }
            var m = n.kind == CNode.SPEC_RECORD ? n.c : -1
            while (m >= 0) {
                if (p.ast.nodes[m].kind == CNode.MEMBER_DECL) {
                    look_ahead(b, p, p.ast.nodes[m].a)
                }
                m = p.ast.nodes[m].next
            }
        }
        at = n.next
    }
}

//! The one file-scope definition of each record and enum tag of unit node `u`, the own headers'
//! included, which a use of the tag before it completes, and each file-scope typedef name's one
//! declaration, which such a definition's members may name before the walk binds it: Dumper A reads
//! a record's fields where its type is first reached, from clang's whole unit.
[arch(at="ARCHITECTURE_RECORDS.md#c-records-definitions")]
def c_tag_lookahead(var b : CTypes; var p : CParser; u : int) {
    var at = p.ast.nodes[u].a
    while (at >= 0) {
        let n = p.ast.nodes[at]
        if (n.kind == CNode.DECL || n.kind == CNode.FUNC_DEF) {
            look_ahead(b, p, n.a)
        }
        if (n.kind == CNode.DECL && c_declares_typedef(p, n.a)) {
            var id = n.b
            while (id >= 0) {
                let d = p.ast.nodes[id].a
                let sym = c_declarator_name(p.ast, d)
                b.typedef_defs[sym] = key_exists(b.typedef_defs, sym) ? int2(-1, -1) : int2(at, d)
                id = p.ast.nodes[id].next
            }
        }
        at = n.next
    }
}

//! The definitions of specifier list `specs` walked as Dumper A walks them: each built, the definitions among its members first, then interned and anchored by
//! a `record` or `enumdef` declaration at its tag (its keyword with none). An own header's
//! (`library`) is built alone: it is interned and anchored where the unit first uses it. False with
//! the error set for one the builder refuses.
[arch(at="ARCHITECTURE_RECORDS.md#c-records-order")]
def c_tag_definitions(var b : CTypes; var p : CParser; specs : int; library : bool) : bool {
    var at = specs
    while (at >= 0) {
        let n = p.ast.nodes[at]
        if ((n.kind == CNode.SPEC_RECORD || n.kind == CNode.SPEC_ENUM) && n.b == 1) {
            var pt = b.tag_built?[at] ?? -1
            if (pt < 0) {
                b.defining++
                pt = define_tag(b, p, at)
                b.defining--
                return false if (pt < 0)
            }
            return false if (!c_tag_complete(b, p))
            if (n.kind == CNode.SPEC_ENUM) {
                bind_enumerators(b, p, at, pt)
            }
            if (!library) {
                if (n.kind == CNode.SPEC_RECORD) {
                    var m = n.c
                    while (m >= 0) {
                        if (p.ast.nodes[m].kind == CNode.MEMBER_DECL) {
                            return false if (!c_tag_definitions(b, p, p.ast.nodes[m].a, false))
                        }
                        m = p.ast.nodes[m].next
                    }
                }
                let idx = c_types_use(b, pt)
                return false if (!empty(b.err))
                b.anchored[pt] = true
                let tok = tag_tok(p, at)
                let place = p.unit.toks[tok]
                let name = b.pool[pt].name
                b.tu.decls |> push(new CirDecl(k = n.kind == CNode.SPEC_ENUM ? "enumdef" : "record", name = name, c_name = name, t = idx, loc = CirLoc(file = c_file_name(p.unit, place.read_file), line = place.read_line, col = place.col)))
            }
        }
        at = n.next
    }
    return true
}
