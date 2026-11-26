options gen2
options indenting = 4

module c1_lr shared public

// Candidate LR: the C99 grammar with the GNU forms Dumper A reads, as a dasBison `[bison]` grammar
// whose actions build the shared AST (`c1_ast`) over the shared token array. The typedef-name
// ambiguity is the classic yacc one: `lr_scan`, the parser's lexer, turns a word into TYPEDEF_NAME
// when the scope table binds it as a typedef and no type specifier came before it in the current
// specifier list, a state it keeps from the tokens it hands out; the grammar's actions write the
// table. Because an LR parser reads one token past a reduction, every scope and specifier effect of
// a token the lexer hands out runs when the next token is asked for, after the parser has shifted
// it: a block's scope opens after its `{` and closes after its `}`, a declaration's typedef flag
// clears after its `;`. Binary operators are one rule with precedence declarations rather than the
// standard's ladder of ten rules.

require strings
require math
require bison/bison_macro
require c1_ast public

//! The token the parser stacks: kind and location, and its index in the token array.
struct LrTok {
    kind : int
    line : int
    col : int
    idx : int
}

//! An open brace: what it opens, and the lexer state the brace saved.
struct LrBrace {
    what : int          //!< BRACE_BLOCK, BRACE_RECORD or BRACE_INIT
    ts : bool
    typedef_flag : bool
    parens : int
    is_enum : bool
}

let BRACE_BLOCK = 0
let BRACE_RECORD = 1
let BRACE_INIT = 2

//! The parser's lexer over `src.toks`, and the tree and scopes the actions write.
struct LrLexer {
    tok : LrTok
    failed : bool
    err : string
    line : int
    col : int
    file : string
    src : Source
    ast : Ast
    sc : Scopes
    pos : int
    eof : int
    ts : bool                   //!< a type specifier came in the current specifier list
    typedef_flag : bool         //!< the current declaration's specifiers hold `typedef`
    tag_pending : bool          //!< after struct/union/enum, before its tag or body
    tag_parens : int            //!< the open parentheses at that struct/union/enum
    tag_is_enum : bool
    prev_kind : int
    parens : array<bool>        //!< per open `(`, the `ts` it saved
    braces : array<LrBrace>
    pending_fn : int            //!< the function declarator a definition's body opens with, -1 none
}

struct LrParser : ParserStatus {
    lexer : LrLexer
}

def private is_type_keyword(k : int) : bool {
    return (k == int(TK.VOID) || k == int(TK.CHAR) || k == int(TK.SHORT) || k == int(TK.INT) || k == int(TK.LONG)
        || k == int(TK.FLOAT) || k == int(TK.DOUBLE) || k == int(TK.SIGNED) || k == int(TK.UNSIGNED)
        || k == int(TK.BOOL) || k == int(TK.COMPLEX) || k == int(TK.IMAGINARY) || k == int(TK.TYPEOF))
}

//! The deferred effects of the token handed out last, now that the parser has shifted it.
def private settle(var lx : LrLexer) {
    let k = lx.prev_kind
    if (k == int(TK.LBRACE)) {
        if (lx.braces[length(lx.braces) - 1].what == BRACE_BLOCK) {
            scope_open(lx.sc)
            if (lx.pending_fn >= 0) {
                var prm = lx.ast.nodes[lx.pending_fn].b
                while (prm >= 0) {
                    let pn = lx.ast.nodes[prm]
                    scope_declare(lx.sc, pn.kind == int(NK.IDENT_PARAM) ? pn.a : declarator_name(lx.ast, pn.b), ORDINARY)
                    prm = pn.next
                }
            }
        }
    } elif (k == int(TK.RBRACE)) {
        if (length(lx.braces) > 0) {
            let b = lx.braces[length(lx.braces) - 1]
            lx.braces |> pop()
            if (b.what == BRACE_BLOCK) {
                scope_close(lx.sc)
                lx.ts = false
            } else {
                lx.ts = b.ts
            }
            lx.typedef_flag = b.typedef_flag
        }
    } elif (k == int(TK.SEMI)) {
        lx.ts = false
        lx.typedef_flag = false
    }
    lx.pending_fn = -1
}

def private paren_floor(lx : LrLexer) : int => length(lx.braces) == 0 ? 0 : lx.braces[length(lx.braces) - 1].parens

//! The parser's lexer: the next token of `src.toks`, a word classified as IDENTIFIER or
//! TYPEDEF_NAME; `false` at the end.
def lr_scan(var lx : LrLexer) : bool {
    settle(lx)
    if (lx.pos >= lx.eof) {
        let t = lx.src.toks[lx.eof]
        lx.line = t.line
        lx.col = t.col
        return false
    }
    let t = lx.src.toks[lx.pos]
    var k = t.kind
    let prev = lx.prev_kind
    if (k == int(TK.IDENTIFIER)) {
        let enumerator = length(lx.braces) > 0 && lx.braces[length(lx.braces) - 1].is_enum && (prev == int(TK.LBRACE) || prev == int(TK.COMMA))
        let forced = enumerator || lx.tag_pending || prev == int(TK.DOT) || prev == int(TK.ARROW) || prev == int(TK.GOTO)
        if (!forced && !lx.ts && is_typedef_name(lx.sc, t.sym)) {
            k = int(TK.TYPEDEF_NAME)
            lx.ts = true
        }
    } elif (is_type_keyword(k)) {
        lx.ts = true
    } elif (k == int(TK.STRUCT) || k == int(TK.UNION) || k == int(TK.ENUM)) {
        lx.ts = true
        lx.tag_pending = true
        lx.tag_parens = length(lx.parens)
        lx.tag_is_enum = k == int(TK.ENUM)
    } elif (k == int(TK.TYPEDEF)) {
        lx.typedef_flag = true
    } elif (k == int(TK.LPAREN)) {
        lx.parens |> push(lx.ts)
        lx.ts = false
    } elif (k == int(TK.RPAREN)) {
        if (length(lx.parens) > paren_floor(lx)) {
            lx.ts = lx.parens[length(lx.parens) - 1]
            lx.parens |> pop()
        }
    } elif (k == int(TK.COMMA)) {
        if (length(lx.parens) > paren_floor(lx)) {
            lx.ts = false
        }
    } elif (k == int(TK.LBRACE)) {
        var what = BRACE_BLOCK
        if (lx.tag_pending) {
            what = BRACE_RECORD
        } elif (prev == int(TK.ASSIGN)) {
            what = BRACE_INIT
        } elif (length(lx.braces) > 0 && lx.braces[length(lx.braces) - 1].what == BRACE_INIT && (prev == int(TK.LBRACE) || prev == int(TK.COMMA))) {
            what = BRACE_INIT
        }
        lx.braces |> push(LrBrace(what = what, ts = lx.ts, typedef_flag = lx.typedef_flag, parens = length(lx.parens), is_enum = what == BRACE_RECORD && lx.tag_is_enum))
        lx.ts = false
        lx.typedef_flag = false
    }
    let depth = length(lx.parens)
    if (lx.tag_pending && (depth < lx.tag_parens || (depth == lx.tag_parens && k != int(TK.STRUCT) && k != int(TK.UNION) && k != int(TK.ENUM) && k != int(TK.IDENTIFIER) && k != int(TK.ATTRIBUTE) && k != int(TK.LPAREN) && k != int(TK.RPAREN)))) {
        lx.tag_pending = false
    }
    lx.tok = LrTok(kind = k, line = t.line, col = t.col, idx = lx.pos)
    lx.file = lx.src.files[t.file]
    lx.prev_kind = k
    lx.pos++
    return true
}

// ---- action helpers

def private mk(var p : LrParser; kind : NK; t : LrTok) : int => add_node(p.lexer.ast, p.lexer.src.toks, kind, t.idx)

def private mk_at(var p : LrParser; kind : NK; at : int) : int => add_node_at(p.lexer.ast, kind, at)

def private sym(p : LrParser; t : LrTok) : int => p.lexer.src.toks[t.idx].sym

def private set_ab(var p : LrParser; n, a, b : int) : int {
    p.lexer.ast.nodes[n].a = a
    p.lexer.ast.nodes[n].b = b
    return n
}

def private one(var p : LrParser; n : int) : int2 {
    var l = empty_list()
    append(p.lexer.ast, l, n)
    return int2(l.head, l.tail)
}

def private more(var p : LrParser; l : int2; n : int) : int2 {
    var nl = NodeList(head = l.x, tail = l.y)
    append(p.lexer.ast, nl, n)
    return int2(nl.head, nl.tail)
}

def private cat(var p : LrParser; a, b : int) : int {
    var nl = empty_list()
    append(p.lexer.ast, nl, a)
    append(p.lexer.ast, nl, b)
    return nl.head
}

def private node1(var p : LrParser; kind : NK; t : LrTok; a : int) : int => set_ab(p, mk(p, kind, t), a, -1)

def private kw(var p : LrParser; t : LrTok) : int {
    let n = mk(p, NK.SPEC_KW, t)
    p.lexer.ast.nodes[n].op = t.kind
    return n
}

def private bin(var p : LrParser; a : int; t : LrTok; b : int) : int {
    let n = mk_at(p, NK.E_BINARY, a)
    p.lexer.ast.nodes[n].op = t.kind
    return set_ab(p, n, a, b)
}

def private unop(var p : LrParser; t : LrTok; a : int) : int {
    let n = node1(p, NK.E_UNARY, t, a)
    p.lexer.ast.nodes[n].op = t.kind
    return n
}

def private assign(var p : LrParser; a : int; t : LrTok; b : int) : int {
    let n = mk_at(p, NK.E_ASSIGN, a)
    p.lexer.ast.nodes[n].op = t.kind
    return set_ab(p, n, a, b)
}

def private cond(var p : LrParser; c, a, b : int) : int {
    let n = set_ab(p, mk_at(p, NK.E_COND, c), c, a)
    p.lexer.ast.nodes[n].c = b
    return n
}

def private postfix_op(var p : LrParser; kind : NK; a : int; t : LrTok; b : int) : int {
    let n = set_ab(p, mk_at(p, kind, a), a, b)
    p.lexer.ast.nodes[n].op = t.kind
    return n
}

def private sized(var p : LrParser; kind : NK; t : LrTok; a : int) : int {
    let n = node1(p, kind, t, a)
    p.lexer.ast.nodes[n].op = t.kind == int(TK.SIZEOF) ? 0 : t.kind
    return n
}

//! A suffix (array or function declarator) applied to `inner`: located at it when there is one.
def private suffix(var p : LrParser; inner, s : int) : int {
    if (inner >= 0) {
        let at = p.lexer.ast.nodes[inner]
        p.lexer.ast.nodes[s].file = at.file
        p.lexer.ast.nodes[s].line = at.line
        p.lexer.ast.nodes[s].col = at.col
    }
    p.lexer.ast.nodes[s].a = inner
    return s
}

def private array_node(var p : LrParser; t : LrTok; flags, quals, size : int) : int {
    let n = mk(p, NK.D_ARRAY, t)
    p.lexer.ast.nodes[n].op = flags
    p.lexer.ast.nodes[n].b = size
    p.lexer.ast.nodes[n].c = quals
    return n
}

def private func_node(var p : LrParser; t : LrTok; flags, params : int) : int {
    let n = mk(p, NK.D_FUNC, t)
    p.lexer.ast.nodes[n].op = flags
    p.lexer.ast.nodes[n].b = params
    return n
}

//! A pointer chain `*q *q ...`: x = the outermost D_PTR, y = the innermost.
def private ptr(var p : LrParser; t : LrTok; quals : int; rest : int2) : int2 {
    let n = mk(p, NK.D_PTR, t)
    p.lexer.ast.nodes[n].b = quals
    if (rest.x >= 0) {
        p.lexer.ast.nodes[n].a = rest.x
        return int2(n, rest.y)
    }
    return int2(n, n)
}

def private with_pointer(var p : LrParser; chain : int2; inner : int) : int {
    p.lexer.ast.nodes[chain.y].a = inner
    return chain.x
}

def private paren_decl(var p : LrParser; t : LrTok; attrs, inner : int) : int => set_ab(p, mk(p, NK.D_PAREN, t), inner, attrs)

//! An INIT_DECL head; it declares its name in the current scope, as a typedef under `typedef`, and
//! a function definition's body sees the parameters of its function declarator.
def private head(var p : LrParser; d, asm_label, attrs : int) : int {
    let n = set_ab(p, mk_at(p, NK.INIT_DECL, d), d, -1)
    p.lexer.ast.nodes[n].c = asm_label
    p.lexer.ast.nodes[n].d = attrs
    scope_declare(p.lexer.sc, declarator_name(p.lexer.ast, d), p.lexer.typedef_flag ? TYPEDEF : ORDINARY)
    p.lexer.pending_fn = name_function(p.lexer.ast, d)
    return n
}

def private decl(var p : LrParser; specs : int2; list : int) : int => set_ab(p, mk_at(p, NK.DECL, specs.x), specs.x, list)

def private func_def(var p : LrParser; specs : int2; h, knr, body : int) : int {
    let n = set_ab(p, mk_at(p, NK.FUNC_DEF, specs.x), specs.x, h)
    p.lexer.ast.nodes[n].c = knr
    p.lexer.ast.nodes[n].d = body
    return n
}

def private record(var p : LrParser; h, tag : int; body : int2; attrs : int) : int {
    p.lexer.ast.nodes[h].a = tag
    p.lexer.ast.nodes[h].b = body.x
    p.lexer.ast.nodes[h].c = body.y
    p.lexer.ast.nodes[h].d = cat(p, p.lexer.ast.nodes[h].d, attrs)
    return h
}

def private enumerator(var p : LrParser; t : LrTok; attrs, value : int) : int {
    let n = set_ab(p, mk(p, NK.ENUMERATOR, t), sym(p, t), value)
    p.lexer.ast.nodes[n].c = attrs
    scope_declare(p.lexer.sc, sym(p, t), ORDINARY)
    return n
}

def private member(var p : LrParser; d, width, attrs : int) : int {
    let n = set_ab(p, mk_at(p, NK.MEMBER_DECLARATOR, d), d, width)
    p.lexer.ast.nodes[n].c = attrs
    return n
}

def private attr(var p : LrParser; t : LrTok; args, has_parens : int) : int {
    let n = set_ab(p, mk(p, NK.ATTR, t), sym(p, t), args)
    p.lexer.ast.nodes[n].c = has_parens
    return n
}

def private label_stmt(var p : LrParser; t : LrTok; attrs, s : int) : int {
    let n = set_ab(p, mk(p, NK.S_LABEL, t), sym(p, t), s)
    p.lexer.ast.nodes[n].c = attrs
    return n
}

def private case_stmt(var p : LrParser; t : LrTok; lo, hi, s : int) : int {
    let n = set_ab(p, mk(p, NK.S_CASE, t), lo, hi)
    p.lexer.ast.nodes[n].c = s
    return n
}

def private for_stmt(var p : LrParser; t : LrTok; init, c, step, body : int) : int {
    let n = set_ab(p, mk(p, NK.S_FOR, t), init, c)
    p.lexer.ast.nodes[n].c = step
    p.lexer.ast.nodes[n].d = body
    return n
}

def private expr_stmt(var p : LrParser; e : int) : int => set_ab(p, mk_at(p, NK.S_EXPR, e), e, -1)

def private if_stmt(var p : LrParser; t : LrTok; c, a, b : int) : int {
    let n = set_ab(p, mk(p, NK.S_IF, t), c, a)
    p.lexer.ast.nodes[n].c = b
    return n
}

def private asm_stmt(var p : LrParser; t : LrTok; flags, tmpl : int; tail : int3) : int {
    let n = set_ab(p, mk(p, NK.S_ASM, t), tmpl, tail.x)
    p.lexer.ast.nodes[n].op = flags
    p.lexer.ast.nodes[n].c = tail.y
    p.lexer.ast.nodes[n].d = tail.z
    return n
}

def private asm_operand(var p : LrParser; at : LrTok; name, constraint, e : int) : int {
    let n = name >= 0 ? mk(p, NK.ASM_OPERAND, at) : mk_at(p, NK.ASM_OPERAND, constraint)
    p.lexer.ast.nodes[n].c = name
    return set_ab(p, n, constraint, e)
}

def private desig_index(var p : LrParser; t : LrTok; a, b : int) : int => set_ab(p, mk(p, NK.DESIG_INDEX, t), a, b)

def private init_item(var p : LrParser; desigs : int2; value : int) : int {
    let n = mk_at(p, NK.INIT_ITEM, desigs.x >= 0 ? desigs.x : value)
    return set_ab(p, n, desigs.x, value)
}

def private tu(var p : LrParser; decls : int2) : int {
    let n = add_node(p.lexer.ast, p.lexer.src.toks, NK.TU, 0)
    p.lexer.ast.root = n
    return set_ab(p, n, decls.x, -1)
}

def private param(var p : LrParser; specs : int2; d : int) : int => set_ab(p, mk_at(p, NK.PARAM, specs.x), specs.x, d)

def private type_name(var p : LrParser; specs : int2; d : int) : int => set_ab(p, mk_at(p, NK.TYPENAME, specs.x), specs.x, d)

[bison(tokens = TK, lexer = lr_scan)]
def lr_c(var p : LrParser) : int {  // nolint:STYLE038 - a grammar is one rule list by construction
    prec_left("OROR")
    prec_left("ANDAND")
    prec_left("PIPE")
    prec_left("CARET")
    prec_left("AMP")
    prec_left("EQ", "NE")
    prec_left("LT", "GT", "LE", "GE")
    prec_left("SHL", "SHR")
    prec_left("PLUS", "MINUS")
    prec_left("STAR", "SLASH", "PERCENT")
    root("translation_unit")

    // ---- translation unit
    rule("translation_unit", "ext_list") <| $(l : int2) => tu(p, l)
    rule("ext_list", "") <| $() => int2(-1, -1)
    rule("ext_list", "ext_list external_declaration") <| $(l : int2; d : int) => more(p, l, d)
    rule("external_declaration", "function_definition") <| $(n : int) => n
    rule("external_declaration", "declaration")
    rule("external_declaration", "SEMI") <| $(t : LrTok) => -1

    // ---- primary and postfix expressions
    rule("primary", "IDENTIFIER") <| $(t : LrTok) => node1(p, NK.E_IDENT, t, sym(p, t))
    rule("primary", "I_CONSTANT") <| $(t : LrTok) => node1(p, NK.E_INT, t, t.idx)
    rule("primary", "F_CONSTANT") <| $(t : LrTok) => node1(p, NK.E_FLOAT, t, t.idx)
    rule("primary", "C_CONSTANT") <| $(t : LrTok) => node1(p, NK.E_CHAR, t, t.idx)
    rule("primary", "string_lit")
    rule("primary", "FUNC_NAME") <| $(t : LrTok) => node1(p, NK.E_FUNC_NAME, t, sym(p, t))
    rule("primary", "LPAREN expr RPAREN") <| $(t : LrTok; e : int; r : LrTok) => node1(p, NK.E_PAREN, t, e)
    rule("primary", "LPAREN compound_statement RPAREN") <| $(t : LrTok; s : int; r : LrTok) => node1(p, NK.E_STMT_EXPR, t, s)
    rule("primary", "VA_ARG LPAREN assign_expr COMMA type_name RPAREN") <| $(t : LrTok; l : LrTok; e : int; c : LrTok; tn : int; r : LrTok) => set_ab(p, mk(p, NK.E_VA_ARG, t), e, tn)
    rule("primary", "OFFSETOF LPAREN type_name COMMA offsetof_path RPAREN") <| $(t : LrTok; l : LrTok; tn : int; c : LrTok; path : int2; r : LrTok) => set_ab(p, mk(p, NK.E_OFFSETOF, t), tn, path.x)
    rule("offsetof_path", "IDENTIFIER") <| $(t : LrTok) => one(p, node1(p, NK.DESIG_FIELD, t, sym(p, t)))
    rule("offsetof_path", "offsetof_path DOT IDENTIFIER") <| $(l : int2; d : LrTok; t : LrTok) => more(p, l, node1(p, NK.DESIG_FIELD, d, sym(p, t)))
    rule("offsetof_path", "offsetof_path LBRACKET expr RBRACKET") <| $(l : int2; b : LrTok; e : int; r : LrTok) => more(p, l, node1(p, NK.DESIG_INDEX, b, e))
    rule("string_lit", "STRING_LITERAL") <| $(t : LrTok) => set_ab(p, mk(p, NK.E_STRING, t), t.idx, 1)
    rule("string_lit", "string_lit STRING_LITERAL") <| $(s : int; t : LrTok) {
        p.lexer.ast.nodes[s].b++
        return s
    }
    rule("postfix", "primary")
    rule("postfix", "postfix LBRACKET expr RBRACKET") <| $(a : int; t : LrTok; i : int; r : LrTok) => set_ab(p, mk_at(p, NK.E_INDEX, a), a, i)
    rule("postfix", "postfix LPAREN RPAREN") <| $(a : int; t : LrTok; r : LrTok) => set_ab(p, mk_at(p, NK.E_CALL, a), a, -1)
    rule("postfix", "postfix LPAREN args RPAREN") <| $(a : int; t : LrTok; l : int2; r : LrTok) => set_ab(p, mk_at(p, NK.E_CALL, a), a, l.x)
    rule("postfix", "postfix DOT IDENTIFIER") <| $(a : int; t : LrTok; m : LrTok) => postfix_op(p, NK.E_MEMBER, a, t, sym(p, m))
    rule("postfix", "postfix ARROW IDENTIFIER") <| $(a : int; t : LrTok; m : LrTok) => postfix_op(p, NK.E_MEMBER, a, t, sym(p, m))
    rule("postfix", "postfix INC") <| $(a : int; t : LrTok) => postfix_op(p, NK.E_POSTFIX, a, t, -1)
    rule("postfix", "postfix DEC") <| $(a : int; t : LrTok) => postfix_op(p, NK.E_POSTFIX, a, t, -1)
    rule("postfix", "LPAREN type_name RPAREN init_braces") <| $(t : LrTok; tn : int; r : LrTok; i : int) => set_ab(p, mk(p, NK.E_COMPOUND_LIT, t), tn, i)
    rule("args", "assign_expr") <| $(e : int) => one(p, e)
    rule("args", "args COMMA assign_expr") <| $(l : int2; c : LrTok; e : int) => more(p, l, e)

    // ---- unary, cast, binary, conditional, assignment, comma
    rule("unary", "postfix")
    rule("unary", "INC unary") <| $(t : LrTok; a : int) => unop(p, t, a)
    rule("unary", "DEC unary") <| $(t : LrTok; a : int) => unop(p, t, a)
    rule("unary", "unary_operator cast_expr") <| $(t : LrTok; a : int) => unop(p, t, a)
    rule("unary", "SIZEOF unary") <| $(t : LrTok; a : int) => sized(p, NK.E_SIZEOF_EXPR, t, a)
    rule("unary", "SIZEOF LPAREN type_name RPAREN") <| $(t : LrTok; l : LrTok; tn : int; r : LrTok) => sized(p, NK.E_SIZEOF_TYPE, t, tn)
    rule("unary", "ALIGNOF LPAREN type_name RPAREN") <| $(t : LrTok; l : LrTok; tn : int; r : LrTok) => sized(p, NK.E_ALIGNOF_TYPE, t, tn)
    rule("unary", "ALIGNOF_GNU LPAREN type_name RPAREN") <| $(t : LrTok; l : LrTok; tn : int; r : LrTok) => sized(p, NK.E_ALIGNOF_TYPE, t, tn)
    rule("unary", "ALIGNOF_GNU unary") <| $(t : LrTok; a : int) => sized(p, NK.E_ALIGNOF_EXPR, t, a)
    rule("unary", "ANDAND IDENTIFIER") <| $(t : LrTok; l : LrTok) => node1(p, NK.E_LABEL_ADDR, t, sym(p, l))
    rule("unary", "EXTENSION cast_expr") <| $(t : LrTok; a : int) => node1(p, NK.E_EXTENSION, t, a)
    rule("unary_operator", "AMP") <| $(t : LrTok) => t
    rule("unary_operator", "STAR") <| $(t : LrTok) => t
    rule("unary_operator", "PLUS") <| $(t : LrTok) => t
    rule("unary_operator", "MINUS") <| $(t : LrTok) => t
    rule("unary_operator", "TILDE") <| $(t : LrTok) => t
    rule("unary_operator", "BANG") <| $(t : LrTok) => t
    rule("cast_expr", "unary")
    rule("cast_expr", "LPAREN type_name RPAREN cast_expr") <| $(t : LrTok; tn : int; r : LrTok; a : int) => set_ab(p, mk(p, NK.E_CAST, t), tn, a)
    rule("binary", "cast_expr")
    rule("binary", "binary OROR binary") <| $(a : int; t : LrTok; b : int) => bin(p, a, t, b)
    rule("binary", "binary ANDAND binary") <| $(a : int; t : LrTok; b : int) => bin(p, a, t, b)
    rule("binary", "binary PIPE binary") <| $(a : int; t : LrTok; b : int) => bin(p, a, t, b)
    rule("binary", "binary CARET binary") <| $(a : int; t : LrTok; b : int) => bin(p, a, t, b)
    rule("binary", "binary AMP binary") <| $(a : int; t : LrTok; b : int) => bin(p, a, t, b)
    rule("binary", "binary EQ binary") <| $(a : int; t : LrTok; b : int) => bin(p, a, t, b)
    rule("binary", "binary NE binary") <| $(a : int; t : LrTok; b : int) => bin(p, a, t, b)
    rule("binary", "binary LT binary") <| $(a : int; t : LrTok; b : int) => bin(p, a, t, b)
    rule("binary", "binary GT binary") <| $(a : int; t : LrTok; b : int) => bin(p, a, t, b)
    rule("binary", "binary LE binary") <| $(a : int; t : LrTok; b : int) => bin(p, a, t, b)
    rule("binary", "binary GE binary") <| $(a : int; t : LrTok; b : int) => bin(p, a, t, b)
    rule("binary", "binary SHL binary") <| $(a : int; t : LrTok; b : int) => bin(p, a, t, b)
    rule("binary", "binary SHR binary") <| $(a : int; t : LrTok; b : int) => bin(p, a, t, b)
    rule("binary", "binary PLUS binary") <| $(a : int; t : LrTok; b : int) => bin(p, a, t, b)
    rule("binary", "binary MINUS binary") <| $(a : int; t : LrTok; b : int) => bin(p, a, t, b)
    rule("binary", "binary STAR binary") <| $(a : int; t : LrTok; b : int) => bin(p, a, t, b)
    rule("binary", "binary SLASH binary") <| $(a : int; t : LrTok; b : int) => bin(p, a, t, b)
    rule("binary", "binary PERCENT binary") <| $(a : int; t : LrTok; b : int) => bin(p, a, t, b)
    rule("cond_expr", "binary")
    rule("cond_expr", "binary QUESTION expr COLON cond_expr") <| $(c : int; q : LrTok; a : int; k : LrTok; b : int) => cond(p, c, a, b)
    rule("cond_expr", "binary QUESTION COLON cond_expr") <| $(c : int; q : LrTok; k : LrTok; b : int) => cond(p, c, -1, b)
    rule("assign_expr", "cond_expr")
    rule("assign_expr", "unary assign_op assign_expr") <| $(a : int; t : LrTok; b : int) => assign(p, a, t, b)
    rule("assign_op", "ASSIGN") <| $(t : LrTok) => t
    rule("assign_op", "MUL_ASSIGN") <| $(t : LrTok) => t
    rule("assign_op", "DIV_ASSIGN") <| $(t : LrTok) => t
    rule("assign_op", "MOD_ASSIGN") <| $(t : LrTok) => t
    rule("assign_op", "ADD_ASSIGN") <| $(t : LrTok) => t
    rule("assign_op", "SUB_ASSIGN") <| $(t : LrTok) => t
    rule("assign_op", "SHL_ASSIGN") <| $(t : LrTok) => t
    rule("assign_op", "SHR_ASSIGN") <| $(t : LrTok) => t
    rule("assign_op", "AND_ASSIGN") <| $(t : LrTok) => t
    rule("assign_op", "XOR_ASSIGN") <| $(t : LrTok) => t
    rule("assign_op", "OR_ASSIGN") <| $(t : LrTok) => t
    rule("expr", "assign_expr")
    rule("expr", "expr COMMA assign_expr") <| $(a : int; t : LrTok; b : int) => bin(p, a, t, b)
    rule("const_expr", "cond_expr") <| $(n : int) => n

    // ---- attributes and asm labels (before the specifiers: an attribute that opens a
    // parenthesized declarator is read as the declarator's, as RD reads it)
    rule("attributes", "attribute") <| $(a : int) => a
    rule("attributes", "attributes attribute") <| $(l, a : int) => cat(p, l, a)
    rule("attribute", "ATTRIBUTE LPAREN LPAREN attr_list RPAREN RPAREN") <| $(t : LrTok; l1 : LrTok; l2 : LrTok; l : int2; r1 : LrTok; r2 : LrTok) => node1(p, NK.ATTRIBUTE, t, l.x)
    rule("attr_list", "attr_or_none") <| $(a : int) => one(p, a)
    rule("attr_list", "attr_list COMMA attr_or_none") <| $(l : int2; c : LrTok; a : int) => more(p, l, a)
    rule("attr_or_none", "") <| $() => -1
    rule("attr_or_none", "attr_name") <| $(t : LrTok) => attr(p, t, -1, 0)
    rule("attr_or_none", "attr_name LPAREN RPAREN") <| $(t : LrTok; l : LrTok; r : LrTok) => attr(p, t, -1, 1)
    rule("attr_or_none", "attr_name LPAREN args RPAREN") <| $(t : LrTok; l : LrTok; a : int2; r : LrTok) => attr(p, t, a.x, 1)
    rule("attr_name", "IDENTIFIER") <| $(t : LrTok) => t
    rule("attr_name", "TYPEDEF_NAME") <| $(t : LrTok) => t
    rule("attr_name", "CONST") <| $(t : LrTok) => t
    rule("asm_label", "ASM LPAREN string_lit RPAREN") <| $(t : LrTok; l : LrTok; s : int; r : LrTok) => node1(p, NK.ASM_LABEL, t, s)

    // ---- declarations
    rule("declaration", "decl_specs SEMI") <| $(s : int2; t : LrTok) => decl(p, s, -1)
    rule("declaration", "decl_specs init_decls SEMI") <| $(s : int2; l : int2; t : LrTok) => decl(p, s, l.x)
    rule("declaration", "static_assert")
    rule("static_assert", "STATIC_ASSERT LPAREN const_expr COMMA string_lit RPAREN SEMI") <| $(t : LrTok; l : LrTok; e : int; c : LrTok; s : int; r : LrTok; k : LrTok) => set_ab(p, mk(p, NK.STATIC_ASSERT, t), e, s)
    rule("static_assert", "STATIC_ASSERT LPAREN const_expr RPAREN SEMI") <| $(t : LrTok; l : LrTok; e : int; r : LrTok; k : LrTok) => set_ab(p, mk(p, NK.STATIC_ASSERT, t), e, -1)
    rule("decl_specs", "decl_spec") <| $(s : int) => one(p, s)
    rule("decl_specs", "decl_specs decl_spec") <| $(l : int2; s : int) => more(p, l, s)
    rule("decl_spec", "storage_kw") <| $(t : LrTok) => kw(p, t)
    rule("decl_spec", "spec_qual")
    rule("storage_kw", "TYPEDEF") <| $(t : LrTok) => t
    rule("storage_kw", "EXTERN") <| $(t : LrTok) => t
    rule("storage_kw", "STATIC") <| $(t : LrTok) => t
    rule("storage_kw", "AUTO") <| $(t : LrTok) => t
    rule("storage_kw", "REGISTER") <| $(t : LrTok) => t
    rule("storage_kw", "THREAD_LOCAL") <| $(t : LrTok) => t
    rule("storage_kw", "INLINE") <| $(t : LrTok) => t
    rule("storage_kw", "NORETURN") <| $(t : LrTok) => t
    rule("spec_qual", "type_kw") <| $(t : LrTok) => kw(p, t)
    rule("spec_qual", "qualifier") <| $(t : LrTok) => kw(p, t)
    rule("spec_qual", "EXTENSION") <| $(t : LrTok) => kw(p, t)
    rule("spec_qual", "TYPEDEF_NAME") <| $(t : LrTok) => node1(p, NK.SPEC_TYPEDEF_NAME, t, sym(p, t))
    rule("spec_qual", "record_spec")
    rule("spec_qual", "enum_spec")
    rule("spec_qual", "TYPEOF LPAREN type_name RPAREN") <| $(t : LrTok; l : LrTok; tn : int; r : LrTok) => node1(p, NK.SPEC_TYPEOF_TYPE, t, tn)
    rule("spec_qual", "TYPEOF LPAREN expr RPAREN") <| $(t : LrTok; l : LrTok; e : int; r : LrTok) => node1(p, NK.SPEC_TYPEOF_EXPR, t, e)
    rule("spec_qual", "ALIGNAS LPAREN type_name RPAREN") <| $(t : LrTok; l : LrTok; tn : int; r : LrTok) => node1(p, NK.SPEC_ALIGNAS_TYPE, t, tn)
    rule("spec_qual", "ALIGNAS LPAREN const_expr RPAREN") <| $(t : LrTok; l : LrTok; e : int; r : LrTok) => node1(p, NK.SPEC_ALIGNAS_EXPR, t, e)
    rule("spec_qual", "attribute")
    rule("type_kw", "VOID") <| $(t : LrTok) => t
    rule("type_kw", "CHAR") <| $(t : LrTok) => t
    rule("type_kw", "SHORT") <| $(t : LrTok) => t
    rule("type_kw", "INT") <| $(t : LrTok) => t
    rule("type_kw", "LONG") <| $(t : LrTok) => t
    rule("type_kw", "FLOAT") <| $(t : LrTok) => t
    rule("type_kw", "DOUBLE") <| $(t : LrTok) => t
    rule("type_kw", "SIGNED") <| $(t : LrTok) => t
    rule("type_kw", "UNSIGNED") <| $(t : LrTok) => t
    rule("type_kw", "BOOL") <| $(t : LrTok) => t
    rule("type_kw", "COMPLEX") <| $(t : LrTok) => t
    rule("type_kw", "IMAGINARY") <| $(t : LrTok) => t
    rule("qualifier", "CONST") <| $(t : LrTok) => t
    rule("qualifier", "VOLATILE") <| $(t : LrTok) => t
    rule("qualifier", "RESTRICT") <| $(t : LrTok) => t
    rule("qualifier", "ATOMIC") <| $(t : LrTok) => t
    rule("spec_quals", "spec_qual") <| $(s : int) => one(p, s)
    rule("spec_quals", "spec_quals spec_qual") <| $(l : int2; s : int) => more(p, l, s)
    rule("init_decls", "init_decl") <| $(d : int) => one(p, d)
    rule("init_decls", "init_decls COMMA init_decl") <| $(l : int2; c : LrTok; d : int) => more(p, l, d)
    rule("init_decl", "decl_head")
    rule("init_decl", "decl_head ASSIGN initializer") <| $(h : int; t : LrTok; i : int) {
        p.lexer.ast.nodes[h].b = i
        return h
    }
    rule("decl_head", "declarator") <| $(d : int) => head(p, d, -1, -1)
    rule("decl_head", "declarator asm_label") <| $(d, l : int) => head(p, d, l, -1)
    rule("decl_head", "declarator attributes") <| $(d, a : int) => head(p, d, -1, a)
    rule("decl_head", "declarator asm_label attributes") <| $(d, l, a : int) => head(p, d, l, a)
    rule("function_definition", "decl_specs decl_head compound_statement") <| $(s : int2; h, b : int) => func_def(p, s, h, -1, b)
    rule("function_definition", "decl_specs decl_head knr_decls compound_statement") <| $(s : int2; h : int; k : int2; b : int) => func_def(p, s, h, k.x, b)
    rule("knr_decls", "declaration") <| $(d : int) => one(p, d)
    rule("knr_decls", "knr_decls declaration") <| $(l : int2; d : int) => more(p, l, d)

    // ---- struct, union, enum
    rule("record_head", "STRUCT") <| $(t : LrTok) => kw_record(p, t, -1)
    rule("record_head", "UNION") <| $(t : LrTok) => kw_record(p, t, -1)
    rule("record_head", "STRUCT attributes") <| $(t : LrTok; a : int) => kw_record(p, t, a)
    rule("record_head", "UNION attributes") <| $(t : LrTok; a : int) => kw_record(p, t, a)
    rule("record_spec", "record_head IDENTIFIER") <| $(h : int; t : LrTok) => record(p, h, sym(p, t), int2(-1, 0), -1)
    rule("record_spec", "record_head IDENTIFIER record_body") <| $(h : int; t : LrTok; b : int2) => record(p, h, sym(p, t), b, -1)
    rule("record_spec", "record_head IDENTIFIER record_body attributes") <| $(h : int; t : LrTok; b : int2; a : int) => record(p, h, sym(p, t), b, a)
    rule("record_spec", "record_head record_body") <| $(h : int; b : int2) => record(p, h, -1, b, -1)
    rule("record_spec", "record_head record_body attributes") <| $(h : int; b : int2; a : int) => record(p, h, -1, b, a)
    rule("record_body", "LBRACE RBRACE") <| $(l : LrTok; r : LrTok) => int2(-1, 1)
    rule("record_body", "LBRACE members RBRACE") <| $(l : LrTok; m : int2; r : LrTok) => int2(m.x, 1)
    rule("members", "member_entry") <| $(m : int) => one(p, m)
    rule("members", "members member_entry") <| $(l : int2; m : int) => more(p, l, m)
    rule("member_entry", "SEMI") <| $(t : LrTok) => -1
    rule("member_entry", "static_assert")
    rule("member_entry", "spec_quals SEMI") <| $(s : int2; t : LrTok) => set_ab(p, mk_at(p, NK.MEMBER_DECL, s.x), s.x, -1)
    rule("member_entry", "spec_quals member_decls SEMI") <| $(s : int2; l : int2; t : LrTok) => set_ab(p, mk_at(p, NK.MEMBER_DECL, s.x), s.x, l.x)
    rule("member_decls", "member_decl") <| $(m : int) => one(p, m)
    rule("member_decls", "member_decls COMMA member_decl") <| $(l : int2; c : LrTok; m : int) => more(p, l, m)
    rule("member_decl", "member_core")
    rule("member_decl", "member_core attributes") <| $(m, a : int) {
        p.lexer.ast.nodes[m].c = a
        return m
    }
    rule("member_core", "declarator") <| $(d : int) => member(p, d, -1, -1)
    rule("member_core", "declarator COLON const_expr") <| $(d : int; c : LrTok; w : int) => member(p, d, w, -1)
    rule("member_core", "COLON const_expr") <| $(c : LrTok; w : int) => set_ab(p, mk(p, NK.MEMBER_DECLARATOR, c), -1, w)
    rule("enum_head", "ENUM") <| $(t : LrTok) => set_ab(p, mk(p, NK.SPEC_ENUM, t), -1, -1)
    rule("enum_head", "ENUM attributes") <| $(t : LrTok; a : int) => enum_attrs(p, set_ab(p, mk(p, NK.SPEC_ENUM, t), -1, -1), a)
    rule("enum_spec", "enum_head IDENTIFIER") <| $(h : int; t : LrTok) => enum_body(p, h, sym(p, t), int2(-1, 0), -1)
    rule("enum_spec", "enum_head IDENTIFIER enum_body") <| $(h : int; t : LrTok; b : int2) => enum_body(p, h, sym(p, t), b, -1)
    rule("enum_spec", "enum_head IDENTIFIER enum_body attributes") <| $(h : int; t : LrTok; b : int2; a : int) => enum_body(p, h, sym(p, t), b, a)
    rule("enum_spec", "enum_head enum_body") <| $(h : int; b : int2) => enum_body(p, h, -1, b, -1)
    rule("enum_spec", "enum_head enum_body attributes") <| $(h : int; b : int2; a : int) => enum_body(p, h, -1, b, a)
    rule("enum_body", "LBRACE RBRACE") <| $(l : LrTok; r : LrTok) => int2(-1, 1)
    rule("enum_body", "LBRACE enumerators RBRACE") <| $(l : LrTok; e : int2; r : LrTok) => int2(e.x, 1)
    rule("enum_body", "LBRACE enumerators COMMA RBRACE") <| $(l : LrTok; e : int2; c : LrTok; r : LrTok) => int2(e.x, 1)
    rule("enumerators", "enumerator") <| $(e : int) => one(p, e)
    rule("enumerators", "enumerators COMMA enumerator") <| $(l : int2; c : LrTok; e : int) => more(p, l, e)
    rule("enumerator", "IDENTIFIER") <| $(t : LrTok) => enumerator(p, t, -1, -1)
    rule("enumerator", "IDENTIFIER ASSIGN const_expr") <| $(t : LrTok; a : LrTok; e : int) => enumerator(p, t, -1, e)
    rule("enumerator", "IDENTIFIER attributes") <| $(t : LrTok; at : int) => enumerator(p, t, at, -1)
    rule("enumerator", "IDENTIFIER attributes ASSIGN const_expr") <| $(t : LrTok; at : int; a : LrTok; e : int) => enumerator(p, t, at, e)

    // ---- declarators
    rule("declarator", "direct_decl")
    rule("declarator", "pointer direct_decl") <| $(c : int2; d : int) => with_pointer(p, c, d)
    rule("pointer", "STAR") <| $(t : LrTok) => ptr(p, t, -1, int2(-1, -1))
    rule("pointer", "STAR ptr_quals") <| $(t : LrTok; q : int2) => ptr(p, t, q.x, int2(-1, -1))
    rule("pointer", "STAR pointer") <| $(t : LrTok; r : int2) => ptr(p, t, -1, r)
    rule("pointer", "STAR ptr_quals pointer") <| $(t : LrTok; q : int2; r : int2) => ptr(p, t, q.x, r)
    rule("ptr_quals", "ptr_qual") <| $(q : int) => one(p, q)
    rule("ptr_quals", "ptr_quals ptr_qual") <| $(l : int2; q : int) => more(p, l, q)
    rule("ptr_qual", "qualifier") <| $(t : LrTok) => kw(p, t)
    rule("ptr_qual", "attribute")
    rule("direct_decl", "IDENTIFIER") <| $(t : LrTok) => node1(p, NK.D_NAME, t, sym(p, t))
    rule("direct_decl", "LPAREN declarator RPAREN") <| $(t : LrTok; d : int; r : LrTok) => paren_decl(p, t, -1, d)
    rule("direct_decl", "LPAREN attributes declarator RPAREN") <| $(t : LrTok; a, d : int; r : LrTok) => paren_decl(p, t, a, d)
    rule("direct_decl", "direct_decl array_suffix") <| $(d, s : int) => suffix(p, d, s)
    rule("direct_decl", "direct_decl func_suffix") <| $(d, s : int) => suffix(p, d, s)
    rule("array_suffix", "LBRACKET RBRACKET") <| $(t : LrTok; r : LrTok) => array_node(p, t, 0, -1, -1)
    rule("array_suffix", "LBRACKET assign_expr RBRACKET") <| $(t : LrTok; e : int; r : LrTok) => array_node(p, t, 0, -1, e)
    rule("array_suffix", "LBRACKET ptr_quals RBRACKET") <| $(t : LrTok; q : int2; r : LrTok) => array_node(p, t, 0, q.x, -1)
    rule("array_suffix", "LBRACKET ptr_quals assign_expr RBRACKET") <| $(t : LrTok; q : int2; e : int; r : LrTok) => array_node(p, t, 0, q.x, e)
    rule("array_suffix", "LBRACKET ptr_quals STAR RBRACKET") <| $(t : LrTok; q : int2; s : LrTok; r : LrTok) => array_node(p, t, 2, q.x, -1)
    rule("array_suffix", "LBRACKET STAR RBRACKET") <| $(t : LrTok; s : LrTok; r : LrTok) => array_node(p, t, 2, -1, -1)
    rule("array_suffix", "LBRACKET STATIC assign_expr RBRACKET") <| $(t : LrTok; s : LrTok; e : int; r : LrTok) => array_node(p, t, 1, -1, e)
    rule("array_suffix", "LBRACKET STATIC ptr_quals assign_expr RBRACKET") <| $(t : LrTok; s : LrTok; q : int2; e : int; r : LrTok) => array_node(p, t, 1, q.x, e)
    rule("array_suffix", "LBRACKET ptr_quals STATIC assign_expr RBRACKET") <| $(t : LrTok; q : int2; s : LrTok; e : int; r : LrTok) => array_node(p, t, 1, q.x, e)
    rule("func_suffix", "LPAREN RPAREN") <| $(t : LrTok; r : LrTok) => func_node(p, t, 0, -1)
    rule("func_suffix", "LPAREN params RPAREN") <| $(t : LrTok; l : int2; r : LrTok) => func_node(p, t, l.y, l.x)
    rule("func_suffix", "LPAREN ELLIPSIS RPAREN") <| $(t : LrTok; e : LrTok; r : LrTok) => func_node(p, t, 1, -1)
    rule("func_suffix", "LPAREN ident_list RPAREN") <| $(t : LrTok; l : int2; r : LrTok) => func_node(p, t, 2, l.x)
    rule("params", "param_list") <| $(l : int2) => int2(l.x, 0)
    rule("params", "param_list COMMA ELLIPSIS") <| $(l : int2; c : LrTok; e : LrTok) => int2(l.x, 1)
    rule("param_list", "param") <| $(n : int) => one(p, n)
    rule("param_list", "param_list COMMA param") <| $(l : int2; c : LrTok; n : int) => more(p, l, n)
    rule("param", "decl_specs") <| $(s : int2) => param(p, s, -1)
    rule("param", "decl_specs declarator") <| $(s : int2; d : int) => param(p, s, d)
    rule("param", "decl_specs abs_decl") <| $(s : int2; d : int) => param(p, s, d)
    rule("ident_list", "IDENTIFIER") <| $(t : LrTok) => one(p, node1(p, NK.IDENT_PARAM, t, sym(p, t)))
    rule("ident_list", "ident_list COMMA IDENTIFIER") <| $(l : int2; c : LrTok; t : LrTok) => more(p, l, node1(p, NK.IDENT_PARAM, t, sym(p, t)))
    rule("type_name", "spec_quals") <| $(s : int2) => type_name(p, s, -1)
    rule("type_name", "spec_quals abs_decl") <| $(s : int2; d : int) => type_name(p, s, d)
    rule("abs_decl", "pointer") <| $(c : int2) => c.x
    rule("abs_decl", "pointer direct_abs") <| $(c : int2; d : int) => with_pointer(p, c, d)
    rule("abs_decl", "direct_abs")
    rule("direct_abs", "LPAREN abs_decl RPAREN") <| $(t : LrTok; d : int; r : LrTok) => paren_decl(p, t, -1, d)
    rule("direct_abs", "LPAREN attributes abs_decl RPAREN") <| $(t : LrTok; a, d : int; r : LrTok) => paren_decl(p, t, a, d)
    rule("direct_abs", "array_suffix")
    rule("direct_abs", "func_suffix")
    rule("direct_abs", "direct_abs array_suffix") <| $(d, s : int) => suffix(p, d, s)
    rule("direct_abs", "direct_abs func_suffix") <| $(d, s : int) => suffix(p, d, s)

    // ---- initializers
    rule("initializer", "assign_expr") <| $(n : int) => n
    rule("initializer", "init_braces")
    rule("init_braces", "LBRACE RBRACE") <| $(t : LrTok; r : LrTok) => node1(p, NK.INIT_LIST, t, -1)
    rule("init_braces", "LBRACE init_items RBRACE") <| $(t : LrTok; l : int2; r : LrTok) => node1(p, NK.INIT_LIST, t, l.x)
    rule("init_braces", "LBRACE init_items COMMA RBRACE") <| $(t : LrTok; l : int2; c : LrTok; r : LrTok) => node1(p, NK.INIT_LIST, t, l.x)
    rule("init_items", "init_item") <| $(i : int) => one(p, i)
    rule("init_items", "init_items COMMA init_item") <| $(l : int2; c : LrTok; i : int) => more(p, l, i)
    rule("init_item", "initializer") <| $(v : int) => init_item(p, int2(-1, -1), v)
    rule("init_item", "designators ASSIGN initializer") <| $(d : int2; t : LrTok; v : int) => init_item(p, d, v)
    rule("designators", "designator") <| $(d : int) => one(p, d)
    rule("designators", "designators designator") <| $(l : int2; d : int) => more(p, l, d)
    rule("designator", "DOT IDENTIFIER") <| $(t : LrTok; n : LrTok) => node1(p, NK.DESIG_FIELD, t, sym(p, n))
    rule("designator", "LBRACKET const_expr RBRACKET") <| $(t : LrTok; e : int; r : LrTok) => desig_index(p, t, e, -1)
    rule("designator", "LBRACKET const_expr ELLIPSIS const_expr RBRACKET") <| $(t : LrTok; a : int; e : LrTok; b : int; r : LrTok) => desig_index(p, t, a, b)

    // ---- statements
    rule("statement", "stmt")
    rule("statement", "attributes stmt") <| $(a, s : int) => set_ab(p, mk_at(p, NK.S_ATTRIBUTED, a), a, s)
    rule("stmt", "IDENTIFIER COLON stmt") <| $(t : LrTok; c : LrTok; s : int) => label_stmt(p, t, -1, s)
    rule("stmt", "IDENTIFIER COLON attributes stmt") <| $(t : LrTok; c : LrTok; a, s : int) => label_stmt(p, t, a, s)
    rule("stmt", "CASE const_expr COLON statement") <| $(t : LrTok; e : int; c : LrTok; s : int) => case_stmt(p, t, e, -1, s)
    rule("stmt", "CASE const_expr ELLIPSIS const_expr COLON statement") <| $(t : LrTok; a : int; e : LrTok; b : int; c : LrTok; s : int) => case_stmt(p, t, a, b, s)
    rule("stmt", "DEFAULT COLON statement") <| $(t : LrTok; c : LrTok; s : int) => node1(p, NK.S_DEFAULT, t, s)
    rule("stmt", "compound_statement")
    rule("stmt", "SEMI") <| $(t : LrTok) => mk(p, NK.S_NULL, t)
    rule("stmt", "expr SEMI") <| $(e : int; t : LrTok) => expr_stmt(p, e)
    rule("stmt", "IF LPAREN expr RPAREN statement") <| $(t : LrTok; l : LrTok; c : int; r : LrTok; a : int) => if_stmt(p, t, c, a, -1)
    rule("stmt", "IF LPAREN expr RPAREN statement ELSE statement") <| $(t : LrTok; l : LrTok; c : int; r : LrTok; a : int; e : LrTok; b : int) => if_stmt(p, t, c, a, b)
    rule("stmt", "SWITCH LPAREN expr RPAREN statement") <| $(t : LrTok; l : LrTok; c : int; r : LrTok; s : int) => set_ab(p, mk(p, NK.S_SWITCH, t), c, s)
    rule("stmt", "WHILE LPAREN expr RPAREN statement") <| $(t : LrTok; l : LrTok; c : int; r : LrTok; s : int) => set_ab(p, mk(p, NK.S_WHILE, t), c, s)
    rule("stmt", "DO statement WHILE LPAREN expr RPAREN SEMI") <| $(t : LrTok; s : int; w : LrTok; l : LrTok; c : int; r : LrTok; k : LrTok) => set_ab(p, mk(p, NK.S_DO, t), s, c)
    rule("stmt", "FOR LPAREN for_init opt_expr SEMI opt_expr RPAREN statement") <| $(t : LrTok; l : LrTok; i, c : int; k : LrTok; s : int; r : LrTok; b : int) => for_stmt(p, t, i, c, s, b)
    rule("stmt", "GOTO IDENTIFIER SEMI") <| $(t : LrTok; n : LrTok; k : LrTok) => node1(p, NK.S_GOTO, t, sym(p, n))
    rule("stmt", "GOTO STAR expr SEMI") <| $(t : LrTok; s : LrTok; e : int; k : LrTok) => node1(p, NK.S_GOTO_PTR, t, e)
    rule("stmt", "CONTINUE SEMI") <| $(t : LrTok; k : LrTok) => mk(p, NK.S_CONTINUE, t)
    rule("stmt", "BREAK SEMI") <| $(t : LrTok; k : LrTok) => mk(p, NK.S_BREAK, t)
    rule("stmt", "RETURN SEMI") <| $(t : LrTok; k : LrTok) => mk(p, NK.S_RETURN, t)
    rule("stmt", "RETURN expr SEMI") <| $(t : LrTok; e : int; k : LrTok) => node1(p, NK.S_RETURN, t, e)
    rule("stmt", "asm_statement")
    rule("for_init", "SEMI") <| $(t : LrTok) => -1
    rule("for_init", "expr SEMI") <| $(e : int; t : LrTok) => expr_stmt(p, e)
    rule("for_init", "declaration")
    rule("opt_expr", "") <| $() => -1
    rule("opt_expr", "expr")
    rule("compound_statement", "LBRACE RBRACE") <| $(t : LrTok; r : LrTok) => mk(p, NK.S_COMPOUND, t)
    rule("compound_statement", "LBRACE block_items RBRACE") <| $(t : LrTok; l : int2; r : LrTok) => node1(p, NK.S_COMPOUND, t, l.x)
    rule("block_items", "block_item") <| $(i : int) => one(p, i)
    rule("block_items", "block_items block_item") <| $(l : int2; i : int) => more(p, l, i)
    rule("block_item", "declaration") <| $(n : int) => n
    rule("block_item", "stmt")
    rule("asm_statement", "ASM LPAREN string_lit asm_tail RPAREN SEMI") <| $(t : LrTok; l : LrTok; s : int; tail : int3; r : LrTok; k : LrTok) => asm_stmt(p, t, 0, s, tail)
    rule("asm_statement", "ASM asm_quals LPAREN string_lit asm_tail RPAREN SEMI") <| $(t : LrTok; q : int; l : LrTok; s : int; tail : int3; r : LrTok; k : LrTok) => asm_stmt(p, t, q, s, tail)
    rule("asm_quals", "asm_qual")
    rule("asm_quals", "asm_quals asm_qual") <| $(a, b : int) => a | b
    rule("asm_qual", "VOLATILE") <| $(t : LrTok) => 1
    rule("asm_qual", "INLINE") <| $(t : LrTok) => 2
    rule("asm_tail", "") <| $() => int3(-1, -1, -1)
    rule("asm_tail", "COLON asm_operands") <| $(c : LrTok; o : int2) => int3(o.x, -1, -1)
    rule("asm_tail", "COLON asm_operands COLON asm_operands") <| $(c : LrTok; o : int2; c2 : LrTok; i : int2) => int3(o.x, i.x, -1)
    rule("asm_tail", "COLON asm_operands COLON asm_operands COLON asm_clobbers") <| $(c : LrTok; o : int2; c2 : LrTok; i : int2; c3 : LrTok; k : int2) => int3(o.x, i.x, k.x)
    rule("asm_operands", "") <| $() => int2(-1, -1)
    rule("asm_operands", "asm_operand_list")
    rule("asm_operand_list", "asm_operand") <| $(o : int) => one(p, o)
    rule("asm_operand_list", "asm_operand_list COMMA asm_operand") <| $(l : int2; c : LrTok; o : int) => more(p, l, o)
    rule("asm_operand", "string_lit LPAREN expr RPAREN") <| $(s : int; l : LrTok; e : int; r : LrTok) => asm_operand(p, l, -1, s, e)
    rule("asm_operand", "LBRACKET IDENTIFIER RBRACKET string_lit LPAREN expr RPAREN") <| $(b : LrTok; n : LrTok; r1 : LrTok; s : int; l : LrTok; e : int; r : LrTok) => asm_operand(p, b, sym(p, n), s, e)
    rule("asm_clobbers", "") <| $() => int2(-1, -1)
    rule("asm_clobbers", "asm_clobber_list")
    rule("asm_clobber_list", "string_lit") <| $(s : int) => one(p, s)
    rule("asm_clobber_list", "asm_clobber_list COMMA string_lit") <| $(l : int2; c : LrTok; s : int) => more(p, l, s)
}

def private kw_record(var p : LrParser; t : LrTok; attrs : int) : int {
    let n = mk(p, NK.SPEC_RECORD, t)
    p.lexer.ast.nodes[n].op = t.kind
    p.lexer.ast.nodes[n].d = attrs
    return n
}

def private enum_attrs(var p : LrParser; h, attrs : int) : int {
    p.lexer.ast.nodes[h].d = attrs
    return h
}

def private enum_body(var p : LrParser; h, tag : int; body : int2; attrs : int) : int {
    p.lexer.ast.nodes[h].a = tag
    p.lexer.ast.nodes[h].b = body.x
    p.lexer.ast.nodes[h].c = body.y
    p.lexer.ast.nodes[h].d = cat(p, p.lexer.ast.nodes[h].d, attrs)
    return h
}

//! Parse the lexed unit in `p.lexer.src` into `p.lexer.ast`.
def lr_parse(var p : LrParser) {
    p.failed = false
    p.err = ""
    p.line = 0
    p.col = 0
    p.lexer.failed = false
    p.lexer.err = ""
    p.lexer.pos = 0
    p.lexer.eof = length(p.lexer.src.toks) - 1
    p.lexer.ts = false
    p.lexer.typedef_flag = false
    p.lexer.tag_pending = false
    p.lexer.prev_kind = 0
    p.lexer.pending_fn = -1
    p.lexer.parens |> clear()
    p.lexer.braces |> clear()
    p.lexer.ast.nodes |> clear()
    p.lexer.ast.nodes |> reserve(length(p.lexer.src.toks))
    p.lexer.ast.root = -1
    p.lexer.sc <- file_scopes(p.lexer.src.names)
    lr_c(p)
}
