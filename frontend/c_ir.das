options gen2
options indenting = 4

module c_ir public

require strings
require daslib/strings_boost
require daslib/cmp
require c_exprs public

//! A unit's C-IR from the parser's tree as Dumper A writes it (`ARCHITECTURE_TYPES.md`,
//! `ARCHITECTURE_EXPRS.md`): its declarations, the statements of its function bodies, their
//! expressions with every conversion, and the type table in the order Dumper A's walk interns it.

//! Open the builder over the dialect `target` with an empty unit; `library_dir` is the own libc
//! headers' folder (`c_types_open`).
def c_ir_open(var r : CIr; target : CirTarget; library_dir : string) {
    c_types_open(r.b, target, library_dir)
    r.b.tu.decls |> clear()
    r.ids |> clear()
    r.id_undo |> clear()
    r.id_marks |> clear()
    r.ret = -1
}

// the location of token `tok` as a C-IR place
def private loc_of(var p : CParser; tok : int) : CirLoc {
    let t = p.unit.toks[tok]
    return CirLoc(file = c_file_name(p.unit, t.file), line = t.line, col = t.col)
}

// typed expression `x` interned and handed out; null stays null
def private used(var r : CIr; var x : CirExpr?) : CirExpr? {
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
    let k = r.b.pool[t].k
    let elem = k == "array" ? r.b.pool[t].elem : -1
    let char_array = elem >= 0 && r.b.pool[elem].k == "int" && r.b.pool[elem].w == 8
    if (n.kind == CNode.STRING && char_array) {
        var s = c_string_literal(r, p, n.a, n.b)
        if (s != null) {
            s.t = t
        }
        return s
    } elif (n.kind != CNode.INIT_LIST) {
        var x = c_expr(r, p, init)
        return x == null ? null : c_assigned(r, p, x, t, n.tok)
    } elif (k != "array") {
        let item = n.a
        if (item < 0 || p.ast.nodes[item].next >= 0 || p.ast.nodes[item].a >= 0) {
            c_refuse(r.b, p, n.tok, "a braced scalar initializer of other than one value")
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
            var at = c_expr(r, p, p.ast.nodes[it.a].a)
            var v = 0l
            if (p.ast.nodes[it.a].kind != CNode.DESIG_INDEX || p.ast.nodes[it.a].next >= 0 || at == null || !c_fold(r, at, v)) {
                c_refuse(r.b, p, it.tok, "this designator")
                return null
            }
            pos = int(v)
        }
        let value = p.ast.nodes[it.b]
        if (r.b.pool[elem].k == "array" && value.kind != CNode.INIT_LIST && value.kind != CNode.STRING) {
            c_refuse(r.b, p, it.tok, "an initializer of an array of arrays with elided braces")
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
// again, as Dumper A reads each parameter's declaration after the function's type
def private parameters(var r : CIr; var p : CParser; f : int; var into : array<CirParam>) : bool {
    return true if (p.ast.nodes[f].op == 2 || c_is_void_list(r.b, p, p.ast.nodes[f].b))
    var param = p.ast.nodes[f].b
    while (param >= 0) {
        let t = c_types_use(r.b, c_param_type(r.b, p, param))
        return false if (t < 0)
        into |> push(CirParam(name = name_of(p, p.ast.nodes[param].b), t = t))
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
    for (prev in r.b.tu.decls) {
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
    r.b.tu.decls |> push(g)
}

// the declaration of function `sym` (init-declarator `id`, pool type `t`): its composite type
// interned, then its parameters'; a block declaration of a name declared before adds no
// declaration, but its prototype converts the calls in its scope, as clang links it to the one
// before
def private function_declaration(var r : CIr; var p : CParser; id, t : int; is_static, local : bool) : bool {
    let d = p.ast.nodes[id].a
    let sym = c_declarator_name(p.ast, d)
    let f = c_name_function(p.ast, d)
    let linked = c_linked(r.b, p, t, sym, f, p.ast.nodes[id].tok)
    return false if (linked < 0)
    if (local && key_exists(r.b.declared, sym)) {
        c_ir_bind(r, sym, function_id(r, p, sym, linked, f))
        return true
    }
    let name = pp_symbol_text(p.unit.lx, sym)
    var cd = new CirDecl(k = "func", name = name, c_name = name, t = c_types_use(r.b, linked), is_static = is_static, loc = loc_of(p, p.ast.nodes[id].tok))
    r.b.declared[sym] = true
    c_ir_bind(r, sym, function_id(r, p, sym, linked, f))
    if (f >= 0 && !parameters(r, p, f, cd.params)) {
        delete_decl(cd)
        return false
    }
    r.b.tu.decls |> push(cd)
    return true
}

// the pool type of object declarator `id` of pool type `t`: at file scope or `extern`, the
// composite with the declarations of its name before it; a tentative definition's array of unknown
// size completed
def private object_type(var r : CIr; var p : CParser; t, id : int; local, is_extern : bool) : int {
    let sym = c_declarator_name(p.ast, p.ast.nodes[id].a)
    var typed = t
    if (!local || is_extern) {
        typed = c_linked(r.b, p, typed, sym, -1, p.ast.nodes[id].tok)
        return -1 if (typed < 0)
    }
    if (!local && !is_extern && p.ast.nodes[id].b < 0) {
        typed = c_tentative(r.b, p, typed, sym, id)
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
        c_refuse(r.b, p, n.tok, "a _Static_assert whose condition the builder cannot fold")
        return false
    } elif (v == 0l) {
        c_reject(r.b, p, n.tok, "a _Static_assert whose condition is 0")
        return false
    }
    return true
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
    if (n.b < 0) {
        return c_specifier_type(r.b, p, n.a) >= 0
    }
    // the specifiers name one type for every declarator, resolved before any of them binds a name
    let base = c_specifier_type(r.b, p, n.a)
    return false if (base < 0)
    let local = !empty(fn)
    var next = n.b
    while (next >= 0) {
        let id = next
        next = p.ast.nodes[id].next
        let d = p.ast.nodes[id].a
        let sym = c_declarator_name(p.ast, d)
        let name = pp_symbol_text(p.unit.lx, sym)
        let at = loc_of(p, p.ast.nodes[id].tok)
        return false if (!c_plain_attributes(r.b, p, p.ast.nodes[id].d))
        let init_node = p.ast.nodes[id].b
        var t = c_sized_by_initializer(r.b, p, c_declarator_type(r.b, p, base, d, false, init_node), d, init_node)
        return false if (t < 0)
        if (typedef_decl) {
            var td = CirType(k = "typedef", name = name, to = c_types_use(r.b, t))
            let entry = c_types_intern_typedef(r.b, td)
            r.b.tu.decls |> push(new CirDecl(k = "typedefdecl", name = name, c_name = name, t = entry, loc = at))
            c_types_bind(r.b, sym, t)
            continue
        }
        if (r.b.pool[t].k == "func") {
            return false if (!function_declaration(r, p, id, t, is_static, local))
            continue
        }
        t = object_type(r, p, t, id, local, is_extern)
        return false if (t < 0)
        let ti = c_types_use(r.b, t)
        c_ir_bind(r, sym, CId(t = t, old_style = -1))
        let init = init_node
        var value = init >= 0 ? used(r, initializer(r, p, init, t)) : null
        return false if (init >= 0 && value == null)
        if (empty(fn)) {
            push_global(r, new CirDecl(k = "global", name = name, c_name = name, t = ti, is_static = is_static, is_extern = is_extern && init < 0, init = value, loc = at))
        } elif (is_static) {
            r.b.tu.decls |> push(new CirDecl(k = "global", name = "{fn}_{name}", c_name = name, t = ti, is_static = true, from_func = fn, init = value, loc = at))
            into |> push(new CirStmt(s = "null", loc = at))
        } elif (is_extern) {
            if (!key_exists(r.b.declared, sym)) {
                r.b.tu.decls |> push(new CirDecl(k = "global", name = name, c_name = name, t = ti, is_extern = true, loc = at))
            }
            into |> push(new CirStmt(s = "null", loc = at))
        } else {
            into |> push(new CirStmt(s = "decl", name = name, t = ti, init = value, loc = at))
        }
        if (empty(fn) || is_extern) {
            r.b.declared[sym] = true
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
    if (n.kind == CNode.DECL) {
        return declaration(r, p, s, fn, into)
    } elif (n.kind == CNode.STATIC_ASSERT) {
        return static_assertion(r, p, n)
    } elif (n.kind == CNode.LABEL || n.kind == CNode.CASE || n.kind == CNode.DEFAULT) {
        if (n.kind == CNode.LABEL) {
            into |> push(new CirStmt(s = "label", label_name = pp_symbol_text(p.unit.lx, n.a), loc = at))
        } elif (n.kind == CNode.DEFAULT) {
            into |> push(new CirStmt(s = "default", loc = at))
        } else {
            var v = 0l
            var value = c_expr(r, p, n.a)
            if (n.b >= 0 || value == null || !c_fold(r, value, v)) {
                c_refuse(r.b, p, n.tok, "this case label")
                return false
            }
            if (key_exists(r.cases, v)) {
                c_reject(r.b, p, n.tok, "a duplicate case value")
                delete_expr(value)
                return false
            }
            r.cases[v] = true
            into |> push(new CirStmt(s = "case", v = v, is_char = value.e == "int_lit" && value.is_char, loc = at))
            delete_expr(value)
        }
        let sub = n.kind == CNode.LABEL ? n.b : n.kind == CNode.DEFAULT ? n.a : n.c
        if (sub < 0) {
            into |> push(new CirStmt(s = "null", loc = at))
            return true
        }
        return statement(r, p, sub, fn, into)
    }
    if (n.kind == CNode.EXPR_STMT && statement_block(r, p, n.a) >= 0) {
        return statement(r, p, statement_block(r, p, n.a), fn, into)
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
        c_types_scope_open(r.b)
        c_ir_open(r)
        var item = n.a
        while (ok && item >= 0) {
            ok = statement(r, p, item, fn, st.body)
            item = p.ast.nodes[item].next
        }
        c_ir_close(r)
        c_types_scope_close(r.b)
    } elif (n.kind == CNode.EXPR_STMT) {
        st.s = "expr"
        st.e = used(r, value_of(r, p, n.a))
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
        let void_fn = r.b.pool[r.ret].k == "void"
        if (n.a >= 0) {
            var e = c_expr(r, p, n.a)
            if (e != null && void_fn && r.b.pool[r.b.unqualified[e.t]].k != "void") {
                c_reject(r.b, p, n.tok, "a value returned from a void function")
                delete_expr(e)
                return false
            }
            st.e = e == null ? null : used(r, void_fn ? c_rvalue(r, e) : c_assigned(r, p, e, r.ret, p.ast.nodes[n.a].tok))
            ok = st.e != null
        } elif (!void_fn) {
            c_reject(r.b, p, n.tok, "a return with no value from a function that returns one")
            ok = false
        }
    } else {
        c_refuse(r.b, p, n.tok, "this statement")
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
        st.cond = used(r, value_of(r, p, n.a))
        ok = st.cond != null && one(r, p, n.b, fn, st.then_s) && (n.c < 0 || one(r, p, n.c, fn, st.else_s))
    } elif (n.kind == CNode.WHILE) {
        st.s = "while"
        st.cond = used(r, value_of(r, p, n.a))
        ok = st.cond != null && one(r, p, n.b, fn, st.body_s)
    } elif (n.kind == CNode.DO) {
        st.s = "do"
        ok = one(r, p, n.a, fn, st.body_s)
        st.cond = ok ? used(r, value_of(r, p, n.b)) : null
        ok = ok && st.cond != null
    } elif (n.kind == CNode.SWITCH) {
        st.s = "switch"
        var c = c_expr(r, p, n.a)
        st.cond = c == null ? null : used(r, c_promote(r, c))
        var outer <- r.cases
        ok = st.cond != null && one(r, p, n.b, fn, st.body_s)
        r.cases <- outer
    } else {
        st.s = "for"
        c_types_scope_open(r.b)
        c_ir_open(r)
        if (n.a >= 0 && p.ast.nodes[n.a].kind == CNode.DECL) {
            st.init_s = new CirStmt(s = "compound", loc = loc_of(p, p.ast.nodes[n.a].tok))
            ok = declaration(r, p, n.a, fn, st.init_s.body)
        } elif (n.a >= 0) {
            var e = used(r, value_of(r, p, n.a))
            ok = e != null
            st.init_s = new CirStmt(s = "expr", e = e, loc = loc_of(p, p.ast.nodes[n.a].tok))
        }
        st.cond = ok && n.b >= 0 ? used(r, value_of(r, p, n.b)) : null
        ok = ok && (n.b < 0 || st.cond != null)
        st.inc = ok && n.c >= 0 ? used(r, value_of(r, p, n.c)) : null
        ok = ok && (n.c < 0 || st.inc != null) && one(r, p, n.d, fn, st.body_s)
        c_ir_close(r)
        c_types_scope_close(r.b)
    }
    return ok
}

// the compound statement of GNU statement expression `e` evaluated for its effect alone, through
// parentheses, `__extension__` and a cast to `void`, as Dumper A takes it for its block; -1 for any
// other expression
def private statement_block(var r : CIr; var p : CParser; e : int) : int {
    let n = p.ast.nodes[e]
    if (n.kind == CNode.STMT_EXPR) {
        return n.a
    } elif (n.kind == CNode.PAREN || n.kind == CNode.EXTENSION) {
        return statement_block(r, p, n.a)
    } elif (n.kind == CNode.CAST && is_void_name(r, p, n.a)) {
        return statement_block(r, p, n.b)
    }
    return -1
}

// whether type-name node `t` names `void`
def private is_void_name(var r : CIr; var p : CParser; t : int) : bool {
    let ty = c_type_name_type(r.b, p, t)
    return ty >= 0 && r.b.pool[ty].k == "void"
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
            let old = declaration_of(p, n.c, typing)
            var typed_by = p.ast.nodes[old].b
            while (typed_by >= 0 && p.ast.nodes[typed_by].a != typing) {
                typed_by = p.ast.nodes[typed_by].next
            }
            return false if (!c_plain_attributes(r.b, p, p.ast.nodes[typed_by].d))
            let pt = c_parameter_type(r.b, p, p.ast.nodes[old].a, typing)
            return false if (pt < 0)
            typed |> push(pt)
            names |> push(pp_symbol_text(p.unit.lx, p.ast.nodes[param].a))
            r.b.old_style |> push(c_promoted(r.b, pt))
            param = p.ast.nodes[param].next
        }
    }
    let spelled = c_declarator_type(r.b, p, c_specifier_type(r.b, p, n.a), d, false)
    r.b.old_style |> clear()
    let t = spelled < 0 ? spelled : c_linked(r.b, p, spelled, sym, f, p.ast.nodes[n.b].tok)
    let ti = c_types_use(r.b, t)
    return false if (ti < 0)
    var cd = new CirDecl(k = "func", name = name, c_name = name, t = ti, is_static = has_storage(p, n.a, CTok.STATIC), loc = loc_of(p, n.tok))
    r.b.declared[sym] = true
    if (old_style) {
        var none : array<int>
        c_ir_bind(r, sym, CId(t = c_function(r.b, r.b.pool[t].ret, none, false), is_function = true, old_style = t))
    } else {
        c_ir_bind(r, sym, function_id(r, p, sym, t, f))
    }
    c_ir_open(r)
    c_types_scope_open(r.b)
    var ok = true
    if (old_style) {
        cd.params |> reserve(length(typed))
        for (pt, pname in typed, names) {
            cd.params |> push(CirParam(name = pname, t = c_types_use(r.b, pt)))
            c_ir_bind(r, c_symbol(p.unit, pname), CId(t = pt, old_style = -1))
        }
    } else {
        ok = parameters(r, p, f, cd.params)
        var param = p.ast.nodes[f].b
        while (ok && param >= 0) {
            c_ir_bind(r, c_declarator_name(p.ast, p.ast.nodes[param].b), CId(t = c_param_type(r.b, p, param), old_style = -1))
            param = p.ast.nodes[param].next
        }
    }
    r.ret = r.b.pool[t].ret
    var body : array<CirStmt?>
    ok = ok && statement(r, p, n.d, name, body)
    c_types_scope_close(r.b)
    c_ir_close(r)
    if (ok) {
        cd.body = body[0]
        r.b.tu.decls |> push(cd)
    } else {
        delete_decl(cd)
    }
    return ok
}

// whether external declaration `decl` stands in a file under the own libc headers' folder
def private in_library(r : CIr; var p : CParser; decl : int) : bool {
    return false if (empty(r.b.library_dir))
    let file = c_file_name(p.unit, p.unit.toks[p.ast.nodes[decl].tok].file)
    return starts_with(file, r.b.library_dir)
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
    var id = n.b
    while (id >= 0) {
        let d = p.ast.nodes[id].a
        let sym = c_declarator_name(p.ast, d)
        let t = c_plain_attributes(r.b, p, p.ast.nodes[id].d) ? c_declarator_type(r.b, p, c_specifier_type(r.b, p, n.a), d, false) : -1
        if (t < 0) {
            if (typedef_decl) {
                r.b.untyped[sym] = r.b.err
            } else {
                r.ids |> erase(sym)
            }
            r.b.err = ""
        } elif (typedef_decl) {
            c_types_bind(r.b, sym, t)
        } elif (r.b.pool[t].k == "func") {
            r.b.declared[sym] = true
            r.b.library_functions[sym] = int2(decl, is_def ? n.b : id)
            c_ir_bind(r, sym, function_id(r, p, sym, t, c_name_function(p.ast, d)))
        } else {
            r.b.declared[sym] = true
            c_ir_bind(r, sym, CId(t = t, old_style = -1))
        }
        id = is_def ? -1 : p.ast.nodes[id].next
    }
}

//! The C-IR of unit node `u`, which `c_unit` built, into `r.b.tu`: its declarations, bodies and
//! expressions, and the type table in the order Dumper A's walk interns it; false with the error
//! set at the first construct not built yet. Under the msvc dialect `size_t`, which clang declares
//! there before the unit, is `unsigned long long`.
[arch(at="ARCHITECTURE_TYPES.md#c-types-order")]
def c_ir_unit(var r : CIr; var p : CParser; u : int) : bool {
    if (is_msvc(r.b.tu.target)) {
        c_types_bind(r.b, c_symbol(p.unit, "size_t"), c_builtin(r.b, "unsigned long long"))
    }
    var none : array<CirStmt?>
    var at = p.ast.nodes[u].a
    r.b.unit_items = at
    while (empty(r.b.err) && at >= 0) {
        if (in_library(r, p, at)) {
            library_declaration(r, p, at)
        } elif (p.ast.nodes[at].kind == CNode.FUNC_DEF) {
            definition(r, p, at)
        } else {
            declaration(r, p, at, "", none)
        }
        at = p.ast.nodes[at].next
    }
    return empty(r.b.err)
}
