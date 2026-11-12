options gen2

module link public

require strings
require math
require daslib/strings_boost
require daslib/fio
require cir

//! The C-IR link: the trees of several translation units, as the dumper built them, into one
//! program tree the emitter takes as it takes one unit. Nothing here knows clang or daslang
//! syntax: the type tables merge into one, every external symbol binds to its one definition, and
//! a file-scope static keeps its owning unit, renamed only where its name collides.

//! The linked program: the merged tree, whose `tu` names the entry unit's file, with the unit each
//! of its declarations came from; the first refusal; and the link's report, one line per static
//! renamed, per declaration bound to another unit's definition and per header function kept once.
struct LinkResult {
    program : CirTu
    owners : array<int>
    error : string
    renamed : array<string>
    bound : array<string>
    deduplicated : array<string>
}

// the merged type table and each unit's map into it; the definition that completed a merged
// record or enum, for a refusal's location
struct private Linker {
    types : array<CirType>
    index : table<string; int>
    maps : array<array<int>>
    origin : table<int; CirLoc>
    error : string
}

//! What the link knows of a program before it names the statics, which the partition into modules
//! reads (`converter/layout.das`): the unit defining each external name that has a definition (or a
//! tentative one), and per unit the names its code references that none of its statics,
//! parameters, locals or labels declares.
struct LinkFacts {
    defined_in : table<string; int>
    refs : array<table<string>>
}

// a declaration by its unit and its index there
struct private DeclRef {
    tu : int
    at : int
}

def private loc_text(loc : CirLoc) : string => "{loc.file}:{loc.line}"

// the location of the definition of type `t` of `tu`: its `record` or `enumdef` anchor, else the unit
def private anchor_of(tu : CirTu; t : int) : CirLoc {
    for (d in tu.decls) {
        if ((d.k == "record" || d.k == "enumdef") && d.t == t) {
            return d.loc
        }
    }
    return CirLoc(file = tu.tu)
}

def private mapped(m : array<int>; idx : int) : int => idx >= 0 && idx < length(m) ? m[idx] : idx

// `t` of a unit as a merged entry: the entry with `key` when there is one, else `t` appended
def private interned(var lk : Linker; key : string; var t : CirType) : int {
    let known = lk.index?[key] ?? -1
    if (known >= 0) {
        return known
    }
    let idx = length(lk.types)
    lk.types |> emplace(t)
    lk.index[key] = idx
    return idx
}

def private same_dims(a, b : array<CirDim>) : bool {
    if (length(a) != length(b)) {
        return false
    }
    for (x, y in a, b) {
        if (x.item != y.item || (!empty(x.item) && x.enum_t != y.enum_t)) {
            return false
        }
    }
    return true
}

def private same_fields(a, b : array<CirField>) : bool {
    if (length(a) != length(b)) {
        return false
    }
    for (x, y in a, b) {
        if (x.name != y.name || x.t != y.t || x.off != y.off || x.bit_off != y.bit_off || x.bit_w != y.bit_w || x.is_bitfield != y.is_bitfield || !same_dims(x.dims, y.dims)) {
            return false
        }
    }
    return true
}

def private same_items(a, b : array<CirEnumItem>) : bool {
    if (length(a) != length(b)) {
        return false
    }
    for (x, y in a, b) {
        if (x.name != y.name || x.v != y.v) {
            return false
        }
    }
    return true
}

def private remap_dims(var dims : array<CirDim>; m : array<int>) {
    for (dim in dims) {
        if (!empty(dim.item)) {
            dim.enum_t = mapped(m, dim.enum_t)
        }
    }
}

// a record of unit `ti` by its spelling, which is location-based for an anonymous one and so the
// same in every unit that includes its header: the first complete definition fills the merged
// entry, a later one must lay it out alike
def private merge_record(var lk : Linker; tu : CirTu; ti, idx : int) : int {
    let spelled = empty(tu.types[idx].spell) ? tu.types[idx].name : tu.types[idx].spell
    var shell = CirType(k = tu.types[idx].k, name = tu.types[idx].name, spell = tu.types[idx].spell, size = -1, align = -1)
    let at = interned(lk, "{tu.types[idx].k}:{spelled}", shell)
    lk.maps[ti][idx] = at
    if (tu.types[idx].size < 0) {
        return at
    }
    var fields : array<CirField>
    fields |> reserve(length(tu.types[idx].fields))
    for (f in tu.types[idx].fields) {
        var field = CirField(name = f.name, t = merge_type(lk, tu, ti, f.t), off = f.off, bit_off = f.bit_off, bit_w = f.bit_w, is_bitfield = f.is_bitfield)
        if (!empty(lk.error)) {
            return -1
        }
        field.dims := f.dims
        for (dim in field.dims) {
            if (!empty(dim.item)) {
                dim.enum_t = merge_type(lk, tu, ti, dim.enum_t)
            }
        }
        fields |> emplace(field)
    }
    if (lk.types[at].size < 0) {
        lk.types[at].size = tu.types[idx].size
        lk.types[at].align = tu.types[idx].align
        lk.types[at].packed = tu.types[idx].packed
        lk.types[at].fields <- fields
        lk.origin[at] = anchor_of(tu, idx)
        return at
    }
    if (lk.types[at].size != tu.types[idx].size || lk.types[at].align != tu.types[idx].align || lk.types[at].packed != tu.types[idx].packed || !same_fields(lk.types[at].fields, fields)) {
        lk.error = "`{spelled}` is defined with two different layouts: {loc_text(lk.origin?[at] ?? CirLoc())} and {loc_text(anchor_of(tu, idx))}"
        return -1
    }
    return at
}

def private merge_enum(var lk : Linker; tu : CirTu; ti, idx : int) : int {
    var t := tu.types[idx]
    let key = "enum:{t.spell}"
    let known = lk.index?[key] ?? -1
    if (known >= 0 && (!same_items(lk.types[known].items, t.items) || lk.types[known].is_signed != t.is_signed)) {
        lk.error = "`{t.spell}` is defined with two different enumerator lists: {loc_text(lk.origin?[known] ?? CirLoc())} and {loc_text(anchor_of(tu, idx))}"
        return -1
    }
    let at = interned(lk, key, t)
    if (known < 0) {
        lk.origin[at] = anchor_of(tu, idx)
    }
    lk.maps[ti][idx] = at
    return at
}

//! Type `idx` of unit `ti` as an index into the merged table: a record by its spelling, an enum by
//! its spelling, every other type by its kind and its merged parts.
def private merge_type(var lk : Linker; tu : CirTu; ti, idx : int) : int {
    if (idx < 0 || idx >= length(tu.types)) {
        return idx
    }
    let known = lk.maps[ti][idx]
    if (known >= 0) {
        return known
    }
    let k = tu.types[idx].k
    if (k == "struct" || k == "union") {
        return merge_record(lk, tu, ti, idx)
    }
    if (k == "enum") {
        return merge_enum(lk, tu, ti, idx)
    }
    var t := tu.types[idx]
    var key : string
    if (k == "void") {
        key = "void"
    } elif (k == "int") {
        key = "int:{t.w}:{t.is_signed}:{t.spell}"
    } elif (k == "float") {
        key = "float:{t.w}:{t.spell}"
    } elif (k == "ptr") {
        t.to = merge_type(lk, tu, ti, t.to)
        key = "ptr:{t.to}"
    } elif (k == "array") {
        t.elem = merge_type(lk, tu, ti, t.elem)
        key = "array:{t.elem}:{t.count}"
    } elif (k == "func") {
        t.ret = merge_type(lk, tu, ti, t.ret)
        for (p in t.params) {
            p = merge_type(lk, tu, ti, p)
        }
        let params = join([for (p in t.params); string(p)], ",")
        key = "func:{t.ret}:{params}:{t.variadic}"
    } elif (k == "typedef") {
        t.to = merge_type(lk, tu, ti, t.to)
        key = "typedef:{t.name}:{t.to}"
    } else {
        lk.error = "{tu.tu}: type kind `{k}` has no link rule"
        return -1
    }
    if (!empty(lk.error)) {
        return -1
    }
    let at = interned(lk, key, t)
    lk.maps[ti][idx] = at
    return at
}

def private remap_expr(var x : CirExpr?; m : array<int>) {
    if (x == null) {
        return
    }
    x.t = mapped(m, x.t)
    if (x.e == "enum_ref") {
        x.enum_t = mapped(m, x.enum_t)
    } elif (x.e == "sizeof_v" || x.e == "alignof_v" || x.e == "offsetof") {
        x.of_t = mapped(m, x.of_t)
    } elif (x.e == "va_arg") {
        x.arg_t = mapped(m, x.arg_t)
    }
    remap_expr(x.a, m)
    remap_expr(x.b, m)
    remap_expr(x.c, m)
    remap_expr(x.fn, m)
    remap_expr(x.base, m)
    remap_expr(x.i, m)
    remap_expr(x.list, m)
    remap_expr(x.init, m)
    for (arg in x.args) {
        remap_expr(arg, m)
    }
    for (item in x.init_items) {
        remap_expr(item.v, m)
    }
}

def private remap_stmt(var x : CirStmt?; m : array<int>) {
    if (x == null) {
        return
    }
    if (x.s == "decl") {
        x.t = mapped(m, x.t)
        remap_dims(x.dims, m)
    }
    remap_expr(x.init, m)
    remap_expr(x.e, m)
    remap_expr(x.cond, m)
    remap_expr(x.inc, m)
    remap_stmt(x.then_s, m)
    remap_stmt(x.else_s, m)
    remap_stmt(x.body_s, m)
    remap_stmt(x.init_s, m)
    for (child in x.body) {
        remap_stmt(child, m)
    }
}

def private remap_decl(var d : CirDecl?; m : array<int>) {
    d.t = mapped(m, d.t)
    for (p in d.params) {
        p.t = mapped(m, p.t)
    }
    remap_dims(d.dims, m)
    remap_expr(d.init, m)
    remap_stmt(d.body, m)
}

// the references to a renamed static, outside the scopes where a parameter or local of the same
// name hides it; `hidden` counts the enclosing declarations of each such name. With `collect` the
// walk renames nothing: every name a parameter, local or label declares lands in `declared`, and
// every reference no such declaration hides in `refs`
struct private Renaming {
    names : table<string; string>
    hidden : table<string; int>
    collect : bool
    refs : table<string>
    declared : table<string>
}

def private rename_expr(var rn : Renaming; var x : CirExpr?) {
    if (x == null) {
        return
    }
    if (x.e == "ref" && (rn.hidden?[x.name] ?? 0) == 0) {
        let to = rn.names?[x.name] ?? ""
        if (rn.collect) {
            rn.refs |> insert(x.name)
        } elif (!empty(to)) {
            x.name = to
        }
    }
    rename_expr(rn, x.a)
    rename_expr(rn, x.b)
    rename_expr(rn, x.c)
    rename_expr(rn, x.fn)
    rename_expr(rn, x.base)
    rename_expr(rn, x.i)
    rename_expr(rn, x.list)
    rename_expr(rn, x.init)
    for (arg in x.args) {
        rename_expr(rn, arg)
    }
    for (item in x.init_items) {
        rename_expr(rn, item.v)
    }
}

def private hide(var rn : Renaming; name : string; var scope : array<string>) {
    if (rn.collect) {
        rn.declared |> insert(name)
    }
    if (rn.collect || key_exists(rn.names, name)) {
        rn.hidden[name] = (rn.hidden?[name] ?? 0) + 1
        scope |> push(name)
    }
}

def private unhide(var rn : Renaming; scope : array<string>) {
    for (name in scope) {
        rn.hidden[name] = rn.hidden[name] - 1
    }
}

// a block's declarations hide a name from their own initializer to the end of the block, a `for`
// header's to the end of the loop
def private rename_stmt(var rn : Renaming; var x : CirStmt?; var scope : array<string>) {
    if (x == null) {
        return
    }
    if (x.s == "compound" || x.s == "for") {
        var inner : array<string>
        // a `for` header declaring several variables holds them in a block of its own
        if (x.init_s != null && x.init_s.s == "compound") {
            for (child in x.init_s.body) {
                rename_stmt(rn, child, inner)
            }
        } else {
            rename_stmt(rn, x.init_s, inner)
        }
        rename_expr(rn, x.cond)
        rename_expr(rn, x.inc)
        rename_stmt(rn, x.body_s, inner)
        for (child in x.body) {
            rename_stmt(rn, child, inner)
        }
        unhide(rn, inner)
        return
    }
    if (x.s == "decl") {
        hide(rn, x.name, scope)
    } elif (x.s == "label" && rn.collect) {
        rn.declared |> insert(x.label_name)
    }
    rename_expr(rn, x.init)
    rename_expr(rn, x.e)
    rename_expr(rn, x.cond)
    rename_expr(rn, x.inc)
    var arm : array<string>
    rename_stmt(rn, x.then_s, arm)
    unhide(rn, arm)
    arm |> clear()
    rename_stmt(rn, x.else_s, arm)
    unhide(rn, arm)
    arm |> clear()
    rename_stmt(rn, x.body_s, arm)
    unhide(rn, arm)
}

def private walk_decl(var rn : Renaming; var d : CirDecl?) {
    var inscope scope : array<string>
    for (p in d.params) {
        hide(rn, p.name, scope)
    }
    rename_expr(rn, d.init)
    rename_stmt(rn, d.body, scope)
    unhide(rn, scope)
}

// every reference in `tu` to a key of `names` takes its value, and so does the declaration itself
def private rename_unit(var tu : CirTu; names : table<string; string>) {
    if (empty(names)) {
        return
    }
    var rn : Renaming
    rn.names := names
    for (d in tu.decls) {
        if ((d.k == "func" || d.k == "global") && d.is_static) {
            d.name = names?[d.name] ?? d.name
        }
        walk_decl(rn, d)
    }
}

// the names `d` references that no parameter, local or label of its own declares
def private free_refs(var d : CirDecl?) : table<string> {
    var rn = Renaming(collect = true)
    walk_decl(rn, d)
    return <- rn.refs
}

def private is_symbol(d : CirDecl?) : bool => d.k == "func" || d.k == "global"

// the name a static wants in the program: a file-scope one its C name, a local one the dumper's
// hoisted `<function>_<name>`
def private wanted_name(d : CirDecl?) : string => empty(d.from_func) ? d.c_name : d.name

// a function defined in a header the unit includes, rather than in the unit's own file
def private from_header(tu : CirTu; d : CirDecl?) : bool => base_name(d.loc.file) != tu.tu

// whether every unit holding a copy of `group` holds one of `callee`'s group too, so each copy's
// call reaches the one copy `callee`'s group keeps
def private covers(callee, group : array<DeclRef>) : bool {
    for (c in group) {
        if (!has_value([for (other in callee); other.tu], c.tu)) {
            return false
        }
    }
    return true
}

// what a name a header copy references is in unit `ti`: "object" or "function" for a static of the
// unit, "external" otherwise (a definition of the program, a libc name, a parameter or local)
def private name_kind(tus : array<CirTu>; units : array<UnitNames>; ti : int; name : string) : string {
    let di = units[ti].statics?[name] ?? -1
    return di < 0 ? "external" : tus[ti].decls[di].k == "func" ? "function" : "object"
}

// whether every reference of the copies resolves alike in every unit holding one: an external in
// all of them, or a static function in all of them whose own group stands over those units; a
// static object stays one copy per unit, so it never does
def private resolves_alike(var tus : array<CirTu>; units : array<UnitNames>; standing : table<string; array<DeclRef>>; name : string; scope : int; copies : array<DeclRef>) : bool {
    var refs <- free_refs(tus[copies[0].tu].decls[copies[0].at])
    for (ref in keys(refs)) {
        let kind = name_kind(tus, units, copies[0].tu, ref)
        for (c in copies) {
            if (name_kind(tus, units, c.tu, ref) != kind) {
                return false
            }
        }
        if (kind == "object") {
            return false
        }
        if (kind == "function" && ref != name) {
            var covered = false
            standing |> get(scoped_key(ref, scope)) $(callee) {
                covered = covers(callee, copies)
            }
            if (!covered) {
                return false
            }
        }
    }
    return true
}

// a header function's group within one scope, by its name and the scope
def private scoped_key(name : string; scope : int) : string => "{name}@{scope}"

// the header functions identical in several units of one scope (one output module), each a group of
// copies by scope, name and bytes keyed by `scoped_key`; a group stands while its references resolve
// alike in every unit of it (`resolves_alike`)
def private header_groups(var tus : array<CirTu>; units : array<UnitNames>; scopes : array<int>) : table<string; array<DeclRef>> {
    var groups : table<string; array<DeclRef>>
    for (ti, tu in count(), tus) {
        for (di, d in count(), tu.decls) {
            if (d.k == "func" && d.is_static && d.body != null && from_header(tu, d)) {
                groups["{scopes[ti]}\n{d.name}\n{write_cir_decl(*d, true)}"] |> push(DeclRef(tu = ti, at = di))
            }
        }
    }
    var standing : table<string; array<DeclRef>>
    for (copies in values(groups)) {
        if (length(copies) > 1) {
            standing[scoped_key(tus[copies[0].tu].decls[copies[0].at].name, scopes[copies[0].tu])] := copies
        }
    }
    var changed = true
    while (changed) {
        var inscope fallen : array<string>
        for (key, copies in keys(standing), values(standing)) {
            let first = DeclRef(tu = copies[0].tu, at = copies[0].at)
            if (!resolves_alike(tus, units, standing, tus[first.tu].decls[first.at].name, scopes[first.tu], copies)) {
                fallen |> push(key)
            }
        }
        for (key in fallen) {
            standing |> erase(key)
        }
        changed = !empty(fallen)
    }
    return <- standing
}

//! A unit's file stem as an identifier: the prefix of its renamed statics and its node's stem in
//! the layout.
def unit_stem(tu : CirTu) : string => ident_of(file_stem(tu.tu))

def private same_target(a, b : CirTarget) : bool =>
    a.triple == b.triple && a.int_w == b.int_w && a.long_w == b.long_w && a.llong_w == b.llong_w && a.ptr_w == b.ptr_w && a.char_signed == b.char_signed

// the units' trees with every type index in the merged table, which becomes the program's
def private merge_types(var tus : array<CirTu>; var program : CirTu) : string {
    var lk : Linker
    lk.maps |> resize(length(tus))
    for (ti in range(length(tus))) {
        lk.maps[ti] |> resize(length(tus[ti].types))
        for (idx in range(length(tus[ti].types))) {
            lk.maps[ti][idx] = -1
        }
        for (idx in range(length(tus[ti].types))) {
            merge_type(lk, tus[ti], ti, idx)
            if (!empty(lk.error)) {
                return lk.error
            }
        }
    }
    for (ti in range(length(tus))) {
        for (d in tus[ti].decls) {
            remap_decl(d, lk.maps[ti])
        }
    }
    program.types <- lk.types
    return ""
}

// why the array the declarations `refs` of `name` declare cannot be the object `chosen` defines, ""
// when it can: a declaration giving it a length other than the definition's (`extern int a[3];`
// against `int a[4];`), which C leaves undefined; one of unknown length takes the definition's
def private length_mismatch(tus : array<CirTu>; types : array<CirType>; name : string; refs : array<DeclRef>; chosen : DeclRef) : string {
    let def_decl = tus[chosen.tu].decls[chosen.at]
    if (types[def_decl.t].k != "array" || types[def_decl.t].count < 0) {
        return ""
    }
    for (ref in refs) {
        let d = tus[ref.tu].decls[ref.at]
        if (types[d.t].k == "array" && types[d.t].count >= 0 && types[d.t].count != types[def_decl.t].count) {
            // `chosen` is a definition unless no unit defines the array, when it is the first declaration
            let defined = def_decl.is_extern ? "declared an array of {types[def_decl.t].count} at {loc_text(def_decl.loc)}, and no unit defines it" : "defined an array of {types[def_decl.t].count} at {loc_text(def_decl.loc)}"
            return "`{name}` is declared an array of {types[d.t].count} at {loc_text(d.loc)} and {defined}"
        }
    }
    return ""
}

// the declaration every external name binds to, by name: its definition with a body or an
// initializer, else its first tentative definition, else its first declaration; a tentative
// definition merges into the initialized one
def private bind_externals(var tus : array<CirTu>; var res : LinkResult; var keep : table<string; DeclRef>; var facts : LinkFacts) {
    var uses : table<string; array<DeclRef>>
    var order : array<string>
    for (ti, tu in count(), tus) {
        for (di, d in count(), tu.decls) {
            if (is_symbol(d) && !d.is_static) {
                if (!key_exists(uses, d.name)) {
                    order |> push(d.name)
                }
                uses[d.name] |> push(DeclRef(tu = ti, at = di))
            }
        }
    }
    for (name in order) {
        uses |> get(name) $(refs) {
            let first = tus[refs[0].tu].decls[refs[0].at]
            var strong = DeclRef(tu = -1, at = -1)
            var tentative = DeclRef(tu = -1, at = -1)
            for (ref in refs) {
                let d = tus[ref.tu].decls[ref.at]
                if (d.k != first.k) {
                    res.error = "`{name}` is a function in one unit and an object in another: {loc_text(first.loc)} and {loc_text(d.loc)}"
                    return
                }
                let defines = d.k == "func" ? d.body != null : d.init != null
                if (defines && strong.tu >= 0) {
                    let other = tus[strong.tu].decls[strong.at].loc
                    if (other.file == d.loc.file && other.line == d.loc.line) {
                        res.error = "`{name}` is defined in {tus[strong.tu].tu} and {tus[ref.tu].tu} by {loc_text(d.loc)}: a function or object a header defines without `static` (C99 `inline` among them) is one definition per unit, which the link does not merge yet"
                    } else {
                        res.error = "`{name}` is defined twice: {loc_text(other)} and {loc_text(d.loc)}"
                    }
                    return
                }
                if (defines) {
                    strong = ref
                } elif (tentative.tu < 0 && d.k == "global" && !d.is_extern) {
                    tentative = ref
                }
            }
            let chosen = strong.tu >= 0 ? strong : tentative.tu >= 0 ? tentative : refs[0]
            res.error = length_mismatch(tus, res.program.types, name, refs, chosen)
            return if (!empty(res.error))
            if (strong.tu >= 0 || tentative.tu >= 0) {
                facts.defined_in[name] = chosen.tu
                for (ref in refs) {
                    if (ref.tu != chosen.tu) {
                        res.bound |> push("{tus[ref.tu].tu}: {name} -> {tus[chosen.tu].tu}")
                    }
                }
            }
            keep[name] = chosen
        }
        break if (!empty(res.error))
    }
}

// what the link knows of each unit: its statics by the name they want, with their index; the
// header functions it shares with an earlier unit's copy, by name, with that unit; and the final
// name of each static whose name changes
struct private UnitNames {
    statics : table<string; int>
    copied_from : table<string; int>
    finals : table<string; string>
    // the names the unit's code references that none of its parameters, locals or labels
    // declares, and the names those declare
    refs : table<string>
    locals : table<string>
}

// the program's bindings: each unit's names, the declaration each external name keeps and the
// dropped header copies, by `<unit>:<index>`
struct private Binding {
    units : array<UnitNames>
    keep : table<string; DeclRef>
    dropped : table<string>
}

// why the units cannot link, "" when they can: none, an entry other than `main`, two dialects, or
// two units of one stem
def private refusal(tus : array<CirTu>; entry : string) : string {
    if (empty(tus)) {
        return "a program needs at least one translation unit"
    }
    if (entry != "main") {
        return "the program's entry `{entry}` is not `main`: C `main` is the one entry point the emitter wraps"
    }
    var stems : table<string; string>
    for (tu in tus) {
        if (!same_target(tu.target, tus[0].target)) {
            return "{tu.tu} is dumped for {tu.target.triple}, {tus[0].tu} for {tus[0].target.triple}"
        }
        let stem = unit_stem(tu)
        let other = stems?[stem] ?? ""
        if (!empty(other)) {
            return "{other} and {tu.tu} share the stem `{stem}`"
        }
        stems[stem] = tu.tu
    }
    return ""
}

// every static by the name it wants, so the copies of a header function compare, each unit's
// statics recorded by that name, and the names each unit's code references and declares; two
// statics of one unit wanting one name are refused (Dumper A names a hoisted local static past
// every file-scope name of its unit), so the one renaming of `rename_collisions` names them all
def private want_names(var tus : array<CirTu>; var b : Binding) : string {
    b.units |> resize(length(tus))
    for (tu, unit in tus, b.units) {
        var inscope wanted, claimed : table<string; string>
        for (d in tu.decls) {
            if (is_symbol(d) && d.is_static && !key_exists(wanted, d.name)) {
                let want = wanted_name(d)
                let other = claimed?[want] ?? ""
                // a guard: Dumper A gives a hoisted static a name past every file-scope name, so no C input reaches it
                if (!empty(other)) {
                    return "{tu.tu}: the statics `{other}` and `{d.name}` both want the name `{want}`"
                }
                claimed[want] = d.name
                wanted[d.name] = want
            }
        }
        rename_unit(tu, wanted)
        var rn = Renaming(collect = true)
        for (di, d in count(), tu.decls) {
            if (is_symbol(d) && d.is_static) {
                unit.statics[d.name] = di
            }
            walk_decl(rn, d)
        }
        unit.refs <- rn.refs
        unit.locals <- rn.declared
    }
    return ""
}

// a header function kept once lives in its first unit; the other units' copies drop
def private share_header_copies(var tus : array<CirTu>; var b : Binding; scopes : array<int>; var res : LinkResult) {
    let groups <- header_groups(tus, b.units, scopes)
    for (copies in values(groups)) {
        let name = tus[copies[0].tu].decls[copies[0].at].name
        res.deduplicated |> push("{name}: {join([for (c in copies); tus[c.tu].tu], ", ")}")
        for (c in copies) {
            if (c.tu != copies[0].tu) {
                b.dropped |> insert("{c.tu}:{c.at}")
                b.units[c.tu].copied_from[name] = copies[0].tu
            }
        }
    }
    sort(res.deduplicated)
}

// whether `unit` reaches its copy of header function `name` through unit `ti`'s kept copy
def private copies_from(unit : UnitNames; name : string; ti : int) : bool => (unit.copied_from?[name] ?? -1) == ti

// the first of `<want>`, `<want>1`, `<want>2`, ... neither `taken` nor any of `blocked` holds; it
// is then taken
def private fresh_name(var taken : table<string>; blocked : array<table<string>>; want : string) : string {
    var name = want
    var n = 1
    while (key_exists(taken, name) || has_value([for (names in blocked); key_exists(names, name)], true)) {
        name = "{want}{n}"
        n++
    }
    taken |> insert(name)
    return name
}

// a static keeps its name unless another owner takes it: an external name of the program, a name
// the emitter maps to libc or c_runtime (`reserved`), or, in a unit of its scope (its output
// module), a name the unit's code references without a static of its own by that name or the
// unit's own static (a header function kept once owned by its first unit). A renamed static takes
// `<stem>_<name>`, the next free one past every file-scope name of the program and every
// parameter, local and label of the units that call it; a shared header copy's references reach
// its kept copy's name
def private rename_collisions(var tus : array<CirTu>; var b : Binding; reserved : array<string>; scopes : array<int>; var res : LinkResult) {
    // by name, -1 for a name of the whole program and each unit referencing it or holding a
    // static of it
    var owners : table<string; table<int>>
    var taken : table<string>
    for (name in keys(b.keep)) {
        owners[name] |> insert(-1)
    }
    for (name in reserved) {
        owners[name] |> insert(-1)
    }
    for (ti, unit in count(), b.units) {
        for (name in keys(unit.refs)) {
            if (!key_exists(unit.statics, name)) {
                owners[name] |> insert(ti)
            }
        }
        for (name in keys(unit.statics)) {
            if (!key_exists(unit.copied_from, name)) {
                owners[name] |> insert(ti)
            }
        }
    }
    for (name in keys(owners)) {
        taken |> insert(name)
    }
    for (ti, tu, unit in count(), tus, b.units) {
        var inscope names <- [for (name in keys(unit.statics)); name; where !key_exists(unit.copied_from, name)]
        sort(names)
        for (name in names) {
            var others = false
            owners |> get(name) $(units) {
                for (other in keys(units)) {
                    others = others || other == -1 || (other != ti && scopes[other] == scopes[ti])
                }
            }
            if (others) {
                var inscope blocked <- [for (other in b.units); other.locals; where copies_from(other, name, ti)]
                blocked |> push_clone(unit.locals)
                let renamed = fresh_name(taken, blocked, "{unit_stem(tu)}_{name}")
                unit.finals[name] = renamed
                res.renamed |> push("{tu.tu}: {name} -> {renamed}")
            }
        }
    }
    for (tu, unit in tus, b.units) {
        for (name, owner in keys(unit.copied_from), values(unit.copied_from)) {
            let kept = b.units[owner].finals?[name] ?? ""
            if (!empty(kept)) {
                unit.finals[name] = kept
            }
        }
        rename_unit(tu, unit.finals)
    }
}

// the declarations in link order into the program: each external once at its binding, the
// statics but the dropped copies, each type anchor once, each with its unit in `owners`; the
// program's `tu` the unit defining `main`
def private gather(var tus : array<CirTu>; b : Binding; var res : LinkResult) {
    var anchors : table<string>
    for (ti, tu in count(), tus) {
        for (di in range(length(tu.decls))) {
            var d = tu.decls[di]
            tu.decls[di] = null
            var take = true
            if (is_symbol(d) && !d.is_static) {
                let chosen = b.keep?[d.name] ?? DeclRef(tu = -1, at = -1)
                take = chosen.tu == ti && chosen.at == di
            } elif (is_symbol(d)) {
                take = !key_exists(b.dropped, "{ti}:{di}")
            } else {
                let anchor = d.k == "typedefdecl" ? "{d.k}:{d.name}:{d.t}" : "{d.k}:{d.t}"
                take = !key_exists(anchors, anchor)
                anchors |> insert(anchor)
            }
            if (take && d.k == "func" && d.c_name == "main" && !d.is_static && d.body != null) {
                res.program.tu = tu.tu
            }
            if (take) {
                res.program.decls |> push(d)
                res.owners |> push(ti)
            } else {
                delete_decl(d)
            }
        }
        tu.decls |> clear()
    }
}

// the expansion marks of expression `x` and below: each `m` through `remap`, each id past `offset`;
// `top` the highest id after
def private remap_macro_expr(var x : CirExpr?; remap : array<int>; offset : int; var top : int&) {
    if (x == null) {
        return
    }
    for (u in x.fn_macro) {
        u.m = remap[u.m]
        u.site += offset
        top = max(top, u.site)
    }
    for (a in x.macro_args) {
        a.site += offset
    }
    for (part in fixed_array(x.a, x.b, x.c, x.fn, x.base, x.i, x.list, x.init)) {
        remap_macro_expr(part, remap, offset, top)
    }
    for (arg in x.args) {
        remap_macro_expr(arg, remap, offset, top)
    }
    for (item in x.init_items) {
        remap_macro_expr(item.v, remap, offset, top)
    }
}

def private remap_macro_stmt(var st : CirStmt?; remap : array<int>; offset : int; var top : int&) {
    if (st == null) {
        return
    }
    for (u in st.fn_macro) {
        u.m = remap[u.m]
        u.site += offset
        top = max(top, u.site)
    }
    for (x in fixed_array(st.init, st.e, st.cond, st.inc)) {
        remap_macro_expr(x, remap, offset, top)
    }
    for (child in fixed_array(st.then_s, st.else_s, st.body_s, st.init_s)) {
        remap_macro_stmt(child, remap, offset, top)
    }
    for (child in st.body) {
        remap_macro_stmt(child, remap, offset, top)
    }
}

// the units' function-like macros into the program's one table, a `#define` (name, file, line,
// text) once, each unit's expansions renumbered past every earlier unit's so an id names one
// expansion in the program
[arch(at="ARCHITECTURE_LINK.md#link-macros")]
def private merge_macros(var tus : array<CirTu>; var program : CirTu) {
    var index : table<string; int>
    var offset = 0
    for (tu in tus) {
        var inscope remap : array<int>
        remap |> reserve(length(tu.macros))
        for (m in tu.macros) {
            let key = "{m.name}\n{m.file}\n{m.line}\n{m.text}"
            if (!key_exists(index, key)) {
                index[key] = length(program.macros)
                program.macros |> push_clone(m)
            }
            remap |> push(index?[key] ?? 0)
        }
        var top = offset - 1
        for (d in tu.decls) {
            remap_macro_expr(d.init, remap, offset, top)
            remap_macro_stmt(d.body, remap, offset, top)
        }
        offset = top + 1
        tu.macros |> clear()
    }
}

//! Links the dumper's trees of a program's units, in link order, into one tree: the merged type
//! table, one declaration per external name (prototypes and `extern` declarations bound to the
//! definition, tentative definitions merged), every unit's statics, renamed `<stem>_<name>` only
//! where the name collides with an external or with a static or a reference of another unit of its
//! scope, a function a header defines in several units of one scope kept once where every copy is
//! identical, the type anchors once each. `scoping` sees the units (their types already indices into
//! the merged table), that table and the link's facts once the externals are bound, and gives each
//! unit its scope, the output module that holds it (`converter/layout.das`), or a refusal. The units'
//! declarations move into the program, which leaves `tus` without any. `entry` must be `main`; the
//! program's `tu` is the file of the unit defining it, else the first unit's.
[arch(at="ARCHITECTURE_LINK.md#link")]
def link_tus(var tus : array<CirTu>; entry : string; reserved : array<string>; scoping : block<(tus : array<CirTu>; types : array<CirType>; facts : LinkFacts; var scopes : array<int>) : string>) : LinkResult {
    var res : LinkResult
    res.error = refusal(tus, entry)
    if (!empty(res.error)) {
        return <- res
    }
    res.program.cir = tus[0].cir
    res.program.producer = tus[0].producer
    res.program.target = tus[0].target
    res.program.tu = tus[0].tu
    merge_macros(tus, res.program)
    res.error = merge_types(tus, res.program)
    if (!empty(res.error)) {
        return <- res
    }
    var b : Binding
    res.error = want_names(tus, b)
    if (!empty(res.error)) {
        return <- res
    }
    var facts : LinkFacts
    bind_externals(tus, res, b.keep, facts)
    if (!empty(res.error)) {
        return <- res
    }
    facts.refs <- [for (unit in b.units); {for (name in keys(unit.refs)); name; where !key_exists(unit.statics, name)}]
    var scopes : array<int>
    res.error = invoke(scoping, tus, res.program.types, facts, scopes)
    if (!empty(res.error)) {
        return <- res
    }
    if (length(scopes) != length(tus)) {
        scopes |> resize(length(tus))
    }
    share_header_copies(tus, b, scopes, res)
    rename_collisions(tus, b, reserved, scopes, res)
    gather(tus, b, res)
    return <- res
}

//! `link_tus` with every unit in one scope, one output module.
def link_tus(var tus : array<CirTu>; entry : string; reserved : array<string>) : LinkResult {
    return <- link_tus(tus, entry, reserved) $(_tus, _types, _facts, _scopes) : string {
        return ""
    }
}

//! `link_tus` with no name reserved beyond the program's own.
def link_tus(var tus : array<CirTu>; entry : string) : LinkResult => link_tus(tus, entry, array<string>())
