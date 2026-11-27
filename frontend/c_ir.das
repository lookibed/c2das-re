options gen2
options indenting = 4

module c_ir public

require strings
require daslib/strings_boost
require daslib/cmp
require math
require c_exprs public
require c_records public

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
    r.fold = @@c_fold_node
    r.tag_type = @@c_tag_type
    r.tu_prefix = ""
    r.linkage_names |> clear()
    r.file_scope_names |> clear()
    r.hoisted_names |> clear()
    r.fn_all_locals |> clear()
    r.fn_extern_names |> clear()
    r.fn_name = ""
}

// the place of token `tok` in the C-IR: where the unit's text puts it, after its line markers
[arch(at="ARCHITECTURE_NAMES.md#c-ir-places")]
def private loc_of(var p : CParser; tok : int) : CirLoc {
    let t = p.unit.toks[tok]
    return CirLoc(file = c_file_name(p.unit, t.file), line = t.line, col = t.col)
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

// the initializer node `init` of an object of pool type `t`, converted as C11 6.7.9 says: a
// character array's string literal typed as the array, a list's items each to its element type at
// its position, in the order of the positions, a later item for a position replacing an earlier
// one (clang's semantic form), a scalar's value (braced or not) by assignment
[arch(at="ARCHITECTURE_EXPRS.md#c-exprs-slots")]
def private initializer(var r : CIr; var p : CParser; init, t : int) : CirExpr? {
    let n = p.ast.nodes[init]
    let k = r.pool[t].k
    let elem = k == "array" ? r.pool[t].elem : -1
    let char_array = elem >= 0 && r.pool[elem].k == "int" && r.pool[elem].w == 8
    if (n.kind == CNode.STRING && char_array) {
        var s = c_string_literal(r, p, n.a, n.b)
        if (s != null) {
            s.t = t
        }
        return s
    } elif (n.kind != CNode.INIT_LIST) {
        var x = c_expr(r, p, init)
        return x == null ? null : c_assigned(r, x, t)
    } elif (k == "struct" || k == "union") {
        c_refuse(r, p, n.tok, "an initializer list of a struct or union")
        return null
    } elif (k != "array") {
        let item = n.a
        if (item < 0 || p.ast.nodes[item].next >= 0 || p.ast.nodes[item].a >= 0) {
            c_refuse(r, p, n.tok, "a braced scalar initializer of other than one value")
            return null
        }
        return initializer(r, p, p.ast.nodes[item].b, t)
    }
    let first = n.a
    if (char_array && first >= 0 && p.ast.nodes[first].next < 0 && p.ast.nodes[first].a < 0 && p.ast.nodes[p.ast.nodes[first].b].kind == CNode.STRING) {
        return initializer(r, p, p.ast.nodes[first].b, t)
    }
    var x = new CirExpr(e = "init_list", t = t)
    var pos = 0
    var item = first
    while (item >= 0) {
        let it = p.ast.nodes[item]
        if (it.a >= 0) {
            var v = 0l
            if (p.ast.nodes[it.a].kind != CNode.DESIG_INDEX || p.ast.nodes[it.a].next >= 0 || !c_fold_node(r, p, p.ast.nodes[it.a].a, v)) {
                c_refuse(r, p, it.tok, "this designator")
                return null
            }
            pos = int(v)
        }
        let value = p.ast.nodes[it.b]
        if (r.pool[elem].k == "array" && value.kind != CNode.INIT_LIST && value.kind != CNode.STRING) {
            c_refuse(r, p, it.tok, "an initializer of an array of arrays with elided braces")
            return null
        }
        var v = initializer(r, p, it.b, elem)
        return null if (v == null)
        var placed = false
        for (old in x.init_items) {
            if (old.pos == pos) {
                delete_expr(old.v)
                old.v = v
                placed = true
            }
        }
        if (!placed) {
            x.init_items |> push(CirInitItem(pos = pos, v = v))
        }
        pos++
        item = it.next
    }
    sort(x.init_items, cmp_by(_.pos))
    return x
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
    return sym < 0 ? "" : pp_symbol_text(p.unit.lx, sym)
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
    return true if (p.ast.nodes[f].op == 2 || c_is_void_list(p, p.ast.nodes[f].b))
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

// function declaration `sym` of pool type `t` by function declarator `f` (-1 through a typedef),
// `local` in a block: bound in its scope; its type, then its parameters, and its declaration,
// unless a block declaration of a name declared before, which adds nothing
def private function_declaration(var r : CIr; var p : CParser; sym, t, f : int; local, is_static : bool; at : CirLoc) : bool {
    let name = pp_symbol_text(p.unit.lx, sym)
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
    r.tu.decls |> push(cd)
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
// (`c_tag_definitions`): one with no tag that a typedef declares by its name alone is named by it,
// and an own header's record is anchored at the declaration's place
def private declaration_tags(var r : CIr; var p : CParser; decl : int; typedef_decl : bool) : bool {
    let n = p.ast.nodes[decl]
    let first = n.b >= 0 ? p.ast.nodes[n.b].a : -1
    let hint = typedef_decl && first >= 0 && p.ast.nodes[first].kind == CNode.D_NAME ? name_of(p, first) : ""
    r.anchor_at = loc_of(p, first >= 0 ? name_tok(p, first, n.tok) : n.tok)
    return c_tag_definitions(r, p, n.a, hint, false)
}

// typedef name `sym` of pool type `t`, declared at `at`: bound, so a record its type reached first
// sees it, then its type and its `typedef` entry interned and its declaration written
def private typedef_declaration(var r : CIr; var p : CParser; sym, t : int; at : CirLoc) : bool {
    let name = pp_symbol_text(p.unit.lx, sym)
    c_types_bind(r, sym, t)
    return false if (!c_tag_complete(r, p))
    var td = CirType(k = "typedef", name = name, to = c_types_use(r, t))
    let entry = c_types_intern_typedef(r, td)
    r.tu.decls |> push(new CirDecl(k = "typedefdecl", name = name, c_name = name, t = entry, loc = at))
    return true
}

// declaration node `decl` in Dumper A's order, per init-declarator its type, then its
// initializer's or its parameters' types; `fn` the function holding a block declaration ("" at file
// scope), `into` the block's statements: a local its `decl`, a hoisted `static` and an `extern` a
// `null`, a block function declaration none
[arch(at="ARCHITECTURE_TYPES.md#c-types-order")]
def private declaration(var r : CIr; var p : CParser; decl : int; fn : string; var into : array<CirStmt?>) : bool {
    let n = p.ast.nodes[decl]
    return true if (n.kind != CNode.DECL)
    let typedef_decl = c_declares_typedef(p, n.a)
    let is_static = has_storage(p, n.a, CTok.STATIC)
    let is_extern = has_storage(p, n.a, CTok.EXTERN)
    return false if (!declaration_tags(r, p, decl, typedef_decl))
    if (n.b < 0) {
        return c_specifier_type(r, p, n.a) >= 0
    }
    var next = n.b
    while (next >= 0) {
        let id = next
        next = p.ast.nodes[id].next
        let d = p.ast.nodes[id].a
        let sym = c_declarator_name(p.ast, d)
        let name = pp_symbol_text(p.unit.lx, sym)
        let f = c_name_function(p.ast, d)
        let at = loc_of(p, name_tok(p, d, p.ast.nodes[id].tok))
        return false if (!c_plain_attributes(r, p, p.ast.nodes[id].d))
        let base = c_specifier_type(r, p, n.a)
        let t = c_declarator_type(r, p, base, d, false, p.ast.nodes[id].b)
        return false if (t < 0)
        r.anchor_at = at
        if (typedef_decl) {
            return false if (!typedef_declaration(r, p, sym, t, at))
            continue
        }
        return false if (!c_tag_complete(r, p))
        if (r.pool[t].k == "func") {
            return false if (!function_declaration(r, p, sym, t, f, !empty(fn), is_static, at))
            continue
        }
        let ti = c_types_use(r, t)
        let global = empty(fn)
        let linked = global ? linkage_name(r, name, is_static) : is_static ? free_fn_name(r, "{r.fn_name}_{name}") : is_extern ? linkage_name(r, name, false) : local_name(r, name)
        if (!global && is_static) {
            r.hoisted_names |> insert(linked)
        }
        c_ir_bind(r, sym, CId(t = t, old_style = -1, name = linked))
        let init = p.ast.nodes[id].b
        var value = init >= 0 ? used(r, p, initializer(r, p, init, t)) : null
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
        return true
    } elif (n.kind == CNode.LABEL || n.kind == CNode.CASE || n.kind == CNode.DEFAULT) {
        if (n.kind == CNode.LABEL) {
            into |> push(new CirStmt(s = "label", label_name = pp_symbol_text(p.unit.lx, n.a), loc = at))
        } elif (n.kind == CNode.DEFAULT) {
            into |> push(new CirStmt(s = "default", loc = at))
        } else {
            var v = 0l
            if (n.b >= 0 || !c_fold_node(r, p, n.a, v)) {
                c_refuse(r, p, n.tok, "this case label")
                return false
            }
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
    } elif (n.kind == CNode.GOTO) {
        st.s = "goto"
        st.label_name = pp_symbol_text(p.unit.lx, n.a)
    } elif (n.kind == CNode.CONTINUE || n.kind == CNode.BREAK) {
        st.s = n.kind == CNode.CONTINUE ? "continue" : "break"
    } elif (n.kind == CNode.RETURN) {
        st.s = "return"
        if (n.a >= 0) {
            var e = c_expr(r, p, n.a)
            st.e = e == null ? null : used(r, p, r.pool[r.ret].k == "void" ? c_rvalue(r, e) : c_assigned(r, e, r.ret))
            ok = st.e != null
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
        st.cond = c == null ? null : used(r, p, c_promote(r, c))
        ok = st.cond != null && one(r, p, n.b, fn, st.body_s)
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
// names `old_names` keeps while it is read (`ARCHITECTURE_NAMES.md` section 38)
[arch(at="ARCHITECTURE_NAMES.md#c-names-locals")]
def private function_names(var r : CIr; var p : CParser; name : string; f, body : int; old_names : array<string>) {
    r.fn_name = name
    r.fn_all_locals |> clear()
    r.fn_extern_names |> clear()
    for (pname in old_names) {
        r.fn_all_locals |> insert(pname)
    }
    var param = p.ast.nodes[f].op == 2 || c_is_void_list(p, p.ast.nodes[f].b) ? -1 : p.ast.nodes[f].b
    while (param >= 0) {
        r.fn_all_locals |> insert(name_of(p, p.ast.nodes[param].b))
        param = p.ast.nodes[param].next
    }
    collect_names(p, body, r.fn_all_locals, r.fn_extern_names)
}

// function definition `def_node`: its type (an old-style one's parameters promoted, as clang types
// it), each parameter, then its body; the function's declaration after the statics its body hoists
[arch(at="ARCHITECTURE_TYPES.md#c-types-order")]
def private definition(var r : CIr; var p : CParser; def_node : int) : bool {
    let n = p.ast.nodes[def_node]
    let d = p.ast.nodes[n.b].a
    let f = c_name_function(p.ast, d)
    let sym = c_declarator_name(p.ast, d)
    let name = pp_symbol_text(p.unit.lx, sym)
    let old_style = p.ast.nodes[f].op == 2
    var typed : array<int>
    var names : array<string>
    if (old_style) {
        var param = p.ast.nodes[f].b
        while (param >= 0) {
            let typing = p.ast.nodes[param].b
            let pt = c_parameter_type(r, p, p.ast.nodes[declaration_of(p, n.c, typing)].a, typing)
            return false if (pt < 0)
            typed |> push(pt)
            names |> push(pp_symbol_text(p.unit.lx, p.ast.nodes[param].a))
            r.old_style |> push(c_promoted(r, pt))
            param = p.ast.nodes[param].next
        }
    }
    r.anchor_at = loc_of(p, name_tok(p, d, n.tok))
    return false if (!c_tag_definitions(r, p, n.a, "", false))
    let t = c_declarator_type(r, p, c_specifier_type(r, p, n.a), d, false)
    r.old_style |> clear()
    return false if (!c_tag_complete(r, p))
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
            c_ir_bind(r, c_symbol(p.unit, pname), CId(t = pt, old_style = -1, name = local))
        }
    } else {
        ok = parameters(r, p, f, cd.params, true)
        var param = c_is_void_list(p, p.ast.nodes[f].b) ? -1 : p.ast.nodes[f].b
        var at = 0
        while (ok && param >= 0) {
            let psym = c_declarator_name(p.ast, p.ast.nodes[param].b)
            if (psym >= 0) {
                c_ir_bind(r, psym, CId(t = c_param_type(r, p, param), old_style = -1, name = cd.params[at].name))
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
def private in_library(r : CIr; var p : CParser; decl : int) : bool {
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
    let first = n.b >= 0 && !is_def ? p.ast.nodes[n.b].a : -1
    let hint = typedef_decl && first >= 0 && p.ast.nodes[first].kind == CNode.D_NAME ? name_of(p, first) : ""
    if (!c_tag_definitions(r, p, n.a, hint, true)) {
        library_tags_untyped(r, p, n.a)
        r.err = ""
    }
    var id = n.b
    while (id >= 0) {
        let d = p.ast.nodes[id].a
        let sym = c_declarator_name(p.ast, d)
        let t = c_declarator_type(r, p, c_specifier_type(r, p, n.a), d, false)
        if (t < 0) {
            if (typedef_decl) {
                r.typedefs |> erase(sym)
                r.untyped[sym] = r.err
            } else {
                r.ids |> erase(sym)
            }
            r.err = ""
        } elif (typedef_decl) {
            c_types_bind(r, sym, t)
            r.untyped |> erase(sym)
        } elif (r.pool[t].k == "func") {
            r.declared[sym] = true
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
    let slash = max(rfind(p.unit.name, "/"), rfind(p.unit.name, "\\"))
    r.tu.cir = CIR_VERSION
    r.tu.producer = C_IR_PRODUCER
    r.tu.tu = slice(p.unit.name, slash + 1)
    r.tu_prefix = ident_of(slice(r.tu.tu, 0, max(find(r.tu.tu, "."), 0)))
    collect_file_scope_names(r, p, u)
    c_tag_lookahead(r, p, u)
    var none : array<CirStmt?>
    var at = p.ast.nodes[u].a
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
    return empty(r.err)
}
