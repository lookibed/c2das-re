options gen2
options indenting = 4

module c1_rd shared public

// Candidate RD: the C99 grammar with the GNU forms Dumper A reads, by recursive descent over the
// token array, building the shared AST (`c1_ast`). The typedef-name ambiguity is decided where it
// arises: a word is a type name when the scope table binds it as a typedef and no type specifier
// came before it in the specifier list. Scopes are exact: a block, a `for` statement, a prototype's
// parameter list, and a function body that sees its declarator's parameters. Binary operators go by
// precedence climbing. Every construct it does not take is an error at its token, `file:line:col:
// what`; the first error ends the parse.

require strings
require math
require c1_ast public

struct Rd {
    src : Source
    ast : Ast
    sc : Scopes
    pos : int
    eof : int
    failed : bool
    err : string
}

//! The kind of the token at the cursor.
def private kind(p : Rd) : int => p.src.toks[p.pos].kind

def private kind_at(p : Rd; ahead : int) : int => p.src.toks[min(p.pos + ahead, p.eof)].kind

def private fail(var p : Rd; msg : string) {
    if (!p.failed) {
        p.failed = true
        let tok = p.src.toks[p.pos]
        let got = tok.kind == int(TK.EOF) ? "end of input" : "'{tok_text(p.src, p.pos)}'"
        p.err = "{p.src.files[tok.file]}:{tok.line}:{tok.col}: {msg}, got {got}"
    }
    p.pos = p.eof
}

def private refuse(var p : Rd; what : string) {
    if (!p.failed) {
        p.failed = true
        p.err = "{tok_where(p.src, p.pos)}: {what} is not supported"
    }
    p.pos = p.eof
}

//! Take the token of kind `k` or fail naming it.
def private take(var p : Rd; k : int) : int {
    if (p.src.toks[p.pos].kind == k) {
        p.pos++
        return p.pos - 1
    }
    fail(p, "expected '{kind_name(k)}'")
    return p.eof
}

def private accept(var p : Rd; k : int) : bool {
    if (p.src.toks[p.pos].kind == k) {
        p.pos++
        return true
    }
    return false
}

def private node(var p : Rd; kind : NK; t : int) : int => add_node(p.ast, p.src.toks, kind, t)

def private node_at(var p : Rd; kind : NK; at : int) : int => add_node_at(p.ast, kind, at)

//! Whether the word at token `t` is a typedef name in scope.
def private typedef_at(p : Rd; t : int) : bool {
    let tok = p.src.toks[t]
    return tok.kind == int(TK.IDENTIFIER) && is_typedef_name(p.sc, tok.sym)
}

def private is_type_keyword(k : int) : bool {
    return (k == int(TK.VOID) || k == int(TK.CHAR) || k == int(TK.SHORT) || k == int(TK.INT) || k == int(TK.LONG)
        || k == int(TK.FLOAT) || k == int(TK.DOUBLE) || k == int(TK.SIGNED) || k == int(TK.UNSIGNED)
        || k == int(TK.BOOL) || k == int(TK.COMPLEX) || k == int(TK.IMAGINARY))
}

def private is_qualifier(k : int) : bool => k == int(TK.CONST) || k == int(TK.VOLATILE) || k == int(TK.RESTRICT) || k == int(TK.ATOMIC)

def private is_storage_or_function(k : int) : bool {
    return (k == int(TK.TYPEDEF) || k == int(TK.EXTERN) || k == int(TK.STATIC) || k == int(TK.AUTO)
        || k == int(TK.REGISTER) || k == int(TK.THREAD_LOCAL) || k == int(TK.INLINE) || k == int(TK.NORETURN))
}

//! Whether token `t` can start a type name: a specifier or qualifier keyword, a tag keyword, typeof,
//! an attribute, or a typedef name.
def private type_start_at(p : Rd; t : int) : bool {
    let k = p.src.toks[t].kind
    return (is_type_keyword(k) || is_qualifier(k) || k == int(TK.STRUCT) || k == int(TK.UNION) || k == int(TK.ENUM)
        || k == int(TK.TYPEOF) || k == int(TK.ATTRIBUTE) || k == int(TK.ALIGNAS) || typedef_at(p, t))
}

//! Whether token `t` can start a declaration in a block.
def private decl_start_at(p : Rd; t : int) : bool {
    let k = p.src.toks[t].kind
    if (k == int(TK.EXTENSION)) {
        return decl_start_at(p, min(t + 1, p.eof))
    }
    if (typedef_at(p, t)) {
        return p.src.toks[min(t + 1, p.eof)].kind != int(TK.COLON)
    }
    return type_start_at(p, t) || is_storage_or_function(k) || k == int(TK.STATIC_ASSERT)
}

def private refuse_unsupported_word(var p : Rd) : bool {
    let k = kind(p)
    if (k == int(TK.LABEL_KW)) {
        refuse(p, "a local label declaration (__label__)")
    } elif (k == int(TK.INT128)) {
        refuse(p, "__int128")
    } elif (k == int(TK.AUTO_TYPE)) {
        refuse(p, "__auto_type")
    } elif (k == int(TK.GENERIC)) {
        refuse(p, "a generic selection (_Generic)")
    } else {
        return false
    }
    return true
}

// ---- attributes and asm labels

//! `__attribute__((a, b(args), ...))` at the cursor: one ATTRIBUTE node of its attributes.
def private attribute(var p : Rd) : int {
    let at = take(p, int(TK.ATTRIBUTE))
    let n = node(p, NK.ATTRIBUTE, at)
    take(p, int(TK.LPAREN))
    take(p, int(TK.LPAREN))
    var attrs = empty_list()
    while (!p.failed && kind(p) != int(TK.RPAREN)) {
        if (accept(p, int(TK.COMMA))) {
            continue
        }
        let tok = p.src.toks[p.pos]
        if (tok.sym < 0) {
            fail(p, "expected an attribute name")
            return n
        }
        let a = node(p, NK.ATTR, p.pos)
        p.ast.nodes[a].a = tok.sym
        p.ast.nodes[a].c = 0
        p.pos++
        if (accept(p, int(TK.LPAREN))) {
            p.ast.nodes[a].c = 1
            var args = empty_list()
            while (!p.failed && kind(p) != int(TK.RPAREN)) {
                append(p.ast, args, assignment(p))
                if (!accept(p, int(TK.COMMA))) {
                    break
                }
            }
            take(p, int(TK.RPAREN))
            p.ast.nodes[a].b = args.head
        }
        append(p.ast, attrs, a)
    }
    take(p, int(TK.RPAREN))
    take(p, int(TK.RPAREN))
    p.ast.nodes[n].a = attrs.head
    return n
}

//! Attributes at the cursor, none or several, as a list.
def private attributes(var p : Rd) : int {
    var list = empty_list()
    while (!p.failed && kind(p) == int(TK.ATTRIBUTE)) {
        append(p.ast, list, attribute(p))
    }
    return list.head
}

//! One string literal expression: adjacent literals joined into one node.
def private string_literal(var p : Rd) : int {
    let first = take(p, int(TK.STRING_LITERAL))
    let n = node(p, NK.E_STRING, first)
    var count = 1
    while (kind(p) == int(TK.STRING_LITERAL)) {
        p.pos++
        count++
    }
    p.ast.nodes[n].a = first
    p.ast.nodes[n].b = count
    return n
}

// ---- specifiers

//! A declaration's specifiers: x = the list, y = 1 when it holds `typedef`.
def private specifiers(var p : Rd; for_type_name : bool) : int2 {
    var list = empty_list()
    var seen_type = false
    var is_typedef = 0
    while (!p.failed) {
        let k = kind(p)
        if (is_type_keyword(k)) {
            seen_type = true
        } elif (is_qualifier(k) || k == int(TK.EXTENSION)) {
            if (k == int(TK.ATOMIC) && kind_at(p, 1) == int(TK.LPAREN)) {
                refuse(p, "the _Atomic(type) specifier")
                break
            }
        } elif (is_storage_or_function(k) && !for_type_name) {
            if (k == int(TK.TYPEDEF)) {
                is_typedef = 1
            }
        } elif (k == int(TK.IDENTIFIER)) {
            if (seen_type || !typedef_at(p, p.pos)) {
                break
            }
            let n = node(p, NK.SPEC_TYPEDEF_NAME, p.pos)
            p.ast.nodes[n].a = p.src.toks[p.pos].sym
            p.pos++
            append(p.ast, list, n)
            seen_type = true
            continue
        } elif (k == int(TK.STRUCT) || k == int(TK.UNION)) {
            append(p.ast, list, record(p))
            seen_type = true
            continue
        } elif (k == int(TK.ENUM)) {
            append(p.ast, list, enum_spec(p))
            seen_type = true
            continue
        } elif (k == int(TK.TYPEOF)) {
            let at = p.pos
            p.pos++
            take(p, int(TK.LPAREN))
            var n = -1
            if (type_start_at(p, p.pos)) {
                n = node(p, NK.SPEC_TYPEOF_TYPE, at)
                p.ast.nodes[n].a = type_name(p)
            } else {
                n = node(p, NK.SPEC_TYPEOF_EXPR, at)
                p.ast.nodes[n].a = expression(p)
            }
            take(p, int(TK.RPAREN))
            append(p.ast, list, n)
            seen_type = true
            continue
        } elif (k == int(TK.ALIGNAS)) {
            let at = p.pos
            p.pos++
            take(p, int(TK.LPAREN))
            var n = -1
            if (type_start_at(p, p.pos)) {
                n = node(p, NK.SPEC_ALIGNAS_TYPE, at)
                p.ast.nodes[n].a = type_name(p)
            } else {
                n = node(p, NK.SPEC_ALIGNAS_EXPR, at)
                p.ast.nodes[n].a = conditional(p)
            }
            take(p, int(TK.RPAREN))
            append(p.ast, list, n)
            continue
        } elif (k == int(TK.ATTRIBUTE)) {
            append(p.ast, list, attribute(p))
            continue
        } else {
            if (refuse_unsupported_word(p)) {
                break
            }
            break
        }
        let n = node(p, NK.SPEC_KW, p.pos)
        p.ast.nodes[n].op = k
        p.pos++
        append(p.ast, list, n)
    }
    return int2(list.head, is_typedef)
}

//! `struct|union [attrs] [tag] [{ members }] [attrs]`.
def private record(var p : Rd) : int {
    let n = node(p, NK.SPEC_RECORD, p.pos)
    p.ast.nodes[n].op = kind(p)
    p.pos++
    var attrs = empty_list()
    append(p.ast, attrs, attributes(p))
    p.ast.nodes[n].c = 0
    if (kind(p) == int(TK.IDENTIFIER)) {
        p.ast.nodes[n].a = p.src.toks[p.pos].sym
        p.pos++
    }
    if (accept(p, int(TK.LBRACE))) {
        p.ast.nodes[n].c = 1
        var members = empty_list()
        while (!p.failed && kind(p) != int(TK.RBRACE)) {
            if (accept(p, int(TK.SEMI))) {
                continue
            }
            append(p.ast, members, member_decl(p))
        }
        take(p, int(TK.RBRACE))
        p.ast.nodes[n].b = members.head
        append(p.ast, attrs, attributes(p))
    } elif (p.ast.nodes[n].a < 0) {
        fail(p, "expected a tag or '\{' after '{kind_name(p.ast.nodes[n].op)}'")
    }
    p.ast.nodes[n].d = attrs.head
    return n
}

//! A member declaration: specifiers, then declarators with optional bit widths, then `;`.
def private member_decl(var p : Rd) : int {
    if (kind(p) == int(TK.STATIC_ASSERT)) {
        return static_assert_decl(p)
    }
    let at = p.pos
    let specs = specifiers(p, true)
    if (specs.x < 0) {
        fail(p, "expected a member declaration")
        return -1
    }
    let n = node(p, NK.MEMBER_DECL, at)
    p.ast.nodes[n].a = specs.x
    var decls = empty_list()
    while (!p.failed && kind(p) != int(TK.SEMI)) {
        var md = -1
        if (kind(p) == int(TK.COLON)) {
            md = node(p, NK.MEMBER_DECLARATOR, p.pos)
        } else {
            let d = declarator(p, 0)
            md = node_at(p, NK.MEMBER_DECLARATOR, d)
            p.ast.nodes[md].a = d
        }
        if (accept(p, int(TK.COLON))) {
            p.ast.nodes[md].b = conditional(p)
        }
        p.ast.nodes[md].c = attributes(p)
        append(p.ast, decls, md)
        if (!accept(p, int(TK.COMMA))) {
            break
        }
    }
    take(p, int(TK.SEMI))
    p.ast.nodes[n].b = decls.head
    return n
}

//! `enum [attrs] [tag] [{ enumerators [,] }] [attrs]`; each enumerator is an ordinary identifier.
def private enum_spec(var p : Rd) : int {
    let n = node(p, NK.SPEC_ENUM, p.pos)
    p.pos++
    var attrs = attributes(p)
    p.ast.nodes[n].c = 0
    if (kind(p) == int(TK.IDENTIFIER)) {
        p.ast.nodes[n].a = p.src.toks[p.pos].sym
        p.pos++
    }
    if (accept(p, int(TK.LBRACE))) {
        p.ast.nodes[n].c = 1
        var list = empty_list()
        while (!p.failed && kind(p) != int(TK.RBRACE)) {
            if (kind(p) != int(TK.IDENTIFIER)) {
                fail(p, "expected an enumerator")
                break
            }
            let e = node(p, NK.ENUMERATOR, p.pos)
            let sym = p.src.toks[p.pos].sym
            p.ast.nodes[e].a = sym
            p.pos++
            p.ast.nodes[e].c = attributes(p)
            if (accept(p, int(TK.ASSIGN))) {
                p.ast.nodes[e].b = conditional(p)
            }
            scope_declare(p.sc, sym, ORDINARY)
            append(p.ast, list, e)
            if (!accept(p, int(TK.COMMA))) {
                break
            }
        }
        take(p, int(TK.RBRACE))
        p.ast.nodes[n].b = list.head
        var all = empty_list()
        append(p.ast, all, attrs)
        append(p.ast, all, attributes(p))
        attrs = all.head
    } elif (p.ast.nodes[n].a < 0) {
        fail(p, "expected a tag or '\{' after 'enum'")
    }
    p.ast.nodes[n].d = attrs
    return n
}

// ---- declarators

//! Qualifiers and attributes after a `*` or inside `[]`.
def private pointer_qualifiers(var p : Rd) : int {
    var list = empty_list()
    while (!p.failed) {
        let k = kind(p)
        if (is_qualifier(k)) {
            let q = node(p, NK.SPEC_KW, p.pos)
            p.ast.nodes[q].op = k
            p.pos++
            append(p.ast, list, q)
        } elif (k == int(TK.ATTRIBUTE)) {
            append(p.ast, list, attribute(p))
        } else {
            break
        }
    }
    return list.head
}

//! A declarator: `mode` 0 names something, 1 is abstract, 2 either (a parameter). An abstract one
//! with nothing in it is -1.
def private declarator(var p : Rd; mode : int) : int {
    if (kind(p) == int(TK.STAR)) {
        let n = node(p, NK.D_PTR, p.pos)
        p.pos++
        p.ast.nodes[n].b = pointer_qualifiers(p)
        p.ast.nodes[n].a = declarator(p, mode)
        return n
    }
    return direct_declarator(p, mode)
}

//! Whether the `(` at the cursor opens a nested declarator rather than a parameter list.
def private nested_paren(p : Rd; mode : int) : bool {
    if (mode == 0) {
        return true
    }
    let k = kind_at(p, 1)
    if (k == int(TK.STAR) || k == int(TK.LPAREN) || k == int(TK.LBRACKET) || k == int(TK.ATTRIBUTE)) {
        return true
    }
    return mode == 2 && k == int(TK.IDENTIFIER) && !typedef_at(p, p.pos + 1)
}

def private direct_declarator(var p : Rd; mode : int) : int {
    var inner = -1
    let k = kind(p)
    if (k == int(TK.IDENTIFIER) && mode != 1) {
        inner = node(p, NK.D_NAME, p.pos)
        p.ast.nodes[inner].a = p.src.toks[p.pos].sym
        p.pos++
    } elif (k == int(TK.LPAREN) && nested_paren(p, mode)) {
        inner = node(p, NK.D_PAREN, p.pos)
        p.pos++
        p.ast.nodes[inner].b = attributes(p)
        p.ast.nodes[inner].a = declarator(p, mode)
        take(p, int(TK.RPAREN))
    } elif (mode == 0) {
        fail(p, "expected a declarator")
        return -1
    }
    while (!p.failed) {
        if (kind(p) == int(TK.LBRACKET)) {
            let n = inner >= 0 ? node_at(p, NK.D_ARRAY, inner) : node(p, NK.D_ARRAY, p.pos)
            p.pos++
            p.ast.nodes[n].a = inner
            var flags = 0
            if (accept(p, int(TK.STATIC))) {
                flags |= 1
            }
            p.ast.nodes[n].c = pointer_qualifiers(p)
            if (accept(p, int(TK.STATIC))) {
                flags |= 1
            }
            if (kind(p) == int(TK.STAR) && kind_at(p, 1) == int(TK.RBRACKET)) {
                flags |= 2
                p.pos++
            } elif (kind(p) != int(TK.RBRACKET)) {
                p.ast.nodes[n].b = assignment(p)
            }
            take(p, int(TK.RBRACKET))
            p.ast.nodes[n].op = flags
            inner = n
        } elif (kind(p) == int(TK.LPAREN)) {
            let n = inner >= 0 ? node_at(p, NK.D_FUNC, inner) : node(p, NK.D_FUNC, p.pos)
            p.pos++
            p.ast.nodes[n].a = inner
            parameters(p, n)
            take(p, int(TK.RPAREN))
            inner = n
        } else {
            break
        }
    }
    return inner
}

//! A function declarator's parameters into node `f`, in a prototype scope of their own.
def private parameters(var p : Rd; f : int) {
    var list = empty_list()
    var flags = 0
    if (kind(p) == int(TK.IDENTIFIER) && !typedef_at(p, p.pos)) {
        // an identifier list: the parameters of an old-style definition
        flags = 2
        while (!p.failed) {
            if (kind(p) != int(TK.IDENTIFIER)) {
                fail(p, "expected a parameter name")
                break
            }
            let n = node(p, NK.IDENT_PARAM, p.pos)
            p.ast.nodes[n].a = p.src.toks[p.pos].sym
            p.pos++
            append(p.ast, list, n)
            if (!accept(p, int(TK.COMMA))) {
                break
            }
        }
    } elif (kind(p) != int(TK.RPAREN)) {
        scope_open(p.sc)
        while (!p.failed) {
            if (accept(p, int(TK.ELLIPSIS))) {
                flags |= 1
                break
            }
            let at = p.pos
            let specs = specifiers(p, false)
            if (specs.x < 0) {
                fail(p, "expected a parameter declaration")
                break
            }
            let n = node(p, NK.PARAM, at)
            p.ast.nodes[n].a = specs.x
            let d = declarator(p, 2)
            p.ast.nodes[n].b = d
            scope_declare(p.sc, declarator_name(p.ast, d), ORDINARY)
            append(p.ast, list, n)
            if (!accept(p, int(TK.COMMA))) {
                break
            }
        }
        scope_close(p.sc)
    }
    p.ast.nodes[f].op = flags
    p.ast.nodes[f].b = list.head
}

//! A type name: specifiers and qualifiers, then an abstract declarator.
def private type_name(var p : Rd) : int {
    let at = p.pos
    let specs = specifiers(p, true)
    if (specs.x < 0) {
        fail(p, "expected a type name")
        return -1
    }
    let n = node(p, NK.TYPENAME, at)
    p.ast.nodes[n].a = specs.x
    p.ast.nodes[n].b = declarator(p, 1)
    return n
}

// ---- initializers

def private initializer(var p : Rd) : int {
    if (kind(p) == int(TK.LBRACE)) {
        return init_list(p)
    }
    return assignment(p)
}

//! `{ [designators =] initializer, ... [,] }`.
def private init_list(var p : Rd) : int {
    let n = node(p, NK.INIT_LIST, p.pos)
    p.pos++
    var items = empty_list()
    while (!p.failed && kind(p) != int(TK.RBRACE)) {
        var desigs = empty_list()
        let at = p.pos
        while (!p.failed) {
            if (kind(p) == int(TK.DOT)) {
                let d = node(p, NK.DESIG_FIELD, p.pos)
                p.pos++
                if (kind(p) != int(TK.IDENTIFIER)) {
                    fail(p, "expected a field name")
                    break
                }
                p.ast.nodes[d].a = p.src.toks[p.pos].sym
                p.pos++
                append(p.ast, desigs, d)
            } elif (kind(p) == int(TK.LBRACKET)) {
                let d = node(p, NK.DESIG_INDEX, p.pos)
                p.pos++
                p.ast.nodes[d].a = conditional(p)
                if (accept(p, int(TK.ELLIPSIS))) {
                    p.ast.nodes[d].b = conditional(p)
                }
                take(p, int(TK.RBRACKET))
                append(p.ast, desigs, d)
            } else {
                break
            }
        }
        if (desigs.head >= 0) {
            take(p, int(TK.ASSIGN))
        } elif (kind(p) == int(TK.IDENTIFIER) && kind_at(p, 1) == int(TK.COLON)) {
            refuse(p, "the old GNU designator 'field:'")
            break
        }
        let value = initializer(p)
        let item = desigs.head >= 0 ? node(p, NK.INIT_ITEM, at) : node_at(p, NK.INIT_ITEM, max(value, 0))
        p.ast.nodes[item].a = desigs.head
        p.ast.nodes[item].b = value
        append(p.ast, items, item)
        if (!accept(p, int(TK.COMMA))) {
            break
        }
    }
    take(p, int(TK.RBRACE))
    p.ast.nodes[n].a = items.head
    return n
}

// ---- declarations

def private static_assert_decl(var p : Rd) : int {
    let n = node(p, NK.STATIC_ASSERT, p.pos)
    p.pos++
    take(p, int(TK.LPAREN))
    p.ast.nodes[n].a = conditional(p)
    if (accept(p, int(TK.COMMA))) {
        p.ast.nodes[n].b = string_literal(p)
    }
    take(p, int(TK.RPAREN))
    take(p, int(TK.SEMI))
    return n
}

//! The declarator's tail: an asm label and attributes, as an INIT_DECL without its initializer.
def private init_declarator_head(var p : Rd; d : int) : int {
    let n = node_at(p, NK.INIT_DECL, d)
    p.ast.nodes[n].a = d
    if (kind(p) == int(TK.ASM)) {
        let l = node(p, NK.ASM_LABEL, p.pos)
        p.pos++
        take(p, int(TK.LPAREN))
        p.ast.nodes[l].a = string_literal(p)
        take(p, int(TK.RPAREN))
        p.ast.nodes[n].c = l
    }
    p.ast.nodes[n].d = attributes(p)
    return n
}

//! A declaration, or at file scope a function definition. `file_scope` allows the definition.
def private declaration(var p : Rd; file_scope : bool) : int {
    if (kind(p) == int(TK.STATIC_ASSERT)) {
        return static_assert_decl(p)
    }
    let at = p.pos
    let specs = specifiers(p, false)
    if (specs.x < 0) {
        fail(p, "expected a declaration")
        return -1
    }
    let decl_kind = specs.y == 1 ? TYPEDEF : ORDINARY
    let n = node(p, NK.DECL, at)
    p.ast.nodes[n].a = specs.x
    if (accept(p, int(TK.SEMI))) {
        return n
    }
    var list = empty_list()
    var first = true
    while (!p.failed) {
        let d = declarator(p, 0)
        let id = init_declarator_head(p, d)
        if (first && file_scope && (kind(p) == int(TK.LBRACE) || (kind(p) != int(TK.SEMI) && kind(p) != int(TK.COMMA) && kind(p) != int(TK.ASSIGN)))) {
            return function_definition(p, n, id)
        }
        first = false
        scope_declare(p.sc, declarator_name(p.ast, d), decl_kind)
        if (accept(p, int(TK.ASSIGN))) {
            p.ast.nodes[id].b = initializer(p)
        }
        append(p.ast, list, id)
        if (!accept(p, int(TK.COMMA))) {
            break
        }
    }
    take(p, int(TK.SEMI))
    p.ast.nodes[n].b = list.head
    return n
}

//! A function definition after its specifiers (node `decl`) and declarator (`head`): old-style
//! parameter declarations, then the body, in a scope that holds the parameters.
def private function_definition(var p : Rd; decl, head : int) : int {
    let n = node_at(p, NK.FUNC_DEF, decl)
    p.ast.nodes[n].a = p.ast.nodes[decl].a
    p.ast.nodes[n].b = head
    let d = p.ast.nodes[head].a
    scope_declare(p.sc, declarator_name(p.ast, d), ORDINARY)
    let f = name_function(p.ast, d)
    if (f < 0) {
        fail(p, "expected ';' after a declarator")
        return n
    }
    scope_open(p.sc)
    var knr = empty_list()
    while (!p.failed && kind(p) != int(TK.LBRACE)) {
        append(p.ast, knr, declaration(p, false))
    }
    p.ast.nodes[n].c = knr.head
    var prm = p.ast.nodes[f].b
    while (prm >= 0) {
        let pn = p.ast.nodes[prm]
        scope_declare(p.sc, pn.kind == int(NK.IDENT_PARAM) ? pn.a : declarator_name(p.ast, pn.b), ORDINARY)
        prm = pn.next
    }
    p.ast.nodes[n].d = compound(p, false)
    scope_close(p.sc)
    return n
}

// ---- statements

//! `{ items }`; `scoped` opens a block scope (a function body shares its parameters' scope).
def private compound(var p : Rd; scoped : bool) : int {
    let n = node(p, NK.S_COMPOUND, p.pos)
    take(p, int(TK.LBRACE))
    if (scoped) {
        scope_open(p.sc)
    }
    var items = empty_list()
    while (!p.failed && kind(p) != int(TK.RBRACE)) {
        if (decl_start_at(p, p.pos)) {
            append(p.ast, items, declaration(p, false))
        } else {
            append(p.ast, items, statement(p))
        }
    }
    take(p, int(TK.RBRACE))
    if (scoped) {
        scope_close(p.sc)
    }
    p.ast.nodes[n].a = items.head
    return n
}

def private statement(var p : Rd) : int {
    let k = kind(p)
    let at = p.pos
    if (k == int(TK.LBRACE)) {
        return compound(p, true)
    } elif (k == int(TK.SEMI)) {
        p.pos++
        return node(p, NK.S_NULL, at)
    } elif (k == int(TK.IDENTIFIER) && kind_at(p, 1) == int(TK.COLON)) {
        let n = node(p, NK.S_LABEL, at)
        p.ast.nodes[n].a = p.src.toks[at].sym
        p.pos += 2
        p.ast.nodes[n].c = attributes(p)
        p.ast.nodes[n].b = statement(p)
        return n
    } elif (k == int(TK.CASE)) {
        let n = node(p, NK.S_CASE, at)
        p.pos++
        p.ast.nodes[n].a = conditional(p)
        if (accept(p, int(TK.ELLIPSIS))) {
            p.ast.nodes[n].b = conditional(p)
        }
        take(p, int(TK.COLON))
        p.ast.nodes[n].c = statement(p)
        return n
    } elif (k == int(TK.DEFAULT)) {
        let n = node(p, NK.S_DEFAULT, at)
        p.pos++
        take(p, int(TK.COLON))
        p.ast.nodes[n].a = statement(p)
        return n
    } elif (k == int(TK.IF)) {
        let n = node(p, NK.S_IF, at)
        p.pos++
        take(p, int(TK.LPAREN))
        p.ast.nodes[n].a = expression(p)
        take(p, int(TK.RPAREN))
        p.ast.nodes[n].b = statement(p)
        if (accept(p, int(TK.ELSE))) {
            p.ast.nodes[n].c = statement(p)
        }
        return n
    } elif (k == int(TK.SWITCH) || k == int(TK.WHILE)) {
        let n = node(p, k == int(TK.SWITCH) ? NK.S_SWITCH : NK.S_WHILE, at)
        p.pos++
        take(p, int(TK.LPAREN))
        p.ast.nodes[n].a = expression(p)
        take(p, int(TK.RPAREN))
        p.ast.nodes[n].b = statement(p)
        return n
    } elif (k == int(TK.DO)) {
        let n = node(p, NK.S_DO, at)
        p.pos++
        p.ast.nodes[n].a = statement(p)
        take(p, int(TK.WHILE))
        take(p, int(TK.LPAREN))
        p.ast.nodes[n].b = expression(p)
        take(p, int(TK.RPAREN))
        take(p, int(TK.SEMI))
        return n
    } elif (k == int(TK.FOR)) {
        let n = node(p, NK.S_FOR, at)
        p.pos++
        take(p, int(TK.LPAREN))
        scope_open(p.sc)
        if (decl_start_at(p, p.pos)) {
            p.ast.nodes[n].a = declaration(p, false)
        } else {
            if (kind(p) != int(TK.SEMI)) {
                let e = expression(p)
                let s = node_at(p, NK.S_EXPR, e)
                p.ast.nodes[s].a = e
                p.ast.nodes[n].a = s
            }
            take(p, int(TK.SEMI))
        }
        if (kind(p) != int(TK.SEMI)) {
            p.ast.nodes[n].b = expression(p)
        }
        take(p, int(TK.SEMI))
        if (kind(p) != int(TK.RPAREN)) {
            p.ast.nodes[n].c = expression(p)
        }
        take(p, int(TK.RPAREN))
        p.ast.nodes[n].d = statement(p)
        scope_close(p.sc)
        return n
    } elif (k == int(TK.GOTO)) {
        p.pos++
        if (accept(p, int(TK.STAR))) {
            let n = node(p, NK.S_GOTO_PTR, at)
            p.ast.nodes[n].a = expression(p)
            take(p, int(TK.SEMI))
            return n
        }
        let n = node(p, NK.S_GOTO, at)
        if (kind(p) != int(TK.IDENTIFIER)) {
            fail(p, "expected a label name")
            return n
        }
        p.ast.nodes[n].a = p.src.toks[p.pos].sym
        p.pos++
        take(p, int(TK.SEMI))
        return n
    } elif (k == int(TK.CONTINUE) || k == int(TK.BREAK)) {
        p.pos++
        take(p, int(TK.SEMI))
        return node(p, k == int(TK.CONTINUE) ? NK.S_CONTINUE : NK.S_BREAK, at)
    } elif (k == int(TK.RETURN)) {
        let n = node(p, NK.S_RETURN, at)
        p.pos++
        if (kind(p) != int(TK.SEMI)) {
            p.ast.nodes[n].a = expression(p)
        }
        take(p, int(TK.SEMI))
        return n
    } elif (k == int(TK.ASM)) {
        return asm_statement(p)
    } elif (k == int(TK.ATTRIBUTE)) {
        let n = node(p, NK.S_ATTRIBUTED, at)
        p.ast.nodes[n].a = attributes(p)
        p.ast.nodes[n].b = statement(p)
        return n
    }
    if (refuse_unsupported_word(p)) {
        return -1
    }
    let e = expression(p)
    let s = node_at(p, NK.S_EXPR, max(e, 0))
    p.ast.nodes[s].a = e
    take(p, int(TK.SEMI))
    return s
}

//! `asm [volatile|inline] ( template [: outputs [: inputs [: clobbers]]] );`
def private asm_statement(var p : Rd) : int {
    let n = node(p, NK.S_ASM, p.pos)
    p.pos++
    var flags = 0
    while (true) {
        if (accept(p, int(TK.VOLATILE))) {
            flags |= 1
        } elif (accept(p, int(TK.INLINE))) {
            flags |= 2
        } elif (kind(p) == int(TK.GOTO)) {
            refuse(p, "asm goto")
            return n
        } else {
            break
        }
    }
    p.ast.nodes[n].op = flags
    take(p, int(TK.LPAREN))
    p.ast.nodes[n].a = string_literal(p)
    for (slot in range(3)) {
        if (!accept(p, int(TK.COLON))) {
            break
        }
        var list = empty_list()
        while (!p.failed && kind(p) != int(TK.COLON) && kind(p) != int(TK.RPAREN)) {
            if (slot == 2) {
                append(p.ast, list, string_literal(p))
            } else {
                append(p.ast, list, asm_operand(p))
            }
            if (!accept(p, int(TK.COMMA))) {
                break
            }
        }
        if (slot == 0) {
            p.ast.nodes[n].b = list.head
        } elif (slot == 1) {
            p.ast.nodes[n].c = list.head
        } else {
            p.ast.nodes[n].d = list.head
        }
    }
    take(p, int(TK.RPAREN))
    take(p, int(TK.SEMI))
    return n
}

//! `[name] "constraint" (expression)`.
def private asm_operand(var p : Rd) : int {
    let n = node(p, NK.ASM_OPERAND, p.pos)
    if (accept(p, int(TK.LBRACKET))) {
        p.ast.nodes[n].c = p.src.toks[p.pos].sym
        take(p, int(TK.IDENTIFIER))
        take(p, int(TK.RBRACKET))
    }
    p.ast.nodes[n].a = string_literal(p)
    take(p, int(TK.LPAREN))
    p.ast.nodes[n].b = expression(p)
    take(p, int(TK.RPAREN))
    return n
}

// ---- expressions

def private expression(var p : Rd) : int {
    var lhs = assignment(p)
    while (!p.failed && kind(p) == int(TK.COMMA)) {
        p.pos++
        let n = node_at(p, NK.E_BINARY, lhs)
        p.ast.nodes[n].op = int(TK.COMMA)
        p.ast.nodes[n].a = lhs
        p.ast.nodes[n].b = assignment(p)
        lhs = n
    }
    return lhs
}

def private is_assign_op(k : int) : bool => k == int(TK.ASSIGN) || (k >= int(TK.MUL_ASSIGN) && k <= int(TK.OR_ASSIGN))

def private assignment(var p : Rd) : int {
    let lhs = conditional(p)
    let k = kind(p)
    if (!p.failed && is_assign_op(k)) {
        p.pos++
        let n = node_at(p, NK.E_ASSIGN, lhs)
        p.ast.nodes[n].op = k
        p.ast.nodes[n].a = lhs
        p.ast.nodes[n].b = assignment(p)
        return n
    }
    return lhs
}

def private conditional(var p : Rd) : int {
    let c = binary(p, 1)
    if (p.failed || kind(p) != int(TK.QUESTION)) {
        return c
    }
    p.pos++
    let n = node_at(p, NK.E_COND, c)
    p.ast.nodes[n].a = c
    if (kind(p) != int(TK.COLON)) {
        p.ast.nodes[n].b = expression(p)
    }
    take(p, int(TK.COLON))
    p.ast.nodes[n].c = conditional(p)
    return n
}

//! The binding level of binary operator `k`, 0 for a token that is none.
def private binary_level(k : int) : int {
    if (k == int(TK.OROR)) {
        return 1
    } elif (k == int(TK.ANDAND)) {
        return 2
    } elif (k == int(TK.PIPE)) {
        return 3
    } elif (k == int(TK.CARET)) {
        return 4
    } elif (k == int(TK.AMP)) {
        return 5
    } elif (k == int(TK.EQ) || k == int(TK.NE)) {
        return 6
    } elif (k == int(TK.LT) || k == int(TK.GT) || k == int(TK.LE) || k == int(TK.GE)) {
        return 7
    } elif (k == int(TK.SHL) || k == int(TK.SHR)) {
        return 8
    } elif (k == int(TK.PLUS) || k == int(TK.MINUS)) {
        return 9
    } elif (k == int(TK.STAR) || k == int(TK.SLASH) || k == int(TK.PERCENT)) {
        return 10
    }
    return 0
}

//! Precedence climbing over the left-associative binary operators of level `min_level` and up.
def private binary(var p : Rd; min_level : int) : int {
    var lhs = cast_expr(p)
    while (!p.failed) {
        let k = kind(p)
        let level = binary_level(k)
        if (level < min_level || level == 0) {
            break
        }
        p.pos++
        let rhs = binary(p, level + 1)
        let n = node_at(p, NK.E_BINARY, lhs)
        p.ast.nodes[n].op = k
        p.ast.nodes[n].a = lhs
        p.ast.nodes[n].b = rhs
        lhs = n
    }
    return lhs
}

//! A parenthesized type name at the cursor `(`: its TYPENAME, the cursor past `)`.
def private paren_type(var p : Rd) : int {
    p.pos++
    let t = type_name(p)
    take(p, int(TK.RPAREN))
    return t
}

def private compound_literal(var p : Rd; at, t : int) : int {
    let n = node(p, NK.E_COMPOUND_LIT, at)
    p.ast.nodes[n].a = t
    p.ast.nodes[n].b = init_list(p)
    return postfix(p, n)
}

def private cast_expr(var p : Rd) : int {
    if (kind(p) == int(TK.LPAREN) && type_start_at(p, p.pos + 1)) {
        let at = p.pos
        let t = paren_type(p)
        if (kind(p) == int(TK.LBRACE)) {
            return compound_literal(p, at, t)
        }
        let n = node(p, NK.E_CAST, at)
        p.ast.nodes[n].a = t
        p.ast.nodes[n].b = cast_expr(p)
        return n
    }
    return unary(p)
}

def private unary(var p : Rd) : int {
    let k = kind(p)
    let at = p.pos
    if (k == int(TK.INC) || k == int(TK.DEC)) {
        p.pos++
        let n = node(p, NK.E_UNARY, at)
        p.ast.nodes[n].op = k
        p.ast.nodes[n].a = unary(p)
        return n
    } elif (k == int(TK.AMP) || k == int(TK.STAR) || k == int(TK.PLUS) || k == int(TK.MINUS) || k == int(TK.TILDE) || k == int(TK.BANG)) {
        p.pos++
        let n = node(p, NK.E_UNARY, at)
        p.ast.nodes[n].op = k
        p.ast.nodes[n].a = cast_expr(p)
        return n
    } elif (k == int(TK.ANDAND)) {
        p.pos++
        let n = node(p, NK.E_LABEL_ADDR, at)
        p.ast.nodes[n].a = p.src.toks[p.pos].sym
        take(p, int(TK.IDENTIFIER))
        return n
    } elif (k == int(TK.SIZEOF) || k == int(TK.ALIGNOF) || k == int(TK.ALIGNOF_GNU)) {
        p.pos++
        if (kind(p) == int(TK.LPAREN) && type_start_at(p, p.pos + 1)) {
            let lp = p.pos
            let t = paren_type(p)
            if (kind(p) == int(TK.LBRACE)) {
                let lit = compound_literal(p, lp, t)
                let n = node(p, k == int(TK.SIZEOF) ? NK.E_SIZEOF_EXPR : NK.E_ALIGNOF_EXPR, at)
                p.ast.nodes[n].op = k == int(TK.SIZEOF) ? 0 : k
                p.ast.nodes[n].a = lit
                return n
            }
            let n = node(p, k == int(TK.SIZEOF) ? NK.E_SIZEOF_TYPE : NK.E_ALIGNOF_TYPE, at)
            p.ast.nodes[n].op = k == int(TK.SIZEOF) ? 0 : k
            p.ast.nodes[n].a = t
            return n
        }
        if (k == int(TK.ALIGNOF)) {
            fail(p, "expected '(' and a type name after '_Alignof'")
            return -1
        }
        let n = node(p, k == int(TK.SIZEOF) ? NK.E_SIZEOF_EXPR : NK.E_ALIGNOF_EXPR, at)
        p.ast.nodes[n].op = k == int(TK.SIZEOF) ? 0 : k
        p.ast.nodes[n].a = unary(p)
        return n
    } elif (k == int(TK.EXTENSION)) {
        p.pos++
        let n = node(p, NK.E_EXTENSION, at)
        p.ast.nodes[n].a = cast_expr(p)
        return n
    }
    return postfix(p, primary(p))
}

def private postfix(var p : Rd; e : int) : int {
    var lhs = e
    while (!p.failed) {
        let k = kind(p)
        if (k == int(TK.LBRACKET)) {
            p.pos++
            let n = node_at(p, NK.E_INDEX, lhs)
            p.ast.nodes[n].a = lhs
            p.ast.nodes[n].b = expression(p)
            take(p, int(TK.RBRACKET))
            lhs = n
        } elif (k == int(TK.LPAREN)) {
            p.pos++
            let n = node_at(p, NK.E_CALL, lhs)
            p.ast.nodes[n].a = lhs
            var args = empty_list()
            while (!p.failed && kind(p) != int(TK.RPAREN)) {
                append(p.ast, args, assignment(p))
                if (!accept(p, int(TK.COMMA))) {
                    break
                }
            }
            take(p, int(TK.RPAREN))
            p.ast.nodes[n].b = args.head
            lhs = n
        } elif (k == int(TK.DOT) || k == int(TK.ARROW)) {
            p.pos++
            let n = node_at(p, NK.E_MEMBER, lhs)
            p.ast.nodes[n].op = k
            p.ast.nodes[n].a = lhs
            p.ast.nodes[n].b = p.src.toks[p.pos].sym
            take(p, int(TK.IDENTIFIER))
            lhs = n
        } elif (k == int(TK.INC) || k == int(TK.DEC)) {
            p.pos++
            let n = node_at(p, NK.E_POSTFIX, lhs)
            p.ast.nodes[n].op = k
            p.ast.nodes[n].a = lhs
            lhs = n
        } else {
            break
        }
    }
    return lhs
}

def private primary(var p : Rd) : int {
    let k = kind(p)
    let at = p.pos
    if (k == int(TK.IDENTIFIER)) {
        if (typedef_at(p, at)) {
            fail(p, "unexpected type name in an expression")
            return -1
        }
        p.pos++
        let n = node(p, NK.E_IDENT, at)
        p.ast.nodes[n].a = p.src.toks[at].sym
        return n
    } elif (k == int(TK.I_CONSTANT) || k == int(TK.F_CONSTANT) || k == int(TK.C_CONSTANT)) {
        p.pos++
        let n = node(p, k == int(TK.I_CONSTANT) ? NK.E_INT : k == int(TK.F_CONSTANT) ? NK.E_FLOAT : NK.E_CHAR, at)
        p.ast.nodes[n].a = at
        return n
    } elif (k == int(TK.STRING_LITERAL)) {
        return string_literal(p)
    } elif (k == int(TK.FUNC_NAME)) {
        p.pos++
        let n = node(p, NK.E_FUNC_NAME, at)
        p.ast.nodes[n].a = p.src.toks[at].sym
        return n
    } elif (k == int(TK.LPAREN)) {
        p.pos++
        if (kind(p) == int(TK.LBRACE)) {
            let n = node(p, NK.E_STMT_EXPR, at)
            p.ast.nodes[n].a = compound(p, true)
            take(p, int(TK.RPAREN))
            return n
        }
        let n = node(p, NK.E_PAREN, at)
        p.ast.nodes[n].a = expression(p)
        take(p, int(TK.RPAREN))
        return n
    } elif (k == int(TK.VA_ARG)) {
        p.pos++
        let n = node(p, NK.E_VA_ARG, at)
        take(p, int(TK.LPAREN))
        p.ast.nodes[n].a = assignment(p)
        take(p, int(TK.COMMA))
        p.ast.nodes[n].b = type_name(p)
        take(p, int(TK.RPAREN))
        return n
    } elif (k == int(TK.OFFSETOF)) {
        p.pos++
        let n = node(p, NK.E_OFFSETOF, at)
        take(p, int(TK.LPAREN))
        p.ast.nodes[n].a = type_name(p)
        take(p, int(TK.COMMA))
        var path = empty_list()
        let first = node(p, NK.DESIG_FIELD, p.pos)
        p.ast.nodes[first].a = p.src.toks[p.pos].sym
        take(p, int(TK.IDENTIFIER))
        append(p.ast, path, first)
        while (!p.failed && kind(p) != int(TK.RPAREN)) {
            if (kind(p) == int(TK.DOT)) {
                let d = node(p, NK.DESIG_FIELD, p.pos)
                p.pos++
                p.ast.nodes[d].a = p.src.toks[p.pos].sym
                take(p, int(TK.IDENTIFIER))
                append(p.ast, path, d)
            } elif (kind(p) == int(TK.LBRACKET)) {
                let d = node(p, NK.DESIG_INDEX, p.pos)
                p.pos++
                p.ast.nodes[d].a = expression(p)
                take(p, int(TK.RBRACKET))
                append(p.ast, path, d)
            } else {
                fail(p, "expected '.', '[' or ')' in __builtin_offsetof")
            }
        }
        take(p, int(TK.RPAREN))
        p.ast.nodes[n].b = path.head
        return n
    }
    if (!refuse_unsupported_word(p)) {
        fail(p, "expected an expression")
    }
    return -1
}

// ---- translation unit

//! Parse the lexed unit `src` (moved in and back out through `p.src`) into `p.ast`.
def rd_parse(var p : Rd) {
    p.eof = length(p.src.toks) - 1
    p.pos = 0
    p.failed = false
    p.err = ""
    p.ast.nodes |> clear()
    p.ast.nodes |> reserve(length(p.src.toks))
    p.sc <- file_scopes(p.src.names)
    let tu = node(p, NK.TU, 0)
    var decls = empty_list()
    while (!p.failed && kind(p) != int(TK.EOF)) {
        if (accept(p, int(TK.SEMI))) {
            continue
        }
        if (kind(p) == int(TK.ASM)) {
            refuse(p, "a file-scope asm")
            break
        }
        append(p.ast, decls, declaration(p, true))
    }
    p.ast.nodes[tu].a = decls.head
    p.ast.root = tu
}
