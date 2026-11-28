options gen2
options indenting = 4

module c_ir public

require strings
require daslib/strings_boost
require math
require c_exprs public
require c_records public
require c_inits public
require c_consts public

//! A unit's C-IR from the parser's tree as Dumper A writes it (`ARCHITECTURE_TYPES.md`,
//! `ARCHITECTURE_EXPRS.md`): its declarations, the statements of its function bodies, their
//! expressions with every conversion, and the type table in the order Dumper A's walk interns it.

//! The producer Dumper C names in the C-IR it writes (`docs/c-ir-spec.md` section 1).
let C_IR_PRODUCER = "c2das-dumper-c 0.1"

//! Open the builder over the dialect `target` with an empty unit; `library_dir` is the own libc
//! headers' folder (`c_types_open`).
def c_ir_open(var r : CIr; target : CirTarget; library_dir : string) {
    c_types_open(r, target, library_dir)
    r.tu.decls |> clear()
    r.ids |> clear()
    r.id_undo |> clear()
    r.id_marks |> clear()
    r.ret = -1
    r.switch_t = -1
    r.weak_names |> clear()
    r.defined_names |> clear()
    r.fold = @@c_fold_node
    r.fold_type = @@c_fold_node_type
    r.tag_type = @@c_tag_type
    r.init_count = @@c_init_count
    r.compound_literal = @@c_compound_literal
    r.constant_expr = @@c_constant_expr
    r.expr_type = @@c_expr_type
    r.tu_prefix = ""
    r.linkage_names |> clear()
    r.file_scope_names |> clear()
    r.hoisted_names |> clear()
    r.fn_all_locals |> clear()
    r.fn_extern_names |> clear()
    r.fn_name = ""
}

// the place of token `tok` in the C-IR: where clang's expansion location puts it in the file as
// read, the outermost macro name's for a token an expansion made
[arch(at="ARCHITECTURE_NAMES.md#c-ir-places")]
def private loc_of(p : CParser; tok : int) : CirLoc {
    let t = p.unit.toks[tok]
    return CirLoc(file = c_file_name(p.unit, t.read_file), line = t.read_line, col = t.col)
}

// typed expression `x` interned and handed out; null stays null
def private used(var r : CIr; var p : CParser; var x : CirExpr?) : CirExpr? {
    if (x != null && !c_tag_complete(r, p)) {
        delete_expr(x)
        return null
    }
    c_exprs_use(r, x)
    return x
}

// the value of parser expression `n` read for its effect, or as a condition: a function, an array
// or an lvalue converted to a value (clang's ignored-value and condition conversions)
def private value_of(var r : CIr; var p : CParser; n : int) : CirExpr? {
    var x = c_expr(r, p, n)
    return x == null ? null : c_rvalue(r, x)
}

// whether expression node `n` is a character constant under parentheses, as Dumper A marks a
// `case` label's value
def private is_char_constant(p : CParser; n : int) : bool {
    let k = p.ast.nodes[n].kind
    return k == CNode.CHAR || (k == CNode.PAREN && is_char_constant(p, p.ast.nodes[n].a))
}

// the name a declarator declares, as text
def private name_of(var p : CParser; d : int) : string {
    let sym = c_declarator_name(p.ast, d)
    return sym < 0 ? "" : c_symbol_text(p.unit, sym)
}

// whether specifier list `specs` holds storage class `k`
def private has_storage(p : CParser; specs : int; k : CTok) : bool {
    var at = specs
    while (at >= 0) {
        return true if (p.ast.nodes[at].kind == CNode.SPEC_KEYWORD && p.ast.nodes[at].op == int(k))
        at = p.ast.nodes[at].next
    }
    return false
}

// the parameters of function declarator `f` as C-IR parameters, each its adjusted type interned
// again, as Dumper A reads each parameter's declaration after the function's type; a definition's
// (`defines`) named as its locals are
def private parameters(var r : CIr; var p : CParser; f : int; var into : array<CirParam>; defines : bool = false) : bool {
    return true if (p.ast.nodes[f].op == 2 || c_is_void_list(r, p, p.ast.nodes[f].b))
    var param = p.ast.nodes[f].b
    while (param >= 0) {
        let pt = c_param_type(r, p, param)
        return false if (pt < 0 || !c_tag_complete(r, p))
        let t = c_types_use(r, pt)
        let pname = name_of(p, p.ast.nodes[param].b)
        into |> push(CirParam(name = defines ? local_name(r, pname) : pname, t = t))
        param = p.ast.nodes[param].next
    }
    return true
}

// the identifier entry of function `sym` declared with pool type `t` by function declarator `f`
// (-1 for one declared through a typedef): a declaration with no prototype keeps the type and
// prototype of one before it, as clang's composite type does
def private function_id(r : CIr; p : CParser; sym, t, f : int) : CId {
    let proto = f < 0 || (p.ast.nodes[f].op != 2 && !(p.ast.nodes[f].op == 0 && p.ast.nodes[f].b < 0))
    let before = r.ids?[sym] ?? CId(t = -1, old_style = -1)
    if (!proto && before.t >= 0 && before.is_function) {
        return before
    }
    return CId(t = t, is_function = true, proto = proto, old_style = -1)
}

// a file-scope global `g`, merged into an earlier one of its name as Dumper A merges a tentative
// definition: the initializer and an `extern` declaration's completed type move to the earlier one
def private push_global(var r : CIr; var g : CirDecl?) {
    for (prev in r.tu.decls) {
        if (prev.k == "global" && prev.name == g.name && empty(prev.from_func)) {
            if (g.init != null && prev.init == null) {
                prev.init = g.init
                g.init = null
            }
            if (prev.is_extern && !g.is_extern) {
                prev.t = g.t
            }
            prev.is_extern = prev.is_extern && g.is_extern
            delete_decl(g)
            return
        }
    }
    r.tu.decls |> push(g)
}

// the token of the name declarator `d` declares, `fallback` for an abstract one: a declaration's
// place, as clang places it
def private name_tok(p : CParser; d, fallback : int) : int {
    var at = d
    while (at >= 0) {
        return p.ast.nodes[at].tok if (p.ast.nodes[at].kind == CNode.D_NAME)
        at = p.ast.nodes[at].a
    }
    return fallback
}

// `want` when no hoisted static, file-scope name of the unit or name of the function being read
// takes it, else `want` with the first free number appended
[arch(at="ARCHITECTURE_NAMES.md#c-names-locals")]
def private free_fn_name(r : CIr; want : string) : string {
    var name = want
    var n = 1
    while (key_exists(r.hoisted_names, name) || key_exists(r.file_scope_names, name) || key_exists(r.fn_all_locals, name)) {
        name = "{want}{n}"
        n++
    }
    return name
}

// the C-IR name of a parameter or local `c_name`: its own, or a free one when a block-scope
// `extern` or prototype of the function declares the name, whose references spell the
// program-wide name
[arch(at="ARCHITECTURE_NAMES.md#c-names-locals")]
def private local_name(var r : CIr; c_name : string) : string {
    return c_name if (!key_exists(r.fn_extern_names, c_name))
    let name = free_fn_name(r, c_name)
    r.fn_all_locals |> insert(name)
    return name
}

// the C-IR name of a file-scope declaration of `c_name`: `<stem>__<name>` with internal linkage,
// which a later declaration without `static` keeps (C11 6.2.2p4), else its own
[arch(at="ARCHITECTURE_NAMES.md#c-names-statics")]
def private linkage_name(var r : CIr; c_name : string; is_static : bool) : string {
    if (is_static) {
        r.linkage_names[c_name] = "{r.tu_prefix}__{c_name}"
    }
    return r.linkage_names?[c_name] ?? c_name
}

// the names the declarations of statement `s` and under it declare into `locals` (variables and a
// block prototype's parameters) and `externs` (block-scope `extern` declarations and prototypes)
def private collect_names(var p : CParser; s : int; var locals, externs : table<string>) {
    return if (s < 0)
    let n = p.ast.nodes[s]
    if (n.kind == CNode.DECL && !c_declares_typedef(p, n.a)) {
        let is_extern = has_storage(p, n.a, CTok.EXTERN)
        var id = n.b
        while (id >= 0) {
            let d = p.ast.nodes[id].a
            let name = name_of(p, d)
            let f = c_name_function(p.ast, d)
            if (f >= 0) {
                externs |> insert(name)
                var param = p.ast.nodes[f].op == 2 ? -1 : p.ast.nodes[f].b
                while (param >= 0) {
                    let pname = name_of(p, p.ast.nodes[param].b)
                    if (!empty(pname)) {
                        locals |> insert(pname)
                    }
                    param = p.ast.nodes[param].next
                }
            } else {
                locals |> insert(name)
                if (is_extern) {
                    externs |> insert(name)
                }
            }
            id = p.ast.nodes[id].next
        }
        return
    }
    if (n.kind == CNode.COMPOUND) {
        var item = n.a
        while (item >= 0) {
            collect_names(p, item, locals, externs)
            item = p.ast.nodes[item].next
        }
    } elif (n.kind == CNode.IF) {
        collect_names(p, n.b, locals, externs)
        collect_names(p, n.c, locals, externs)
    } elif (n.kind == CNode.SWITCH || n.kind == CNode.WHILE || n.kind == CNode.LABEL) {
        collect_names(p, n.b, locals, externs)
    } elif (n.kind == CNode.DO || n.kind == CNode.DEFAULT) {
        collect_names(p, n.a, locals, externs)
    } elif (n.kind == CNode.CASE) {
        collect_names(p, n.c, locals, externs)
    } elif (n.kind == CNode.FOR) {
        collect_names(p, n.a, locals, externs)
        collect_names(p, n.d, locals, externs)
    } elif (n.kind == CNode.EXPR_STMT && statement_block(p, n.a) >= 0) {
        collect_names(p, statement_block(p, n.a), locals, externs)
    }
}

// every name the unit declares at file scope, the own headers' included, and every name a
// block-scope `extern` or prototype declares anywhere: the names a hoisted static must not take
[arch(at="ARCHITECTURE_NAMES.md#c-names-locals")]
def private collect_file_scope_names(var r : CIr; var p : CParser; u : int) {
    var locals : table<string>
    var at = p.ast.nodes[u].a
    while (at >= 0) {
        let n = p.ast.nodes[at]
        if (n.kind == CNode.FUNC_DEF) {
            r.file_scope_names |> insert(name_of(p, p.ast.nodes[n.b].a))
            collect_names(p, n.d, locals, r.file_scope_names)
        } elif (n.kind == CNode.DECL && !c_declares_typedef(p, n.a)) {
            var id = n.b
            while (id >= 0) {
                r.file_scope_names |> insert(name_of(p, p.ast.nodes[id].a))
                id = p.ast.nodes[id].next
            }
        }
        at = n.next
    }
}

// the pool type init-declarator `id` declares over specifier type `base`: its declarator's, sized by
// its initializer, then a `mode` after a declarator that is a name alone; -1 with the error set
def private declared_type(var r : CIr; var p : CParser; id, base : int) : int {
    let d = p.ast.nodes[id].a
    let attrs = p.ast.nodes[id].d
    return -1 if (!c_plain_attributes(r, p, attrs, true))
    let init_node = p.ast.nodes[id].b
    let t = c_sized_by_initializer(r, p, c_declarator_type(r, p, base, d, false, init_node), d, init_node)
    if (t >= 0 && p.ast.nodes[d].kind == CNode.D_NAME) {
        return c_mode_type(r, p, attrs, t)
    }
    return t >= 0 && c_plain_attributes(r, p, attrs) ? t : -1
}

// name `sym` declared at token `tok` noted `weak` when specifier list `specs` or attribute list
// `attrs` spells it: Dumper A drops `weak` only on a name the unit defines
[arch(at="ARCHITECTURE_SUBSET.md#c-subset-attributes")]
def private note_weak(var r : CIr; p : CParser; sym, specs, attrs, tok : int) {
    for (list in fixed_array(specs, attrs)) {
        var at = list
        while (at >= 0) {
            if (p.ast.nodes[at].kind == CNode.ATTRIBUTE) {
                for (named in c_attribute_names(p, at)) {
                    if (named.name == "weak" && !key_exists(r.weak_names, sym)) {
                        r.weak_names[sym] = tok
                    }
                }
            }
            at = p.ast.nodes[at].next
        }
    }
}

// function declaration `sym` of pool type `spelled` by function declarator `f` (-1 through a
// typedef) at token `tok`, `local` in a block: its composite with the declarations of the name
// before it (`c_linked`) bound in its scope, so a block prototype converts the calls there; its
// type, then its parameters, and its declaration, unless a block declaration of a name declared
// before, which adds nothing
def private function_declaration(var r : CIr; var p : CParser; sym, spelled, f : int; local, is_static : bool; at : CirLoc; tok : int) : bool {
    let t = c_linked(r, p, spelled, sym, f, tok)
    return false if (t < 0)
    let name = c_symbol_text(p.unit, sym)
    let linked = linkage_name(r, name, is_static && !local)
    var fid = function_id(r, p, sym, t, f)
    fid.name = linked
    c_ir_bind(r, sym, fid)
    return true if (local && key_exists(r.declared, sym))
    var cd = new CirDecl(k = "func", name = linked, c_name = name, t = c_types_use(r, t), is_static = key_exists(r.linkage_names, name), loc = at)
    r.declared[sym] = true
    if (f >= 0 && !parameters(r, p, f, cd.params)) {
        delete_decl(cd)
        return false
    }
    if (empty(cd.params) && !c_has_prototype(p, f)) {
        // a declaration with no prototype lists the composite type's parameters, unnamed, as
        // Dumper A reads them off clang's type
        cd.params |> reserve(length(r.pool[r.unqualified[t]].params))
        for (q in r.pool[r.unqualified[t]].params) {
            cd.params |> push(CirParam(name = "", t = c_types_use(r, q)))
        }
    }
    r.tu.decls |> push(cd)
    return true
}

// the pool type of object declarator `id` of pool type `t`: at file scope or `extern`, the
// composite with the declarations of its name before it; a tentative definition's array of unknown
// size completed
def private object_type(var r : CIr; var p : CParser; t, id : int; local, is_extern : bool) : int {
    let sym = c_declarator_name(p.ast, p.ast.nodes[id].a)
    var typed = t
    if (!local || is_extern) {
        typed = c_linked(r, p, typed, sym, -1, p.ast.nodes[id].tok)
        return -1 if (typed < 0)
    }
    if (!local && !is_extern && p.ast.nodes[id].b < 0) {
        typed = c_tentative(r, p, typed, sym, id)
    }
    return typed
}

// a `_Static_assert` (C11 6.7.10): its condition folded, as clang checks it; Dumper A's walk adds
// nothing for it. A false one is invalid C; one the builder cannot fold yet is refused
[arch(at="ARCHITECTURE_EXPRS.md#c-exprs-constants")]
def private static_assertion(var r : CIr; var p : CParser; n : CNodeRec) : bool {
    var x = c_expr(r, p, n.a)
    return false if (x == null)
    var v = 0l
    let folded = c_fold(r, x, v)
    delete_expr(x)
    if (!folded) {
        c_refuse(r, p, n.tok, "a _Static_assert whose condition the builder cannot fold")
        return false
    } elif (v == 0l) {
        c_reject(r, p, n.tok, "a _Static_assert whose condition is 0")
        return false
    }
    return true
}

// typedef declaration `sym` (`name`) of pool type `t` at `at`: the name bound in its scope, so a
// record its type reached first sees it, then its type, its entry by the name and its declaration
def private typedef_declaration(var r : CIr; var p : CParser; sym : int; name : string; t : int; at : CirLoc) : bool {
    c_types_bind(r, sym, t)
    return false if (!c_tag_complete(r, p))
    var td = CirType(k = "typedef", name = name, to = c_types_use(r, t))
    let entry = c_types_intern_typedef(r, td)
    r.tu.decls |> push(new CirDecl(k = "typedefdecl", name = name, c_name = name, t = entry, loc = at))
    return true
}

// the `dims` of declarator `d` of pool type `t` (`c_dims`), each enumerator's enum its table index
def private table_dims(var r : CIr; var p : CParser; d, t : int) : array<CirDim> {
    var dims <- c_dims(r, p, d, t)
    for (dim in dims) {
        if (!empty(dim.item)) {
            dim.enum_t = c_types_use(r, dim.enum_t)
        }
    }
    return <- dims
}

// variable `g`, declared by `sym`, where it goes: a file-scope one merged into an earlier of its
// name, a block's `static` hoisted with a `null` in its place, a block's `extern` declared at file
// scope once with a `null` in its place, any other local a `decl` statement into `into`
def private variable(var r : CIr; var g : CirDecl?; sym : int; global, is_static, is_extern, no_init : bool; var into : array<CirStmt?>) {
    let at = g.loc
    if (global) {
        g.is_extern = is_extern && no_init
        push_global(r, g)
    } elif (is_static) {
        g.is_static = true
        g.from_func = r.fn_name
        r.tu.decls |> push(g)
        into |> push(new CirStmt(s = "null", loc = at))
    } elif (is_extern) {
        if (!key_exists(r.declared, sym)) {
            g.is_extern = true
            r.tu.decls |> push(g)
        } else {
            delete_decl(g)
        }
        into |> push(new CirStmt(s = "null", loc = at))
    } else {
        var st = new CirStmt(s = "decl", name = g.name, t = g.t, init = g.init, loc = at)
        st.dims <- g.dims
        g.init = null
        delete_decl(g)
        into |> push(st)
    }
}

// the struct, union and enum definitions among declaration `decl`'s specifiers, walked
// (`c_tag_definitions`), each named as `c_tag_names` named it, and an own header's record anchored
// at the declaration's place
def private declaration_tags(var r : CIr; var p : CParser; decl : int) : bool {
    let n = p.ast.nodes[decl]
    let first = n.b >= 0 ? p.ast.nodes[n.b].a : -1
    r.anchor_at = loc_of(p, first >= 0 ? name_tok(p, first, n.tok) : n.tok)
    return c_tag_definitions(r, p, n.a, false)
}

// the C-IR name of object `name` declared `global`ly or in a block: a file-scope or `extern` one's
// linkage name, a hoisted static's `<fn>_<name>` (recorded as hoisted), a local's own
def private object_name(var r : CIr; name : string; global, is_static, is_extern : bool) : string {
    if (global || (is_extern && !is_static)) {
        return linkage_name(r, name, global && is_static)
    } elif (!is_static) {
        return local_name(r, name)
    }
    let hoisted = free_fn_name(r, "{r.fn_name}_{name}")
    r.hoisted_names |> insert(hoisted)
    return hoisted
}

// declaration node `decl` in Dumper A's order, per init-declarator its type, then its
// initializer's or its parameters' types; `fn` the function holding a block declaration ("" at file
// scope), `into` the block's statements: a local its `decl`, a hoisted `static` and an `extern` a
// `null`, a block function declaration none
[arch(at="ARCHITECTURE_TYPES.md#c-types-order")]
def private declaration(var r : CIr; var p : CParser; decl : int; fn : string; var into : array<CirStmt?>) : bool {
    let n = p.ast.nodes[decl]
    return static_assertion(r, p, n) if (n.kind == CNode.STATIC_ASSERT)
    return true if (n.kind != CNode.DECL)
    let typedef_decl = c_declares_typedef(p, n.a)
    let is_static = has_storage(p, n.a, CTok.STATIC)
    let is_extern = has_storage(p, n.a, CTok.EXTERN)
    return false if (!declaration_tags(r, p, decl))
    if (n.b < 0) {
        return c_specifier_type(r, p, n.a) >= 0
    }
    // the specifiers name one type for every declarator, resolved before any of them binds a name
    let base = c_specifier_type(r, p, n.a)
    return false if (base < 0)
    let local = !empty(fn)
    var next = n.b
    while (next >= 0) {
        let id = next
        next = p.ast.nodes[id].next
        let d = p.ast.nodes[id].a
        let sym = c_declarator_name(p.ast, d)
        let name = c_symbol_text(p.unit, sym)
        let f = c_name_function(p.ast, d)
        let at = loc_of(p, name_tok(p, d, p.ast.nodes[id].tok))
        note_weak(r, p, sym, n.a, p.ast.nodes[id].d, name_tok(p, d, p.ast.nodes[id].tok))
        if (!typedef_decl && !is_extern && (empty(fn) || is_static) && f < 0 || p.ast.nodes[id].b >= 0) {
            r.defined_names[sym] = true
        }
        var t = declared_type(r, p, id, base)
        return false if (t < 0)
        r.anchor_at = at
        if (typedef_decl) {
            return false if (!typedef_declaration(r, p, sym, name, t, at))
            continue
        }
        return false if (!c_tag_complete(r, p))
        if (r.pool[t].k == "func") {
            return false if (!function_declaration(r, p, sym, t, f, local, is_static, at, p.ast.nodes[id].tok))
            continue
        }
        t = object_type(r, p, t, id, local, is_extern)
        return false if (t < 0)
        let ti = c_types_use(r, t)
        let global = empty(fn)
        let linked = object_name(r, name, global, is_static, is_extern)
        c_ir_bind(r, sym, CId(t = t, old_style = -1, name = linked, automatic = !global && !is_static && !is_extern))
        let init = p.ast.nodes[id].b
        r.init_static = global || is_static
        var built = init >= 0 ? c_initializer(r, p, init, t) : null
        r.init_static = false
        if (built != null && (global || is_static) && !c_static_initializer(r, p, built, p.ast.nodes[init].tok, global)) {
            delete_expr(built)
            return false
        }
        var value = init >= 0 ? used(r, p, built) : null
        return false if (init >= 0 && value == null)
        var dims <- table_dims(r, p, d, t)
        var g = new CirDecl(k = "global", name = linked, c_name = name, t = ti, is_static = key_exists(r.linkage_names, name), init = value, loc = at)
        g.dims <- dims
        variable(r, g, sym, global, is_static, is_extern, init < 0, into)
        if (empty(fn) || is_extern) {
            r.declared[sym] = true
        }
    }
    return true
}

// GNU case range `case lo ... hi:` of node `n` at `at` into `into`: both ends folded as a single
// label's are (`c_case_value`) and held in the promoted controlling type, as clang converts them;
// an empty range, `lo` above `hi` there, labels nothing and adds no marker
[arch(at="ARCHITECTURE_SUBSET.md#c-subset-case-range")]
def private case_range(var r : CIr; var p : CParser; n : CNodeRec; at : CirLoc; var into : array<CirStmt?>) : bool {
    var lo, hi : int64
    return false if (!c_case_value(r, p, n.a, n.tok, lo) || !c_case_value(r, p, n.b, n.tok, hi))
    lo = c_held_in(r, r.switch_t, lo)
    hi = c_held_in(r, r.switch_t, hi)
    let wide_unsigned = !r.pool[r.switch_t].is_signed && r.pool[r.switch_t].w >= 64
    let empty_range = wide_unsigned ? uint64(lo) > uint64(hi) : lo > hi
    if (!empty_range) {
        into |> push(new CirStmt(s = "case", v = lo, hi = hi, is_range = true, is_char = is_char_constant(p, n.a) && is_char_constant(p, n.b), loc = at))
    }
    if (n.c < 0) {
        into |> push(new CirStmt(s = "null", loc = at))
    }
    return true
}

// statement node `s` as C-IR statements into `into`, in Dumper A's order: a block's declarations
// as their statements, `case`, `default` and a label as a marker before the statement under them,
// every expression with its conversions; false with the error set at a statement not built yet
[arch(at="ARCHITECTURE_TYPES.md#c-types-order")]
def private statement(var r : CIr; var p : CParser; s : int; fn : string; var into : array<CirStmt?>) : bool {
    let n = p.ast.nodes[s]
    let at = loc_of(p, n.tok)
    r.anchor_at = at
    if (n.kind == CNode.DECL) {
        return declaration(r, p, s, fn, into)
    } elif (n.kind == CNode.STATIC_ASSERT) {
        return static_assertion(r, p, n)
    } elif (n.kind == CNode.LABEL || n.kind == CNode.CASE || n.kind == CNode.DEFAULT) {
        if (n.kind == CNode.LABEL) {
            into |> push(new CirStmt(s = "label", label_name = c_symbol_text(p.unit, n.a), loc = at))
        } elif (n.kind == CNode.DEFAULT) {
            into |> push(new CirStmt(s = "default", loc = at))
        } else {
            var v = 0l
            if (n.b >= 0) {
                return case_range(r, p, n, at, into) && (n.c < 0 || statement(r, p, n.c, fn, into))
            }
            return false if (!c_case_value(r, p, n.a, n.tok, v))
            if (key_exists(r.cases, v)) {
                c_reject(r, p, n.tok, "a duplicate case value")
                return false
            }
            r.cases[v] = true
            into |> push(new CirStmt(s = "case", v = v, is_char = is_char_constant(p, n.a), loc = at))
        }
        let sub = n.kind == CNode.LABEL ? n.b : n.kind == CNode.DEFAULT ? n.a : n.c
        if (sub < 0) {
            into |> push(new CirStmt(s = "null", loc = at))
            return true
        }
        return statement(r, p, sub, fn, into)
    }
    if (n.kind == CNode.EXPR_STMT && statement_block(p, n.a) >= 0) {
        let built = statement(r, p, statement_block(p, n.a), fn, into)
        if (built) {
            into[length(into) - 1].loc = at
        }
        return built
    }
    var st = new CirStmt(loc = at)
    let ok = n.kind == CNode.IF || n.kind == CNode.WHILE || n.kind == CNode.DO || n.kind == CNode.SWITCH || n.kind == CNode.FOR ? branch(r, p, n, fn, st) : simple(r, p, n, fn, st)
    if (!ok) {
        delete_stmt(st)
        return false
    }
    into |> push(st)
    return true
}

// a statement with no statement under it, or a block, into `st`: its kind and expressions
// whether asm statement `n` is a compiler barrier, an empty template with no operand and at most
// clobbers, which orders nothing a das run observes and is the empty statement, as Dumper A writes
// it; false with the error set for any other asm, machine code or a register binding
[arch(at="ARCHITECTURE_SUBSET.md#c-subset-asm")]
def private asm_barrier(var r : CIr; var p : CParser; n : CNodeRec) : bool {
    let lit = p.ast.nodes[n.a]
    for (t in range(lit.a, lit.a + lit.b)) {
        if (c_spelling(p.unit, t) != "\"\"") {
            c_refuse(r, p, n.tok, "inline asm with template text", ", which is machine code")
            return false
        }
    }
    if (n.b >= 0 || n.c >= 0) {
        c_refuse(r, p, n.tok, "inline asm with operands", ", which bind registers")
        return false
    }
    return true
}

def private simple(var r : CIr; var p : CParser; n : CNodeRec; fn : string; var st : CirStmt?) : bool {
    var ok = true
    if (n.kind == CNode.COMPOUND) {
        st.s = "compound"
        c_types_scope_open(r)
        c_ir_open(r)
        var item = n.a
        while (ok && item >= 0) {
            ok = statement(r, p, item, fn, st.body)
            item = p.ast.nodes[item].next
        }
        c_ir_close(r)
        c_types_scope_close(r)
    } elif (n.kind == CNode.EXPR_STMT) {
        st.s = "expr"
        st.e = used(r, p, value_of(r, p, n.a))
        ok = st.e != null
    } elif (n.kind == CNode.NULL_STMT) {
        st.s = "null"
    } elif (n.kind == CNode.ASM) {
        ok = asm_barrier(r, p, n)
        st.s = "null"
    } elif (n.kind == CNode.GOTO) {
        st.s = "goto"
        st.label_name = c_symbol_text(p.unit, n.a)
    } elif (n.kind == CNode.CONTINUE || n.kind == CNode.BREAK) {
        st.s = n.kind == CNode.CONTINUE ? "continue" : "break"
    } elif (n.kind == CNode.RETURN) {
        st.s = "return"
        let void_fn = r.pool[r.ret].k == "void"
        if (n.a >= 0) {
            var e = c_expr(r, p, n.a)
            if (e != null && void_fn && r.pool[r.unqualified[e.t]].k != "void") {
                c_reject(r, p, n.tok, "a value returned from a void function")
                delete_expr(e)
                return false
            }
            st.e = e == null ? null : used(r, p, void_fn ? c_rvalue(r, e) : c_assigned(r, p, e, r.ret, p.ast.nodes[n.a].tok))
            ok = st.e != null
        } elif (!void_fn) {
            c_reject(r, p, n.tok, "a return with no value from a function that returns one")
            ok = false
        }
    } else {
        c_refuse(r, p, n.tok, "this statement")
        ok = false
    }
    return ok
}

// an `if`, `while`, `do`, `switch` or `for` into `st`, its expressions where Dumper A dumps them
// among the statements under it
def private branch(var r : CIr; var p : CParser; n : CNodeRec; fn : string; var st : CirStmt?) : bool {
    var ok = true
    if (n.kind == CNode.IF) {
        st.s = "if"
        st.cond = used(r, p, value_of(r, p, n.a))
        ok = st.cond != null && one(r, p, n.b, fn, st.then_s) && (n.c < 0 || one(r, p, n.c, fn, st.else_s))
    } elif (n.kind == CNode.WHILE) {
        st.s = "while"
        st.cond = used(r, p, value_of(r, p, n.a))
        ok = st.cond != null && one(r, p, n.b, fn, st.body_s)
    } elif (n.kind == CNode.DO) {
        st.s = "do"
        ok = one(r, p, n.a, fn, st.body_s)
        st.cond = ok ? used(r, p, value_of(r, p, n.b)) : null
        ok = ok && st.cond != null
    } elif (n.kind == CNode.SWITCH) {
        st.s = "switch"
        var c = c_expr(r, p, n.a)
        var promoted = c == null ? null : c_promote(r, c)
        let controlling = promoted == null ? -1 : r.unqualified[promoted.t]
        st.cond = promoted == null ? null : used(r, p, promoted)
        var outer <- r.cases
        let outer_t = r.switch_t
        r.switch_t = controlling
        ok = st.cond != null && one(r, p, n.b, fn, st.body_s)
        r.switch_t = outer_t
        r.cases <- outer
    } else {
        st.s = "for"
        c_types_scope_open(r)
        c_ir_open(r)
        if (n.a >= 0 && p.ast.nodes[n.a].kind == CNode.DECL) {
            st.init_s = new CirStmt(s = "compound", loc = loc_of(p, p.ast.nodes[n.a].tok))
            ok = declaration(r, p, n.a, fn, st.init_s.body)
        } elif (n.a >= 0) {
            var e = used(r, p, value_of(r, p, n.a))
            ok = e != null
            st.init_s = new CirStmt(s = "expr", e = e, loc = loc_of(p, p.ast.nodes[n.a].tok))
        }
        st.cond = ok && n.b >= 0 ? used(r, p, value_of(r, p, n.b)) : null
        ok = ok && (n.b < 0 || st.cond != null)
        st.inc = ok && n.c >= 0 ? used(r, p, value_of(r, p, n.c)) : null
        ok = ok && (n.c < 0 || st.inc != null) && one(r, p, n.d, fn, st.body_s)
        c_ir_close(r)
        c_types_scope_close(r)
    }
    return ok
}

// the compound statement of GNU statement expression `e` evaluated for its effect alone, through
// parentheses, `__extension__` and a cast to `void`, as Dumper A takes it for its block; -1 for any
// other expression
def private statement_block(var p : CParser; e : int) : int {
    let n = p.ast.nodes[e]
    if (n.kind == CNode.STMT_EXPR) {
        return n.a
    } elif (n.kind == CNode.PAREN || n.kind == CNode.EXTENSION) {
        return statement_block(p, n.a)
    } elif (n.kind == CNode.CAST && is_void_name(p, n.a)) {
        return statement_block(p, n.b)
    }
    return -1
}

// whether type-name node `t` is `void`: the keyword alone (qualifiers aside), no declarator
def private is_void_name(p : CParser; t : int) : bool {
    var found = false
    var at = p.ast.nodes[t].a
    while (at >= 0) {
        let n = p.ast.nodes[at]
        found ||= n.kind == CNode.SPEC_KEYWORD && n.op == int(CTok.VOID)
        return false if (n.kind != CNode.SPEC_KEYWORD || (n.op != int(CTok.VOID) && (n.op < int(CTok.CONST) || n.op > int(CTok.RESTRICT))))
        at = n.next
    }
    return found && p.ast.nodes[t].b < 0
}

// statement node `s` as one C-IR statement into `slot`: a run of markers or declarations becomes
// a compound statement holding them
def private one(var r : CIr; var p : CParser; s : int; fn : string; var slot : CirStmt?&) : bool {
    var body : array<CirStmt?>
    let ok = statement(r, p, s, fn, body)
    if (length(body) == 1) {
        slot = body[0]
        body |> clear()
    } elif (ok) {
        slot = new CirStmt(s = "compound", loc = loc_of(p, p.ast.nodes[s].tok))
        slot.body <- body
    }
    return ok
}

// the declaration in list `old` that has declarator `d`
def private declaration_of(p : CParser; old, d : int) : int {
    var at = old
    while (at >= 0) {
        var id = p.ast.nodes[at].b
        while (id >= 0) {
            return at if (p.ast.nodes[id].a == d)
            id = p.ast.nodes[id].next
        }
        at = p.ast.nodes[at].next
    }
    return -1
}

// the names definition `name` of function declarator `f`, body `body` and old-style parameter
// names `old_names` keeps while it is read (`ARCHITECTURE_NAMES.md` section 47)
[arch(at="ARCHITECTURE_NAMES.md#c-names-locals")]
def private function_names(var r : CIr; var p : CParser; name : string; f, body : int; old_names : array<string>) {
    r.fn_name = name
    r.fn_all_locals |> clear()
    r.fn_extern_names |> clear()
    for (pname in old_names) {
        r.fn_all_locals |> insert(pname)
    }
    var param = p.ast.nodes[f].op == 2 || c_is_void_list(r, p, p.ast.nodes[f].b) ? -1 : p.ast.nodes[f].b
    while (param >= 0) {
        r.fn_all_locals |> insert(name_of(p, p.ast.nodes[param].b))
        param = p.ast.nodes[param].next
    }
    collect_names(p, body, r.fn_all_locals, r.fn_extern_names)
}

// function definition `def_node`: its type (an old-style one's parameters promoted, as clang types
// it), each parameter, then its body; the function's declaration after the statics its body hoists
// the parameters of old-style definition `n`'s function declarator `f`, each typed by its
// declaration list, into `typed` and `names`, and the promoted types its calls convert by into
// `r.old_style`; false with the error set for one the builder does not type
def private old_style_types(var r : CIr; var p : CParser; n : CNodeRec; f : int; var typed : array<int>; var names : array<string>) : bool {
    var param = p.ast.nodes[f].b
    while (param >= 0) {
        let typing = p.ast.nodes[param].b
        let old = declaration_of(p, n.c, typing)
        var typed_by = p.ast.nodes[old].b
        while (typed_by >= 0 && p.ast.nodes[typed_by].a != typing) {
            typed_by = p.ast.nodes[typed_by].next
        }
        return false if (!c_plain_attributes(r, p, p.ast.nodes[typed_by].d))
        let pt = c_parameter_type(r, p, p.ast.nodes[old].a, typing)
        return false if (pt < 0)
        typed |> push(pt)
        names |> push(c_symbol_text(p.unit, p.ast.nodes[param].a))
        r.old_style |> push(c_promoted(r, pt))
        param = p.ast.nodes[param].next
    }
    return true
}

[arch(at="ARCHITECTURE_TYPES.md#c-types-order")]
def private definition(var r : CIr; var p : CParser; def_node : int) : bool {
    let n = p.ast.nodes[def_node]
    let d = p.ast.nodes[n.b].a
    let f = c_name_function(p.ast, d)
    let sym = c_declarator_name(p.ast, d)
    note_weak(r, p, sym, n.a, p.ast.nodes[n.b].d, name_tok(p, d, n.tok))
    r.defined_names[sym] = true
    let name = c_symbol_text(p.unit, sym)
    let old_style = p.ast.nodes[f].op == 2
    var typed : array<int>
    var names : array<string>
    return false if (old_style && !old_style_types(r, p, n, f, typed, names))
    r.anchor_at = loc_of(p, name_tok(p, d, n.tok))
    return false if (!c_tag_definitions(r, p, n.a, false))
    let spelled = c_declarator_type(r, p, c_specifier_type(r, p, n.a), d, false)
    r.old_style |> clear()
    return false if (!c_tag_complete(r, p))
    let t = spelled < 0 ? spelled : c_linked(r, p, spelled, sym, f, p.ast.nodes[n.b].tok)
    let ti = c_types_use(r, t)
    return false if (ti < 0)
    let linked = linkage_name(r, name, has_storage(p, n.a, CTok.STATIC))
    var cd = new CirDecl(k = "func", name = linked, c_name = name, t = ti, is_static = key_exists(r.linkage_names, name), loc = loc_of(p, name_tok(p, d, n.tok)))
    r.declared[sym] = true
    if (old_style) {
        var none : array<int>
        c_ir_bind(r, sym, CId(t = c_function(r, r.pool[t].ret, none, false), is_function = true, old_style = t, name = linked))
    } else {
        var fid = function_id(r, p, sym, t, f)
        fid.name = linked
        c_ir_bind(r, sym, fid)
    }
    function_names(r, p, name, f, n.d, names)
    c_ir_open(r)
    c_types_scope_open(r)
    var ok = true
    if (old_style) {
        cd.params |> reserve(length(typed))
        return false if (!c_tag_complete(r, p))
        for (pt, pname in typed, names) {
            let local = local_name(r, pname)
            cd.params |> push(CirParam(name = local, t = c_types_use(r, pt)))
            c_ir_bind(r, c_symbol(p.unit, pname), CId(t = pt, old_style = -1, name = local, automatic = true))
        }
    } else {
        ok = parameters(r, p, f, cd.params, true)
        var param = c_is_void_list(r, p, p.ast.nodes[f].b) ? -1 : p.ast.nodes[f].b
        var at = 0
        while (ok && param >= 0) {
            let psym = c_declarator_name(p.ast, p.ast.nodes[param].b)
            if (psym >= 0) {
                c_ir_bind(r, psym, CId(t = c_param_type(r, p, param), old_style = -1, name = cd.params[at].name, automatic = true))
            }
            at++
            param = p.ast.nodes[param].next
        }
    }
    r.ret = r.unqualified[r.pool[t].ret]
    var body : array<CirStmt?>
    ok = ok && statement(r, p, n.d, name, body)
    c_types_scope_close(r)
    c_ir_close(r)
    if (ok) {
        cd.body = body[0]
        r.tu.decls |> push(cd)
    } else {
        delete_decl(cd)
    }
    return ok
}

// whether external declaration `decl` stands in a file under the own libc headers' folder
def private in_library(r : CIr; p : CParser; decl : int) : bool {
    return false if (empty(r.library_dir))
    let file = c_file_name(p.unit, p.unit.toks[p.ast.nodes[decl].tok].file)
    return starts_with(file, r.library_dir)
}

// the tags specifier list `specs` defines, whose definition the builder refused, each to the
// refusal, which a use in the unit reports
def private library_tags_untyped(var r : CIr; p : CParser; specs : int) {
    var at = specs
    while (at >= 0) {
        let n = p.ast.nodes[at]
        if ((n.kind == CNode.SPEC_RECORD || n.kind == CNode.SPEC_ENUM) && n.b == 1 && n.a >= 0 && !key_exists(r.tag_built, at)) {
            r.untyped_tags[n.a] = r.err
            r.tags |> erase(n.a)
        }
        at = n.next
    }
}

// a library declaration, which adds no type and no declaration: its typedef names bound to their
// pool types, its functions and variables to theirs, each one the builder does not type to the
// refusal, which a use in the unit reports; its function names declared
[arch(at="ARCHITECTURE_TYPES.md#c-types-library")]
def private library_declaration(var r : CIr; var p : CParser; decl : int) {
    let n = p.ast.nodes[decl]
    let is_def = n.kind == CNode.FUNC_DEF
    return if (n.kind != CNode.DECL && !is_def)
    let typedef_decl = !is_def && c_declares_typedef(p, n.a)
    if (!c_tag_definitions(r, p, n.a, true)) {
        library_tags_untyped(r, p, n.a)
        r.err = ""
    }
    var id = n.b
    while (id >= 0) {
        let d = p.ast.nodes[id].a
        let sym = c_declarator_name(p.ast, d)
        let t = c_plain_attributes(r, p, p.ast.nodes[id].d) ? c_declarator_type(r, p, c_specifier_type(r, p, n.a), d, false) : -1
        if (t < 0) {
            if (typedef_decl) {
                r.untyped[sym] = r.err
            } else {
                r.ids |> erase(sym)
            }
            r.err = ""
        } elif (typedef_decl) {
            c_types_bind(r, sym, t)
        } elif (r.pool[t].k == "func") {
            r.declared[sym] = true
            r.library_functions[sym] = int2(decl, is_def ? n.b : id)
            var fid = function_id(r, p, sym, t, c_name_function(p.ast, d))
            fid.name = name_of(p, d)
            c_ir_bind(r, sym, fid)
        } else {
            r.declared[sym] = true
            c_ir_bind(r, sym, CId(t = t, old_style = -1, name = name_of(p, d)))
        }
        id = is_def ? -1 : p.ast.nodes[id].next
    }
}

//! The C-IR of unit node `u`, which `c_unit` built, into `r.tu`: its declarations, bodies and
//! expressions, and the type table in the order Dumper A's walk interns it; false with the error
//! set at the first construct not built yet. Under the msvc dialect `size_t`, which clang declares
//! there before the unit, is `unsigned long long`.
[arch(at="ARCHITECTURE_TYPES.md#c-types-order")]
def c_ir_unit(var r : CIr; var p : CParser; u : int) : bool {
    if (is_msvc(r.tu.target)) {
        c_types_bind(r, c_symbol(p.unit, "size_t"), c_builtin(r, "unsigned long long"))
    }
    let slash = max(rfind(c_file_name(p.unit, 0), "/"), rfind(c_file_name(p.unit, 0), "\\"))
    r.tu.cir = CIR_VERSION
    r.tu.producer = C_IR_PRODUCER
    r.tu.tu = slice(c_file_name(p.unit, 0), slash + 1)
    r.tu_prefix = ident_of(slice(r.tu.tu, 0, max(find(r.tu.tu, "."), 0)))
    collect_file_scope_names(r, p, u)
    c_tag_lookahead(r, p, u)
    c_tag_names(r, p, u)
    var none : array<CirStmt?>
    var at = p.ast.nodes[u].a
    r.unit_items = at
    while (empty(r.err) && at >= 0) {
        if (in_library(r, p, at)) {
            library_declaration(r, p, at)
        } elif (p.ast.nodes[at].kind == CNode.FUNC_DEF) {
            definition(r, p, at)
        } else {
            declaration(r, p, at, "", none)
        }
        at = p.ast.nodes[at].next
    }
    for (sym, tok in keys(r.weak_names), values(r.weak_names)) {
        if (empty(r.err) && !key_exists(r.defined_names, sym)) {
            c_refuse(r, p, tok, "`weak` on '{c_symbol_text(p.unit, sym)}', which the unit never defines,")
        }
    }
    return empty(r.err)
}
