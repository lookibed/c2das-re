options gen2
options indenting = 4

module c_types public

require strings
require daslib/strings_boost
require c_parser public
require c_layout public
require ../converter/cir.das public
require ../converter/bit_units.das

//! What an identifier names where the walk stands: a variable or a function, its declared pool
//! type, the parameter types an old-style definition's calls convert to, and whether its
//! declaration has a prototype.
struct CId {
    t : int
    is_function : bool
    proto : bool
    old_style : int     //!< the pool function type an old-style definition's calls convert by, -1 for none
    builtin : bool      //!< a builtin function of `BUILTIN_FUNCTIONS`, referenced only as a callee
    name : string       //!< the name a reference to it spells in the C-IR (`ARCHITECTURE_NAMES.md`)
    enum_t : int = -1   //!< an enumerator: the pool enum type it belongs to; -1 for any other identifier
    enum_v : int64      //!< an enumerator's value
}

//! The C-IR type table of one unit as Dumper A builds it (`ARCHITECTURE_TYPES.md`): every type a
//! declaration reaches, once, in the order Dumper A's walk first uses it, each `spell` as clang
//! spells it under the dialect. `pool` holds the types the builder has met, typedefs resolved, by
//! the same structural key, a qualified type apart from its unqualified one; `c_types_use` interns
//! a pool type into the table, qualifiers dropped, its parts first.
//! Beside it, what the walk over the unit keeps: the identifiers in scope, the return type of the
//! function being read, and the evaluator of an integer constant expression an array size spells
//! (`c_exprs.das`'s).
struct CTypes {
    tu : CirTu
    index : table<string; int>      //!< a table entry's key to its index
    pool : array<CirType>           //!< every type met, referring to other pool types
    pool_index : table<string; int> //!< a pool type's key to its index
    used : array<int>               //!< per pool type, its table index; -1 while no use reached it
    quals : array<int>              //!< per pool type, its own qualifiers (`C_CONST`, `C_VOLATILE`, `C_RESTRICT`)
    unqualified : array<int>        //!< per pool type, the pool type without its own qualifiers
    typedefs : table<int; int>      //!< a typedef name's symbol to the pool type it names
    untyped : table<int; string>    //!< a library typedef name the builder does not type, and why
    undo : array<tuple<sym : int; was : int>>   //!< the bindings a block's end restores
    marks : array<int>
    declared : table<int; bool>     //!< the function names declared so far
    library_dir : string            //!< the own libc headers' folder, whose declarations add no type
    old_style : array<int>          //!< the promoted parameter types an old-style definition's type takes
    ids : table<int; CId>           //!< an identifier's symbol to what it names where the walk stands
    id_undo : array<tuple<sym : int; had : bool; was : CId>>
    id_marks : array<int>
    ret : int                       //!< the pool result type of the function being read
    cases : table<int64; bool>      //!< the case values of the innermost switch read so far
    tu_prefix : string              //!< the unit's file stem as an identifier, a file static's prefix
    linkage_names : table<string; string>   //!< a name with internal linkage to its C-IR name
    file_scope_names : table<string>        //!< every name declared at file scope or by a block-scope `extern` or prototype
    hoisted_names : table<string>           //!< the names of the statics hoisted so far
    fn_all_locals : table<string>           //!< the parameter and variable names of the function being read, renames included
    fn_extern_names : table<string>         //!< the names its block-scope `extern` declarations and prototypes declare
    fn_name : string                        //!< the C name of the function being read
    fold : function<(var b : CTypes; var p : CParser; n : int; var v : int64&) : bool> //!< an integer constant expression's value; null for none
    prior : table<int; int>         //!< an ordinary name declared at file scope, or `extern`, to its (composite) pool type
    prototyped : table<int; bool>   //!< such a name whose function type has a prototype
    library_functions : table<int; int2>    //!< a function the own headers declare: its declaration and init-declarator
    unit_items : int                //!< the unit's first external declaration
    fold_type : function<(var b : CTypes; var p : CParser; n : int; var v : int64&; var t : int&) : bool> //!< the same with the expression's pool type, unqualified; null for none
    tag_type : function<(var b : CTypes; var p : CParser; n : int) : int> //!< a struct, union or enum specifier's pool type (`c_records.das`); null for none
    init_count : function<(var b : CTypes; var p : CParser; init, elem : int) : int> //!< the count an unsized array takes from an initializer list (`c_inits.das`); null for none
    init_static : bool                      //!< a static object's initializer is being read, where a flexible array member takes a value
    compound_literal : function<(var b : CTypes; var p : CParser; n : int) : CirExpr?> //!< a compound literal's C-IR (`c_inits.das`); null for none
    tags : table<int; int>                  //!< a tag's symbol to its pool record or enum type
    tag_undo : array<tuple<sym : int; was : int>>   //!< the tag bindings a block's end restores
    tag_marks : array<int>
    untyped_tags : table<int; string>       //!< a tag an own header defines that the builder does not type, and why
    defined_tags : table<string; bool>      //!< every `<kind> <tag>` a definition has named so far, in any scope
    tag_names_of : table<int; string>       //!< a record or enum specifier with a body to the name it takes (`c_tag_names`)
    typedef_defs : table<int; int2>         //!< a typedef name's one file-scope declaration (declaration, declarator), which a record built at an earlier use reads
    tag_defs : table<int; int>              //!< a tag's symbol to its one file-scope definition, built at the tag's first use
    tag_built : table<int; int>             //!< a record or enum specifier with a body to the pool type it defines
    tag_pending : array<int2>               //!< (definition, pool record) a use reached before the definition, not built yet
    layouts : table<int; CRecordLayout>     //!< a complete pool record to its layout
    library_tags : table<int; bool>         //!< the pool records and enums an own header defines, anchored where the unit first uses them
    anchored : table<int; bool>             //!< the pool records and enums a `record` or `enumdef` anchor names
    memo : LayoutMemo                       //!< the `packed` verdicts of the table's records
    anchor_at : CirLoc                      //!< the place of the declaration being read: a library record's anchor
    defining : int                          //!< above 0 while a definition is walked or built: where a specifier may define a tag
    in_type_name : int                      //!< above 0 while a type name is read, where no specifier defines a tag
    next_tag : int                          //!< the identity the next record or enum takes
    err : string
}

//! Open the builder over the dialect `target`, with an empty table; a declaration in a file whose
//! line-marker name starts with `library_dir`, the own libc headers' folder, adds no type, as
//! Dumper A dumps none of them ("" for none).
def c_types_open(var b : CTypes; target : CirTarget; library_dir : string) {
    b.tu.target = target
    b.library_dir = library_dir
    b.tu.types |> clear()
    b.index |> clear()
    b.pool |> clear()
    b.pool_index |> clear()
    b.used |> clear()
    b.quals |> clear()
    b.unqualified |> clear()
    b.typedefs |> clear()
    b.untyped |> clear()
    b.undo |> clear()
    b.marks |> clear()
    b.declared |> clear()
    b.tags |> clear()
    b.tag_undo |> clear()
    b.tag_marks |> clear()
    b.untyped_tags |> clear()
    b.defined_tags |> clear()
    b.tag_names_of |> clear()
    b.typedef_defs |> clear()
    b.tag_defs |> clear()
    b.tag_built |> clear()
    b.tag_pending |> clear()
    b.layouts |> clear()
    b.library_tags |> clear()
    b.anchored |> clear()
    b.memo = LayoutMemo()
    b.anchor_at = CirLoc()
    b.defining = 0
    b.in_type_name = 0
    b.next_tag = 0
    b.prior |> clear()
    b.prototyped |> clear()
    b.library_functions |> clear()
    b.unit_items = -1
    b.err = ""
}

//! The error, at token `tok`: a construct clang rejects (`what` is invalid C there), so the unit
//! has no C-IR, as Dumper A's clang gives it none; no rejection follows another error.
def c_reject(var b : CTypes; p : CParser; tok : int; what : string) {
    b.err = "{c_where(p.unit, tok)}: {what} is invalid C, which clang rejects"
}

//! Bind identifier `sym` to `id` in the innermost scope.
def c_ir_bind(var b : CTypes; sym : int; id : CId) {
    let had = key_exists(b.ids, sym)
    b.id_undo |> push((sym = sym, had = had, was = had ? b.ids?[sym] ?? id : id))
    b.ids[sym] = id
}

//! The first error, at token `tok`: a construct the builder does not type yet, and `why` after it.
def c_refuse(var b : CTypes; p : CParser; tok : int; what : string; why : string = "") {
    refuse(b, p, tok, what, why)
}

// the first error, at token `tok`: a construct the builder does not type yet, and `why` after it
def private refuse(var b : CTypes; p : CParser; tok : int; what : string; why : string = "") {
    if (empty(b.err)) {
        b.err = "{c_where(p.unit, tok)}: {what} is not typed yet{why}"
    }
}

//! Whether `t` is a struct, a union or an enum: a type of its own identity, which its `count`
//! holds (a record's and an enum's C-IR entry writes no `count`).
def c_is_tag_kind(t : CirType) : bool => t.k == "struct" || t.k == "union" || t.k == "enum"

//! The key a type is interned by, in the table or in the pool, as Dumper A keys it: an integer by
//! its width, sign and spelling; `double` and `long double` apart; a pointer, an array and a
//! function by the indices of their parts; a record and an enum by their identity.
def c_type_key(t : CirType) : string {
    if (c_is_tag_kind(t)) {
        return "tag:{t.count}"
    } elif (t.k == "int") {
        return "int:{t.w}:{t.is_signed}:{t.spell}"
    } elif (t.k == "float") {
        return t.w == 32 ? "float:32" : "float:64:{t.spell}"
    } elif (t.k == "ptr") {
        return "ptr:{t.to}"
    } elif (t.k == "array") {
        return "array:{t.elem}:{t.count}"
    } elif (t.k == "func") {
        let listed = join([for (x in t.params); string(x)], ",")
        return "func:{t.ret}:{listed}:{t.variadic}"
    }
    return t.k
}

// pool type `t`: the index it has, or the next one
def private pooled(var b : CTypes; var t : CirType) : int {
    let key = c_type_key(t)
    let known = b.pool_index?[key] ?? -1
    return known if (known >= 0)
    let idx = length(b.pool)
    b.pool |> emplace(t)
    b.pool_index[key] = idx
    b.quals |> push(0)
    b.used |> push(-1)
    b.unqualified |> push(idx)
    return idx
}

//! Pool type `t`: the index it has by its key, or the next one.
def c_pool_type(var b : CTypes; var t : CirType) : int => pooled(b, t)

//! The pool type of a reference to a builtin function, clang's `<builtin fn type>`: in the table
//! `void (...)`, which no other type of gnu17 is (`void f(...)` takes a parameter before `...`).
def c_builtin_fn_type(var b : CTypes) : int {
    var t = CirType(k = "func", ret = builtin_type(b, bit(CTok.VOID)), variadic = true)
    return pooled(b, t)
}

//! The qualifier bits of a pool type.
let C_CONST = 1
let C_VOLATILE = 2
let C_RESTRICT = 4

//! Pool type `t` with qualifiers `q` added: an array's element takes them (C11 6.7.3p9), a function
//! type none.
def c_qualified(var b : CTypes; t, q : int) : int {
    return t if (t < 0 || q == 0 || b.pool[t].k == "func")
    if (b.pool[t].k == "array") {
        let count = b.pool[t].count
        let elem = c_qualified(b, b.pool[t].elem, q)
        return array_of(b, elem, count)
    }
    let base = b.unqualified[t]
    let all = b.quals[t] | q
    let key = "q{all}:{base}"
    let known = b.pool_index?[key] ?? -1
    return known if (known >= 0)
    let idx = length(b.pool)
    var copy := b.pool[base]
    b.pool |> emplace(copy)
    b.pool_index[key] = idx
    b.quals |> push(all)
    b.used |> push(-1)
    b.unqualified |> push(base)
    return idx
}

// the qualifier bits of the qualifier keywords in list `at`
def private qualifiers_of(p : CParser; at : int) : int {
    var q = 0
    var n = at
    while (n >= 0) {
        let k = p.ast.nodes[n].op
        if (p.ast.nodes[n].kind == CNode.SPEC_KEYWORD) {
            q |= k == int(CTok.CONST) ? C_CONST : k == int(CTok.VOLATILE) ? C_VOLATILE : k == int(CTok.RESTRICT) ? C_RESTRICT : 0
        }
        n = p.ast.nodes[n].next
    }
    return q
}

// table entry `t` under `key`: the index it has, or the next one
def private intern(var b : CTypes; key : string; var t : CirType) : int {
    let known = b.index?[key] ?? -1
    return known if (known >= 0)
    let idx = length(b.tu.types)
    b.tu.types |> emplace(t)
    b.index[key] = idx
    return idx
}

//! The table index of pool type `pt`, interned with its parts first where no use reached it yet:
//! a pointer's target, an array's element, a function's result and then each parameter left to
//! right - the order Dumper A reads a type's spelling in. -1 for -1.
[arch(at="ARCHITECTURE_TYPES.md#c-types-order")]
def c_types_use(var b : CTypes; pt : int) : int {
    return -1 if (pt < 0)
    return b.used[pt] if (b.used[pt] >= 0)
    if (c_is_tag_kind(b.pool[pt])) {
        let idx = tag_use(b, b.unqualified[pt])
        b.used[pt] = idx
        return idx
    }
    var t := b.pool[pt]
    if (t.k == "ptr") {
        t.to = c_types_use(b, t.to)
    } elif (t.k == "array") {
        t.elem = c_types_use(b, t.elem)
    } elif (t.k == "func") {
        t.ret = c_types_use(b, t.ret)
        for (i in range(length(t.params))) {
            t.params[i] = c_types_use(b, t.params[i])
        }
    }
    let key = c_type_key(t)
    t.name = ""
    let idx = intern(b, key, t)
    return idx
}

// the table index of unqualified pool record or enum `pt`: its own slot first, so a pointer to it
// among its fields resolves, then each field's type in order and the field's `dims` enums, then
// its layout with the `packed` verdict; a record no definition completes is size and alignment -1.
// One an own header defines is anchored here, at the declaration being read
[arch(at="ARCHITECTURE_RECORDS.md#c-records-order")]
def private tag_use(var b : CTypes; pt : int) : int {
    return b.used[pt] if (b.used[pt] >= 0)
    var slot := b.pool[pt]
    slot.fields |> clear()
    let idx = intern(b, c_type_key(slot), slot)
    b.used[pt] = idx
    if (b.pool[pt].k != "enum") {
        var fields := b.pool[pt].fields
        for (f in fields) {
            f.t = c_types_use(b, f.t)
            for (dim in f.dims) {
                dim.enum_t = empty(dim.item) ? 0 : c_types_use(b, dim.enum_t)
            }
        }
        b.tu.types[idx].fields <- fields
        if (key_exists(b.layouts, pt)) {
            var err : string
            if (!c_layout_into_cir(b.tu, b.memo, idx, b.layouts[pt], err) && empty(b.err)) {
                b.err = err
            }
        }
    }
    if (key_exists(b.library_tags, pt) && !key_exists(b.anchored, pt) && (b.pool[pt].k == "enum" || key_exists(b.layouts, pt))) {
        b.anchored[pt] = true
        let name = b.pool[pt].name
        b.tu.decls |> push(new CirDecl(k = b.pool[pt].k == "enum" ? "enumdef" : "record", name = name, c_name = name, t = idx, loc = b.anchor_at))
    }
    return idx
}

def private int_type(var b : CTypes; w : int; is_signed : bool; spell : string) : int {
    var t = CirType(k = "int", w = w, is_signed = is_signed, spell = spell)
    return pooled(b, t)
}

def private pointer(var b : CTypes; to : int) : int {
    var t = CirType(k = "ptr", to = to)
    return pooled(b, t)
}

def private array_of(var b : CTypes; elem, count : int) : int {
    var t = CirType(k = "array", elem = elem, count = count)
    return pooled(b, t)
}

//! The size in bytes pool type `t` has as clang lays it out: a scalar's width, a pointer's and a
//! function's the pointer width, an enum's 4, an array its count of elements, a complete record its
//! layout's; -1 for a type without one.
def c_type_size(b : CTypes; t : int) : int64 {
    let u = b.unqualified[t]
    let k = b.pool[u].k
    if (k == "int" || k == "float") {
        return int64(b.pool[u].w / 8)
    } elif (k == "ptr" || k == "func") {
        return int64(b.tu.target.ptr_w / 8)
    } elif (k == "enum") {
        return 4l
    } elif (k == "array" && b.pool[u].count >= 0) {
        let elem = c_type_size(b, b.pool[u].elem)
        return elem < 0l ? -1l : int64(b.pool[u].count) * elem
    }
    var size = -1l
    if (k == "struct" || k == "union") {
        get(b.layouts, u) $(l) {
            size = l.size
        }
    }
    return size
}

//! The alignment in bytes pool type `t` has as clang lays it out: a scalar's size, an array's
//! element's, a complete record's layout's; -1 for a type without one.
def c_type_align(b : CTypes; t : int) : int {
    let u = b.unqualified[t]
    let k = b.pool[u].k
    if (k == "array") {
        return c_type_align(b, b.pool[u].elem)
    } elif (k == "void") {
        return -1
    }
    var align = int(c_type_size(b, u))
    if (k == "struct" || k == "union") {
        align = -1
        get(b.layouts, u) $(l) {
            align = l.align
        }
    }
    return align
}

//! The pool type of a pointer to pool type `to`.
def c_pointer(var b : CTypes; to : int) : int => pointer(b, to)

//! The pool type of an array of `count` pool types `elem`, -1 for an unknown count.
def c_array(var b : CTypes; elem, count : int) : int => array_of(b, elem, count)

//! The pool type of the function returning `ret` with the parameter types `params`.
def c_function(var b : CTypes; ret : int; var params : array<int>; variadic : bool) : int => function_of(b, ret, params, variadic)

//! The pool type of builtin type spelling `spell` as clang spells it (`int`, `unsigned long`,
//! `double`, ...); -1 for any other spelling.
def c_builtin(var b : CTypes; spell : string) : int {
    let plain = starts_with(spell, "unsigned ") ? slice(spell, length("unsigned ")) : spell
    for (entry in BUILTINS) {
        if (entry.spell == plain) {
            return builtin_type(b, plain == spell ? entry.set : entry.set | bit(CTok.UNSIGNED))
        }
    }
    return -1
}

def private function_of(var b : CTypes; ret : int; var params : array<int>; variadic : bool) : int {
    var t = CirType(k = "func", ret = ret, variadic = variadic)
    t.params <- [for (x in params); b.unqualified[x]]
    return pooled(b, t)
}

// the bit of a builtin type keyword in a specifier set, by its place after `void`; a second
// `long` is bit `LONG_LONG`
def private bit(k : CTok) : int => 1 << (int(k) - int(CTok.VOID))

let private LONG_LONG = 1 << 12

// the builtin specifier sets and the type each one is, as clang spells it; `w` -1 is the dialect's
// `int`, -2 its `long`, -3 its `long long`, -4 plain `char` (signed as the dialect says)
let private BUILTINS <- [
    (set = bit(CTok.VOID), k = "void", w = 0, sign = false, spell = "void"),
    (set = bit(CTok.BOOL), k = "int", w = 8, sign = false, spell = "_Bool"),
    (set = bit(CTok.CHAR), k = "int", w = -4, sign = false, spell = "char"),
    (set = bit(CTok.CHAR) | bit(CTok.SIGNED), k = "int", w = 8, sign = true, spell = "signed char"),
    (set = bit(CTok.CHAR) | bit(CTok.UNSIGNED), k = "int", w = 8, sign = false, spell = "unsigned char"),
    (set = bit(CTok.SHORT), k = "int", w = 16, sign = true, spell = "short"),
    (set = bit(CTok.INT), k = "int", w = -1, sign = true, spell = "int"),
    (set = bit(CTok.LONG), k = "int", w = -2, sign = true, spell = "long"),
    (set = bit(CTok.LONG) | LONG_LONG, k = "int", w = -3, sign = true, spell = "long long"),
    (set = bit(CTok.FLOAT), k = "float", w = 32, sign = false, spell = "float"),
    (set = bit(CTok.DOUBLE), k = "float", w = 64, sign = false, spell = "double"),
    (set = bit(CTok.LONG) | bit(CTok.DOUBLE), k = "float", w = 64, sign = false, spell = "long double")]

// the pool type of builtin specifier set `set`, -1 for a set that is none: `int` and `signed`
// fold into the set they qualify, and `unsigned` adds `unsigned ` to the spelling of every
// integer but the `char`s, which spell their sign themselves
[arch(at="ARCHITECTURE_TYPES.md#c-types-specifiers")]
def private builtin_type(var b : CTypes; set : int) : int {
    let unsigned_bit = bit(CTok.UNSIGNED)
    let has_unsigned = (set & unsigned_bit) != 0
    var core = set & ~bit(CTok.SIGNED) & ~bit(CTok.INT) & ~unsigned_bit
    if (core == 0) {
        core = bit(CTok.INT)
    } elif (core == bit(CTok.CHAR)) {
        core = set & ~bit(CTok.INT)
    }
    for (entry in BUILTINS) {
        continue if (entry.set != core)
        if (entry.k == "void") {
            var t = CirType(k = "void")
            return pooled(b, t)
        } elif (entry.k == "float") {
            var t = CirType(k = "float", w = entry.w, spell = entry.spell)
            return pooled(b, t)
        }
        let target = b.tu.target
        let w = entry.w == -1 ? target.int_w : entry.w == -2 ? target.long_w : entry.w == -3 ? target.llong_w : entry.w == -4 ? 8 : entry.w
        let sign = entry.w != -4 && entry.sign && !has_unsigned
        let spell = has_unsigned && entry.w != 8 && entry.w != -4 ? "unsigned {entry.spell}" : entry.spell
        return int_type(b, w, sign, spell)
    }
    panic("a builtin specifier set the parser admits has no type")
}

// the attribute words that change the type they stand on
let private TYPE_ATTRIBUTES <- ["mode", "__mode__", "vector_size", "__vector_size__", "ext_vector_type", "__ext_vector_type__"]

//! False with the error set when list `at` holds an attribute naming one of `TYPE_ATTRIBUTES`.
def c_plain_attributes(var b : CTypes; var p : CParser; at : int) : bool {
    var n = at
    while (n >= 0) {
        if (p.ast.nodes[n].kind == CNode.ATTRIBUTE) {
            for (t in range(p.ast.nodes[n].a, p.ast.nodes[n].b + 1)) {
                if (has_value(TYPE_ATTRIBUTES, c_spelling(p.unit, t))) {
                    refuse(b, p, t, "the attribute '{c_spelling(p.unit, t)}', which changes a type,")
                    return false
                }
            }
        }
        n = p.ast.nodes[n].next
    }
    return true
}

// the pool type specifier `at` names, a typedef name's, a `typeof` type name's, a struct's, union's
// or enum's; -1 with the error set for one the builder does not type
def private named_type(var b : CTypes; var p : CParser; at : int) : int {
    let n = p.ast.nodes[at]
    if (n.kind == CNode.SPEC_TYPEOF_TYPE) {
        return c_type_name_type(b, p, n.a)
    } elif (n.kind == CNode.SPEC_RECORD || n.kind == CNode.SPEC_ENUM) {
        let tagged = b.tag_type != null ? invoke(b.tag_type, b, p, at) : -1
        if (tagged < 0) {
            refuse(b, p, n.tok, n.kind == CNode.SPEC_ENUM ? "an enum type" : "a {c_kind_name(n.op)} type")
        }
        return tagged
    }
    var named = b.typedefs?[n.a] ?? -1
    let ahead = b.typedef_defs?[n.a] ?? int2(-1, -1)
    if (named < 0 && b.defining > 0 && ahead.x >= 0 && !key_exists(b.untyped, n.a)) {
        named = c_declarator_type(b, p, c_specifier_type(b, p, p.ast.nodes[ahead.x].a), ahead.y, false)
        return named if (named >= 0 || !empty(b.err))
    }
    if (named < 0) {
        let why = b.untyped?[n.a] ?? ""
        let name = c_symbol_text(p.unit, n.a)
        refuse(b, p, n.tok, "the typedef name '{name}'", empty(why) ? "" : ": {why}")
    }
    return named
}

//! The pool type a list of declaration specifiers names; -1 with the error set for one the builder
//! does not type yet. Qualifiers, storage classes and function specifiers give no C-IR type.
[arch(at="ARCHITECTURE_TYPES.md#c-types-specifiers")]
def c_specifier_type(var b : CTypes; var p : CParser; specs : int) : int {
    var set = 0
    var named = -1
    var at = specs
    while (at >= 0) {
        let n = p.ast.nodes[at]
        if (n.kind == CNode.SPEC_KEYWORD) {
            let k = n.op
            if (k >= int(CTok.VOID) && k <= int(CTok.BOOL)) {
                set |= k == int(CTok.LONG) && (set & bit(CTok.LONG)) != 0 ? LONG_LONG : 1 << (k - int(CTok.VOID))
            } elif (k == int(CTok.COMPLEX)) {
                refuse(b, p, n.tok, "a complex type")
                return -1
            } elif (k == int(CTok.ATOMIC)) {
                refuse(b, p, n.tok, "an _Atomic type")
                return -1
            }
        } elif (n.kind == CNode.SPEC_TYPEDEF_NAME || n.kind == CNode.SPEC_TYPEOF_TYPE || n.kind == CNode.SPEC_RECORD || n.kind == CNode.SPEC_ENUM) {
            named = named_type(b, p, at)
            return -1 if (named < 0)
        } elif (n.kind == CNode.SPEC_TYPEOF_EXPR) {
            refuse(b, p, n.tok, "typeof of an expression")
            return -1
        } elif (n.kind == CNode.SPEC_ALIGNAS_EXPR || n.kind == CNode.SPEC_ALIGNAS_TYPE) {
            refuse(b, p, n.tok, "an _Alignas alignment")
            return -1
        }
        at = n.next
    }
    return -1 if (!c_plain_attributes(b, p, specs))
    return c_qualified(b, named >= 0 ? named : builtin_type(b, set), qualifiers_of(p, specs))
}

// false with the error set when list `at` holds `_Atomic`
def private no_atomic(var b : CTypes; p : CParser; at : int) : bool {
    var n = at
    while (n >= 0) {
        if (p.ast.nodes[n].kind == CNode.SPEC_KEYWORD && p.ast.nodes[n].op == int(CTok.ATOMIC)) {
            refuse(b, p, p.ast.nodes[n].tok, "an _Atomic type")
            return false
        }
        n = p.ast.nodes[n].next
    }
    return true
}

//! The type a value of pool type `t` takes under the default argument promotions (C11 6.5.2.2p6):
//! an integer narrower than `int` is `int`, `float` is `double`, any other type its own, made a
//! function type's parameter, which drops its qualifiers.
def c_promoted(var b : CTypes; t : int) : int {
    assume ty = b.pool[t]
    if (ty.k == "int" && ty.w < b.tu.target.int_w) {
        return builtin_type(b, bit(CTok.INT))
    } elif (ty.k == "float" && ty.w == 32) {
        return builtin_type(b, bit(CTok.DOUBLE))
    }
    return t
}

// whether declarator `d` is at its end: none, its name, or parentheses around one
def private is_end(p : CParser; d : int) : bool {
    var at = d
    while (at >= 0 && p.ast.nodes[at].kind == CNode.D_PAREN) {
        at = p.ast.nodes[at].a
    }
    return at < 0 || p.ast.nodes[at].kind == CNode.D_NAME
}

// the value of integer constant expression node `n` (C11 6.6) as an array size or index (`what`),
// through the unit's one evaluator (`fold`, `c_exprs.das`'s); -2 with the error set for any other
// expression (a variable-length array is out of scope) and for a value below 0 or past 2^31 - 1
[arch(at="ARCHITECTURE_TYPES.md#c-types-declarators")]
def private constant_value(var b : CTypes; var p : CParser; n : int; what : string) : int {
    var v = 0l
    let folded = b.fold != null && invoke(b.fold, b, p, n, v)
    if (!folded) {
        refuse(b, p, p.ast.nodes[n].tok, "an {what} other than an integer constant expression")
        return -2
    } elif (v < 0l || v > 2147483647l) {
        refuse(b, p, p.ast.nodes[n].tok, "an {what} below 0 or past 2^31 - 1")
        return -2
    }
    return int(v)
}

// the bytes of a UTF-8 encoding of code point `c`
def private utf8_length(c : int) : int => c < 0x80 ? 1 : c < 0x800 ? 2 : c < 0x10000 ? 3 : 4

// the bytes a run of `count` adjacent string literals from token `first` makes, its NUL included:
// each escape one byte, a universal character name its UTF-8 bytes; -2 with the error set for a
// prefixed literal
[arch(at="ARCHITECTURE_TYPES.md#c-types-arrays")]
def private string_bytes(var b : CTypes; var p : CParser; first, count : int) : int {
    var bytes = 1
    for (t in range(first, first + count)) {
        if (!starts_with(c_spelling(p.unit, t), "\"")) {
            refuse(b, p, t, "a prefixed string literal")
            return -2
        }
        peek_data(c_spelling(p.unit, t)) $(text) {
            let stop = length(text) - 1
            var i = 1
            while (i < stop) {
                var size = 1
                if (text[i] == uint8('\\')) {
                    i++
                    let ch = int(text[i])
                    if (ch == 'x') {
                        while (i + 1 < stop && is_hex(int(text[i + 1]))) {
                            i++
                        }
                    } elif (ch >= '0' && ch <= '7') {
                        var k = 1
                        while (k < 3 && i + 1 < stop && int(text[i + 1]) >= '0' && int(text[i + 1]) <= '7') {
                            i++
                            k++
                        }
                    } elif (ch == 'u' || ch == 'U') {
                        let digits = ch == 'u' ? 4 : 8
                        var code = 0
                        for (k in range(digits)) {
                            let h = int(text[i + 1 + k])
                            code = code * 16 + (is_number(h) ? h - '0' : (h | 0x20) - 'a' + 10)
                        }
                        i += digits
                        size = utf8_length(code)
                    }
                }
                bytes += size
                i++
            }
        }
    }
    return bytes
}

//! The count an unsized array of pool type `elem` takes from initializer `init` (the node after a
//! declarator's `=`, or a compound literal's list): a string literal's bytes, braced alone or not
//! for a character array; a list's count by `init_count` (`c_inits.das`); -1 for no initializer;
//! -2 with the error set for any other.
[arch(at="ARCHITECTURE_TYPES.md#c-types-arrays")]
def c_initializer_count(var b : CTypes; var p : CParser; init, elem : int) : int {
    return -1 if (init < 0)
    let n = p.ast.nodes[init]
    if (n.kind == CNode.STRING) {
        return string_bytes(b, p, n.a, n.b)
    } elif (n.kind != CNode.INIT_LIST) {
        refuse(b, p, n.tok, "an unsized array initialized by this expression")
        return -2
    }
    let first = n.a
    if (first >= 0 && p.ast.nodes[first].next < 0 && p.ast.nodes[first].a < 0 && p.ast.nodes[p.ast.nodes[first].b].kind == CNode.STRING && b.pool[elem].k == "int" && b.pool[elem].w == 8) {
        return string_bytes(b, p, p.ast.nodes[p.ast.nodes[first].b].a, p.ast.nodes[p.ast.nodes[first].b].b)
    }
    return invoke(b.init_count, b, p, init, elem)
}

//! The pool type declarator `d` gives `base`, C's inside-out reading; `adjust` makes an array or a
//! function at the end a pointer (a parameter, C11 6.7.6.3p7-8), the array never met; `init` is
//! the initializer that sizes an unsized array at the end. `old_style` holds the promoted
//! parameter types an identifier list's function type takes.
[arch(at="ARCHITECTURE_TYPES.md#c-types-declarators")]
def c_declarator_type(var b : CTypes; var p : CParser; base, d : int; adjust : bool; init : int = -1) : int {
    return base if (base < 0 || d < 0)
    let n = p.ast.nodes[d]
    if (n.kind == CNode.D_NAME) {
        return base
    } elif (n.kind == CNode.D_PAREN) {
        return -1 if (!c_plain_attributes(b, p, n.b))
        return c_declarator_type(b, p, base, n.a, adjust, init)
    } elif (n.kind == CNode.D_POINTER) {
        return -1 if (!c_plain_attributes(b, p, n.b) || !no_atomic(b, p, n.b))
        return c_declarator_type(b, p, c_qualified(b, pointer(b, base), qualifiers_of(p, n.b)), n.a, adjust, init)
    } elif (n.kind == CNode.D_ARRAY) {
        let last = is_end(p, n.a)
        if (last && adjust) {
            return -1 if (!no_atomic(b, p, n.c))
            return c_qualified(b, pointer(b, base), qualifiers_of(p, n.c))
        }
        if (n.op == 2) {
            refuse(b, p, n.tok, "a variable-length array")
            return -1
        }
        let count = n.b >= 0 ? constant_value(b, p, n.b, "array size") : last ? c_initializer_count(b, p, init, base) : -1
        return -1 if (count == -2)
        return c_declarator_type(b, p, array_of(b, base, count), n.a, adjust, init)
    }
    var params : array<int>
    if (n.op == 2) {
        params := b.old_style
    }
    var param = n.op == 2 || c_is_void_list(b, p, n.b) ? -1 : n.b
    while (param >= 0) {
        let pt = c_param_type(b, p, param)
        return -1 if (pt < 0)
        params |> push(pt)
        param = p.ast.nodes[param].next
    }
    let f = function_of(b, base, params, n.op == 1)
    if (is_end(p, n.a) && adjust) {
        return pointer(b, f)
    }
    return c_declarator_type(b, p, f, n.a, adjust, init)
}

//! Whether parameter list `param` is `(void)`: one parameter, no declarator, `void` alone - the
//! keyword or a typedef name of it - with qualifiers aside.
def c_is_void_list(b : CTypes; p : CParser; param : int) : bool {
    return false if (param < 0 || p.ast.nodes[param].next >= 0 || p.ast.nodes[param].b >= 0)
    var found = false
    var at = p.ast.nodes[param].a
    while (at >= 0) {
        let n = p.ast.nodes[at]
        if (n.kind == CNode.SPEC_KEYWORD && n.op == int(CTok.VOID)) {
            found = true
        } elif (n.kind == CNode.SPEC_TYPEDEF_NAME) {
            let named = b.typedefs?[n.a] ?? -1
            return false if (named < 0 || b.pool[b.unqualified[named]].k != "void")
            found = true
        } elif (n.kind != CNode.SPEC_KEYWORD || n.op < int(CTok.CONST) || n.op > int(CTok.RESTRICT)) {
            return false
        }
        at = n.next
    }
    return found
}

// a typedef's array or function type, which a parameter declared with no declarator of its own
// adjusts too; the array's element is the pointer's target, the array itself never used
def private adjusted_base(var b : CTypes; base : int) : int {
    return base if (base < 0)
    let k = b.pool[base].k
    if (k == "array") {
        return pointer(b, b.pool[base].elem)
    }
    return k == "func" ? pointer(b, base) : base
}

//! The adjusted pool type that specifiers `specs` and declarator `d` give a parameter.
def c_parameter_type(var b : CTypes; var p : CParser; specs, d : int) : int {
    let base = c_specifier_type(b, p, specs)
    return c_declarator_type(b, p, is_end(p, d) ? adjusted_base(b, base) : base, d, true)
}

//! The adjusted pool type of parameter node `param`: an array or a function is a pointer.
def c_param_type(var b : CTypes; var p : CParser; param : int) : int {
    let n = p.ast.nodes[param]
    return -1 if (!c_plain_attributes(b, p, n.c))
    return c_parameter_type(b, p, n.a, n.b)
}

//! The pool type of type-name node `t` (C11 6.7.7).
def c_type_name_type(var b : CTypes; var p : CParser; t : int) : int {
    b.in_type_name++
    let base = c_specifier_type(b, p, p.ast.nodes[t].a)
    let typed = c_declarator_type(b, p, base, p.ast.nodes[t].b, false)
    b.in_type_name--
    return typed
}

//! Bind typedef name `sym` to pool type `t` in the innermost scope.
def c_types_bind(var b : CTypes; sym, t : int) {
    b.undo |> push((sym = sym, was = b.typedefs?[sym] ?? -1))
    b.typedefs[sym] = t
}

//! Open a scope of typedef names.
def c_types_scope_open(var b : CTypes) {
    b.marks |> push(length(b.undo))
    b.tag_marks |> push(length(b.tag_undo))
}

//! Bind tag `sym` to pool record or enum `t` in the innermost scope.
def c_types_bind_tag(var b : CTypes; sym, t : int) {
    b.tag_undo |> push((sym = sym, was = b.tags?[sym] ?? -1))
    b.tags[sym] = t
}

//! Whether tag `sym` is bound in the innermost scope, not an outer one.
def c_tag_in_scope(b : CTypes; sym : int) : bool {
    return key_exists(b.tags, sym) if (empty(b.tag_marks))
    for (at in range(b.tag_marks[length(b.tag_marks) - 1], length(b.tag_undo))) {
        return true if (b.tag_undo[at].sym == sym)
    }
    return false
}

//! Close the innermost scope of typedef names: its bindings are undone.
def c_types_scope_close(var b : CTypes) {
    let mark = b.marks[length(b.marks) - 1]
    b.marks |> pop()
    var at = length(b.undo) - 1
    while (at >= mark) {
        let entry = b.undo[at]
        if (entry.was < 0) {
            b.typedefs |> erase(entry.sym)
        } else {
            b.typedefs[entry.sym] = entry.was
        }
        at--
    }
    b.undo |> resize(mark)
    let tag_mark = b.tag_marks[length(b.tag_marks) - 1]
    b.tag_marks |> pop()
    var tat = length(b.tag_undo) - 1
    while (tat >= tag_mark) {
        let entry = b.tag_undo[tat]
        if (entry.was < 0) {
            b.tags |> erase(entry.sym)
        } else {
            b.tags[entry.sym] = entry.was
        }
        tat--
    }
    b.tag_undo |> resize(tag_mark)
}

//! `blk` run where the walk stands with the file scope's typedef names, tags and identifiers alone
//! in view, every block's and prototype's bindings set aside and put back after: a record whose one
//! file-scope definition a use in a block reached is built in the scope of its definition.
def c_in_file_scope(var b : CTypes; blk : block<(var b : CTypes) : void>) {
    var typedefs_now, tags_now : table<int; int>
    var ids_now : table<int; CId>
    var ids_had : table<int; bool>
    if (!empty(b.marks)) {
        var at = length(b.undo) - 1
        while (at >= b.marks[0]) {
            let entry = b.undo[at]
            if (!key_exists(typedefs_now, entry.sym)) {
                typedefs_now[entry.sym] = b.typedefs?[entry.sym] ?? -1
            }
            if (entry.was < 0) {
                b.typedefs |> erase(entry.sym)
            } else {
                b.typedefs[entry.sym] = entry.was
            }
            at--
        }
    }
    if (!empty(b.tag_marks)) {
        var at = length(b.tag_undo) - 1
        while (at >= b.tag_marks[0]) {
            let entry = b.tag_undo[at]
            if (!key_exists(tags_now, entry.sym)) {
                tags_now[entry.sym] = b.tags?[entry.sym] ?? -1
            }
            if (entry.was < 0) {
                b.tags |> erase(entry.sym)
            } else {
                b.tags[entry.sym] = entry.was
            }
            at--
        }
    }
    if (!empty(b.id_marks)) {
        var at = length(b.id_undo) - 1
        while (at >= b.id_marks[0]) {
            let entry = b.id_undo[at]
            if (!key_exists(ids_had, entry.sym)) {
                ids_had[entry.sym] = key_exists(b.ids, entry.sym)
                ids_now[entry.sym] = b.ids?[entry.sym] ?? CId()
            }
            if (entry.had) {
                b.ids[entry.sym] = entry.was
            } else {
                b.ids |> erase(entry.sym)
            }
            at--
        }
    }
    invoke(blk, b)
    for (sym, t in keys(typedefs_now), values(typedefs_now)) {
        if (t < 0) {
            b.typedefs |> erase(sym)
        } else {
            b.typedefs[sym] = t
        }
    }
    for (sym, t in keys(tags_now), values(tags_now)) {
        if (t < 0) {
            b.tags |> erase(sym)
        } else {
            b.tags[sym] = t
        }
    }
    for (sym, had in keys(ids_had), values(ids_had)) {
        if (had) {
            b.ids[sym] = ids_now?[sym] ?? CId()
        } else {
            b.ids |> erase(sym)
        }
    }
}

//! Whether specifier list `specs` holds `typedef`.
def c_declares_typedef(p : CParser; specs : int) : bool {
    var at = specs
    while (at >= 0) {
        return true if (p.ast.nodes[at].kind == CNode.SPEC_KEYWORD && p.ast.nodes[at].op == int(CTok.TYPEDEF))
        at = p.ast.nodes[at].next
    }
    return false
}

//! The `typedef` entry `t` interned by its name: one entry per name, whatever type a later
//! typedef of the name gives it.
def c_types_intern_typedef(var b : CTypes; var t : CirType) : int => intern(b, "typedef:{t.name}", t)

//! Pool type `t` of declarator `d`, an array of unknown size a typedef names, sized by initializer
//! `init` as one the declarator spells is (`c_declarator_type`): the declarator is the name alone.
[arch(at="ARCHITECTURE_TYPES.md#c-types-arrays")]
def c_sized_by_initializer(var b : CTypes; var p : CParser; t, d, init : int) : int {
    return t if (t < 0 || init < 0 || !is_end(p, d))
    let u = b.unqualified[t]
    return t if (b.pool[u].k != "array" || b.pool[u].count >= 0)
    let count = c_initializer_count(b, p, init, b.pool[u].elem)
    return count == -2 ? -1 : array_of(b, b.pool[u].elem, count)
}

// whether specifier list `specs` holds keyword `k`
def private has_keyword(p : CParser; specs : int; k : CTok) : bool {
    var at = specs
    while (at >= 0) {
        return true if (p.ast.nodes[at].kind == CNode.SPEC_KEYWORD && p.ast.nodes[at].op == int(k))
        at = p.ast.nodes[at].next
    }
    return false
}

// whether declarator `d` with initializer `init` gives its array a size: one written in its
// outermost array, or an initializer
def private gives_size(p : CParser; d, init : int) : bool {
    return true if (init >= 0)
    var at = d
    while (at >= 0 && p.ast.nodes[at].kind == CNode.D_PAREN) {
        at = p.ast.nodes[at].a
    }
    return at >= 0 && p.ast.nodes[at].kind == CNode.D_ARRAY && p.ast.nodes[at].b >= 0
}

//! The pool type of a file-scope declaration with no initializer and no `extern` (a tentative
//! definition, C11 6.9.2) of pool type `t`, init-declarator `id` declaring `sym`: an array of
//! unknown size is completed to one element at the unit's end, as clang does for the last such
//! definition, unless a later definition of the name follows; -1 with the error set when a later
//! `extern` declaration sizes it.
[arch(at="ARCHITECTURE_TYPES.md#c-types-arrays")]
def c_tentative(var b : CTypes; p : CParser; t, sym, id : int) : int {
    let u = b.unqualified[t]
    return t if (b.pool[u].k != "array" || b.pool[u].count >= 0)
    var after = false
    var decl = b.unit_items
    while (decl >= 0) {
        let dn = p.ast.nodes[decl]
        var other = dn.kind == CNode.DECL ? dn.b : -1
        while (other >= 0) {
            if (after && c_declarator_name(p.ast, p.ast.nodes[other].a) == sym) {
                let sized = gives_size(p, p.ast.nodes[other].a, p.ast.nodes[other].b)
                if (!has_keyword(p, dn.a, CTok.EXTERN)) {
                    return t
                } elif (sized) {
                    refuse(b, p, p.ast.nodes[id].tok, "an array of unknown size defined tentatively and sized by a later extern declaration", " (its completion waits for the Aggregates phase)")
                    return -1
                }
            }
            after = after || other == id
            other = p.ast.nodes[other].next
        }
        decl = dn.next
    }
    return array_of(b, b.pool[u].elem, 1)
}

//! Whether function declarator `f` declares a prototype: a parameter list, `(void)` included; an
//! empty `()` and an identifier list do not.
def c_has_prototype(p : CParser; f : int) : bool => f >= 0 && (p.ast.nodes[f].b >= 0 || p.ast.nodes[f].op == 1) && p.ast.nodes[f].op != 2

// the qualifiers of an object of pool type `t`: its own, or an array's element's
def private object_quals(b : CTypes; t : int) : int {
    let u = b.unqualified[t]
    return b.pool[u].k == "array" ? object_quals(b, b.pool[u].elem) : b.quals[t]
}

//! The pool type a declaration of `sym` with pool type `t` (function declarator `f`, -1 for none)
//! has after the declarations of the name before it (C11 6.2.7p4, the composite type): a function
//! declared with no prototype keeps the earlier prototype, a prototype or an old-style definition
//! after a declaration with none keeps its own type (Dumper A's), an array of unknown size the
//! earlier size; any other pair of different types is refused at token `tok`, as its composite waits for
//! the Aggregates phase. A function only the own headers declared before is the header's type.
[arch(at="ARCHITECTURE_TYPES.md#c-types-redeclarations")]
def c_linked(var b : CTypes; var p : CParser; t, sym, f, tok : int) : int {
    var prev = b.prior?[sym] ?? -1
    var prev_proto = b.prototyped?[sym] ?? false
    let u = b.unqualified[t]
    if (prev < 0 && b.pool[u].k == "func" && key_exists(b.library_functions, sym)) {
        let lib = b.library_functions?[sym] ?? int2(-1, -1)
        let lib_base = c_specifier_type(b, p, p.ast.nodes[lib.x].a)
        prev = c_declarator_type(b, p, lib_base, p.ast.nodes[lib.y].a, false)
        prev_proto = c_has_prototype(p, c_name_function(p.ast, p.ast.nodes[lib.y].a))
    }
    if (prev >= 0 && b.pool[u].k != "func" && object_quals(b, prev) != object_quals(b, t)) {
        c_reject(b, p, tok, "a redeclaration of '{c_symbol_text(p.unit, sym)}' with other qualifiers")
        return -1
    }
    let proto = c_has_prototype(p, f)
    let old_style = f >= 0 && p.ast.nodes[f].op == 2
    var result = t
    if (prev >= 0 && b.unqualified[prev] != u) {
        assume a = b.pool[b.unqualified[prev]]
        assume n = b.pool[u]
        let functions = a.k == "func" && n.k == "func" && b.unqualified[a.ret] == b.unqualified[n.ret]
        let arrays = a.k == "array" && n.k == "array" && b.unqualified[a.elem] == b.unqualified[n.elem]
        if ((functions && !proto && prev_proto) || (arrays && n.count < 0)) {
            result = prev
        } elif (!(functions && (proto || old_style) && !prev_proto) && !(arrays && a.count < 0)) {
            refuse(b, p, tok, "a redeclaration of '{c_symbol_text(p.unit, sym)}' whose type differs from the earlier one's", " (its composite type waits for the Aggregates phase)")
            return -1
        }
    }
    b.prior[sym] = result
    b.prototyped[sym] = proto || prev_proto
    return result
}

