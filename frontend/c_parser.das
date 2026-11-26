options gen2
options indenting = 4

module c_parser public

require math
require c_ast public

//! What a name means in the ordinary name space where the parser stands: nothing, an ordinary
//! identifier, or a typedef name.
enum CBinding {
    NONE
    ORDINARY
    TYPEDEF
}

//! The typedef-name table: each symbol's binding now, and an undo log a scope's close rolls back to
//! its mark, so a lookup is one index.
struct CScopes {
    binding : array<CBinding>
    undo : array<tuple<sym : int; was : CBinding>>
    marks : array<int>
}

//! The parser over one unit's tokens, building `ast`. The first error stops it: `failed` is set,
//! `err` holds `file:line:col: what` and the cursor stays at the end.
struct CParser {
    unit : CUnit
    ast : CAst
    scopes : CScopes
    pos : int
    last : int          //!< the index of the EOF token
    depth : int         //!< the nesting the parser is in, bounded by `C_MAX_DEPTH`
    operators : array<int>  //!< the binary operators waiting for their right operand, of every `binary` running
    operands : array<int>   //!< the operands waiting for their operator, of every `binary` running
    failed : bool
    err : string
}

//! The deepest nesting the parser takes, in levels (`ARCHITECTURE_PARSER.md` section 19 lists what
//! opens one); past it the input is refused. 256 levels of the costliest form fit a 256 KiB stack
//! with a third to spare, the stack a caller of the parser gives it.
let C_MAX_DEPTH = 256

//! Open a scope: the bindings made from now on end at its close.
def c_scope_open(var p : CParser) {
    p.scopes.marks |> push(length(p.scopes.undo))
}

//! Close the innermost scope: every binding made in it is undone.
[arch(at="ARCHITECTURE_PARSER.md#c-typedef-table")]
def c_scope_close(var p : CParser) {
    let mark = p.scopes.marks[length(p.scopes.marks) - 1]
    p.scopes.marks |> pop()
    var at = length(p.scopes.undo) - 1
    while (at >= mark) {
        p.scopes.binding[p.scopes.undo[at].sym] = p.scopes.undo[at].was
        at--
    }
    p.scopes.undo |> resize(mark)
}

//! Bind symbol `sym` as `binding` in the innermost scope; -1 binds nothing.
[arch(at="ARCHITECTURE_PARSER.md#c-typedef-table")]
def c_declare(var p : CParser; sym : int; binding : CBinding) {
    return if (sym < 0)
    if (sym >= length(p.scopes.binding)) {
        p.scopes.binding |> resize(sym + 256)
    }
    p.scopes.undo |> push((sym = sym, was = p.scopes.binding[sym]))
    p.scopes.binding[sym] = binding
}

//! Symbol `sym` names a typedef where the parser stands.
def c_is_typedef(p : CParser; sym : int) : bool => sym >= 0 && sym < length(p.scopes.binding) && p.scopes.binding[sym] == CBinding.TYPEDEF

//! Open the parser over the tokens of `text`, named `name`, with an empty tree and one typedef
//! name, `__builtin_va_list`, which clang declares before every unit; false when the tokens hold
//! an error, which `err` then holds.
def c_parser_open_text(var p : CParser; text, name : string) : bool {
    let clean = c_tokens_of_text(p.unit, text, name)
    p.ast.nodes |> clear()
    p.ast.nodes |> reserve(length(p.unit.toks))
    p.scopes.binding |> clear()
    p.scopes.undo |> clear()
    p.scopes.marks |> clear()
    p.pos = 0
    p.last = length(p.unit.toks) - 1
    p.depth = 0
    p.operators |> clear()
    p.operands |> clear()
    p.failed = !clean
    p.err = p.unit.err
    c_declare(p, c_symbol(p.unit, "__builtin_va_list"), CBinding.TYPEDEF)
    return clean
}

def private kind(p : CParser) : int => p.unit.toks[p.pos].kind

def private kind_at(p : CParser; ahead : int) : int => p.unit.toks[min(p.pos + ahead, p.last)].kind

def private sym(p : CParser) : int => p.unit.toks[p.pos].sym

//! the first error, at the cursor's token; the cursor moves to the end so every loop stops
def private stop(var p : CParser; what : string) {
    if (!p.failed) {
        p.failed = true
        p.err = "{c_where(p.unit, p.pos)}: {what}"
    }
    p.pos = p.last
}

//! malformed input: what the parser expected and the token it met
def private fail(var p : CParser; expected : string) {
    let got = kind(p) == int(CTok.EOF) ? "end of input" : "'{c_spelling(p.unit, p.pos)}'"
    stop(p, "expected {expected}, got {got}")
}

//! a construct the parser does not take
def private refuse(var p : CParser; construct : string) {
    stop(p, "{construct} is not parsed")
}

def private accept(var p : CParser; k : CTok) : bool {
    return false if (kind(p) != int(k))
    p.pos++
    return true
}

def private take(var p : CParser; k : CTok) {
    if (!accept(p, k)) {
        fail(p, "'{c_kind_name(int(k))}'")
    }
}

//! one level deeper, or false and a refusal past `C_MAX_DEPTH`
[arch(at="ARCHITECTURE_PARSER.md#c-parser-errors")]
def private enter(var p : CParser) : bool {
    p.depth++
    return true if (p.depth <= C_MAX_DEPTH)
    refuse(p, "nesting deeper than {C_MAX_DEPTH} levels")
    return false
}

def private leave(var p : CParser) {
    p.depth--
}

def private node(var p : CParser; kind : CNode; tok : int; op : int = 0; a : int = -1; b : int = -1; c : int = -1) : int {
    p.ast.nodes |> push(CNodeRec(kind = kind, op = op, a = a, b = b, c = c, d = -1, next = -1, tok = tok))
    return length(p.ast.nodes) - 1
}

//! the token node `n` starts at, or the cursor's for no node
def private start_of(p : CParser; n : int) : int => n >= 0 ? p.ast.nodes[n].tok : p.pos

//! the construct a keyword names that the parser refuses wherever it stands, "" for any other kind
def private refused_word(k : int) : string {
    if (k == int(CTok.GENERIC)) {
        return "a generic selection (_Generic)"
    } elif (k == int(CTok.IMAGINARY)) {
        return "the _Imaginary type"
    } elif (k == int(CTok.INT128)) {
        return "the __int128 type"
    } elif (k == int(CTok.AUTO_TYPE)) {
        return "__auto_type"
    } elif (k == int(CTok.LOCAL_LABEL)) {
        return "a local label declaration (__label__)"
    } elif (k == int(CTok.REAL_PART)) {
        return "__real__"
    } elif (k == int(CTok.IMAG_PART)) {
        return "__imag__"
    }
    return ""
}

def private is_type_keyword(k : int) : bool => k >= int(CTok.VOID) && k <= int(CTok.COMPLEX)

def private is_qualifier(k : int) : bool => k >= int(CTok.CONST) && k <= int(CTok.ATOMIC)

//! token `t` starts a type name: a specifier or qualifier keyword, a tag, `typeof`, an attribute, a
//! refused type word (so it is refused by name), or an identifier the table binds as a typedef
[arch(at="ARCHITECTURE_PARSER.md#c-typedef-table")]
def private type_starts_at(p : CParser; t : int) : bool {
    let tok = p.unit.toks[min(t, p.last)]
    let k = tok.kind
    return (is_type_keyword(k) || is_qualifier(k) || (k >= int(CTok.STRUCT) && k <= int(CTok.ENUM))
        || k == int(CTok.TYPEOF) || k == int(CTok.ATTRIBUTE) || k == int(CTok.ALIGNAS)
        || k == int(CTok.INT128) || k == int(CTok.AUTO_TYPE) || k == int(CTok.IMAGINARY)
        || (k == int(CTok.IDENTIFIER) && c_is_typedef(p, tok.sym)))
}

//! `__attribute__((...))` at the cursor, kept whole: its node spans its tokens to the `)` that
//! balances the first `(`
def private attribute(var p : CParser) : int {
    let at = p.pos
    p.pos++
    if (kind(p) != int(CTok.LPAREN) || kind_at(p, 1) != int(CTok.LPAREN)) {
        fail(p, "'((' after __attribute__")
        return -1
    }
    let last = balanced(p, CTok.LPAREN, CTok.RPAREN, "')' closing __attribute__")
    return last < 0 ? -1 : node(p, CNode.ATTRIBUTE, at, 0, at, last)
}

//! the token that closes the `open` at the cursor, counting `open` and `close`, the cursor past
//! it; -1 and `expected <closing>` at the end of input
def private balanced(var p : CParser; open, close : CTok; closing : string) : int {
    var depth = 0
    while (!p.failed) {
        let k = kind(p)
        if (k == int(CTok.EOF)) {
            fail(p, closing)
            return -1
        }
        depth += k == int(open) ? 1 : k == int(close) ? -1 : 0
        p.pos++
        return p.pos - 1 if (depth == 0)
    }
    return -1
}

def private attributes(var p : CParser) : int {
    var list = CList()
    while (!p.failed && kind(p) == int(CTok.ATTRIBUTE)) {
        c_append(p.ast, list, attribute(p))
    }
    return list.head
}

//! an enum's enumerators to its `}`, the cursor past its `{`: each name an ordinary identifier from
//! the end of its enumerator on, so it shadows a typedef name; a trailing comma stays
[arch(at="ARCHITECTURE_PARSER.md#c-records")]
def private enumerators(var p : CParser) : int {
    var list = CList()
    while (!p.failed) {
        if (kind(p) != int(CTok.IDENTIFIER)) {
            fail(p, "an enumerator")
            break
        }
        let at = p.pos
        let name = sym(p)
        p.pos++
        let attrs = attributes(p)
        let value = accept(p, CTok.ASSIGN) ? c_constant_expression(p) : -1
        c_declare(p, name, CBinding.ORDINARY)
        c_append(p.ast, list, node(p, CNode.ENUMERATOR, at, 0, name, value, attrs))
        break if (!accept(p, CTok.COMMA) || kind(p) == int(CTok.RBRACE))
    }
    return list.head
}

//! a record's member declarations to its `}`, the cursor past its `{`: `__extension__`s,
//! specifiers, then member declarators, each a declarator, a bit-field width or both, with the
//! attributes before and after it; none for an anonymous member. A `;` alone and `_Static_assert`
//! stand among them; a member name binds nothing in the ordinary scope
[arch(at="ARCHITECTURE_PARSER.md#c-records")]
def private member_declarations(var p : CParser) : int {
    var list = CList()
    while (!p.failed && kind(p) != int(CTok.RBRACE)) {
        if (accept(p, CTok.SEMI)) {
            continue
        } elif (kind(p) == int(CTok.STATIC_ASSERT)) {
            c_append(p.ast, list, static_assert_decl(p))
            continue
        }
        let at = p.pos
        var extension = 0
        while (accept(p, CTok.EXTENSION)) {
            extension = 1
        }
        let specs_at = p.pos
        var typed = false
        let specs = specifiers(p, CSpecifiers.TYPE_NAME, typed)
        if (specs < 0) {
            fail(p, "a member declaration")
            break
        } elif (!typed) {
            untyped(p, specs_at)
            break
        }
        var members = CList()
        var first = true
        var more = kind(p) != int(CTok.SEMI)
        while (!p.failed && more) {
            var attrs = CList()
            c_append(p.ast, attrs, first ? -1 : attributes(p))
            let member_at = p.pos
            let d = kind(p) == int(CTok.COLON) ? -1 : declarator(p, CDeclarator.NAMED)
            let width = accept(p, CTok.COLON) ? c_constant_expression(p) : -1
            c_append(p.ast, attrs, attributes(p))
            c_append(p.ast, members, node(p, CNode.MEMBER_DECLARATOR, d >= 0 ? start_of(p, d) : member_at, 0, d, width, attrs.head))
            first = false
            more = accept(p, CTok.COMMA)
        }
        take(p, CTok.SEMI)
        c_append(p.ast, list, node(p, CNode.MEMBER_DECL, at, extension, specs, members.head))
    }
    return list.head
}

//! `struct`, `union` or `enum`, attributes, a tag, then a body in braces and the attributes after
//! it: a tag or a body at least. A tag binds nothing in the ordinary scope; a body opens a level
[arch(at="ARCHITECTURE_PARSER.md#c-records")]
def private tag_specifier(var p : CParser) : int {
    let at = p.pos
    let k = kind(p)
    p.pos++
    var attrs = CList()
    c_append(p.ast, attrs, attributes(p))
    var tag = -1
    if (kind(p) == int(CTok.IDENTIFIER)) {
        tag = sym(p)
        p.pos++
    }
    var has_body = 0
    var body = -1
    if (kind(p) == int(CTok.LBRACE)) {
        return -1 if (!enter(p))
        p.pos++
        body = k == int(CTok.ENUM) ? enumerators(p) : member_declarations(p)
        take(p, CTok.RBRACE)
        leave(p)
        has_body = 1
        c_append(p.ast, attrs, attributes(p))
    } elif (tag < 0) {
        fail(p, "a tag name or '\{' after '{c_kind_name(k)}'")
        return -1
    }
    let is_enum = k == int(CTok.ENUM)
    let n = node(p, is_enum ? CNode.SPEC_ENUM : CNode.SPEC_RECORD, at, is_enum ? 0 : k, tag, has_body, body)
    p.ast.nodes[n].d = attrs.head
    return n
}

//! `typeof (...)` or `_Alignas (...)`: a type name when one starts after the `(`, else an expression
def private typeof_or_alignas(var p : CParser) : int {
    let at = p.pos
    let is_typeof = kind(p) == int(CTok.TYPEOF)
    p.pos++
    take(p, CTok.LPAREN)
    var n = -1
    if (type_starts_at(p, p.pos)) {
        let t = c_type_name(p)
        n = node(p, is_typeof ? CNode.SPEC_TYPEOF_TYPE : CNode.SPEC_ALIGNAS_TYPE, at, 0, t)
    } else {
        let e = is_typeof ? c_expression(p) : c_constant_expression(p)
        n = node(p, is_typeof ? CNode.SPEC_TYPEOF_EXPR : CNode.SPEC_ALIGNAS_EXPR, at, 0, e)
    }
    take(p, CTok.RPAREN)
    return n
}

//! A type specifier of C11 6.7.2 as one bit of a set: a builtin keyword's bit by its kind's place
//! after `void`, a second `long` its own bit, and a typedef name, a tag or `typeof` one bit for all.
let private SPEC_LONG = 1 << (int(CTok.LONG) - int(CTok.VOID))

let private SPEC_LONG_LONG = 1 << 12

let private SPEC_OTHER = 1 << 13

//! The largest sets of type specifiers that combine (C11 6.7.2p2, `_Complex` as GNU C takes it); a
//! set combines when one of these holds it.
let private SPEC_SETS = fixed_array(
    spec_set(fixed_array(CTok.VOID)),
    spec_set(fixed_array(CTok.CHAR, CTok.SIGNED)),
    spec_set(fixed_array(CTok.CHAR, CTok.UNSIGNED)),
    spec_set(fixed_array(CTok.SHORT, CTok.INT, CTok.SIGNED)),
    spec_set(fixed_array(CTok.SHORT, CTok.INT, CTok.UNSIGNED)),
    spec_set(fixed_array(CTok.LONG, CTok.INT, CTok.SIGNED)) | SPEC_LONG_LONG,
    spec_set(fixed_array(CTok.LONG, CTok.INT, CTok.UNSIGNED)) | SPEC_LONG_LONG,
    spec_set(fixed_array(CTok.FLOAT, CTok.COMPLEX)),
    spec_set(fixed_array(CTok.LONG, CTok.DOUBLE, CTok.COMPLEX)),
    spec_set(fixed_array(CTok.BOOL)),
    SPEC_OTHER)

def private spec_set(kinds : CTok[]) : int {
    var set = 0
    for (k in kinds) {
        set |= 1 << (int(k) - int(CTok.VOID))
    }
    return set
}

//! the set `set` of type specifiers with the one of kind `k` added (`IDENTIFIER` for a typedef name,
//! a tag or `typeof`), or -1 when the result is in no set of `SPEC_SETS`
[arch(at="ARCHITECTURE_PARSER.md#c-type-names")]
def private with_specifier(set, k : int) : int {
    var bit = is_type_keyword(k) ? 1 << (k - int(CTok.VOID)) : SPEC_OTHER
    if (bit == SPEC_LONG && (set & SPEC_LONG) != 0) {
        bit = SPEC_LONG_LONG
    }
    return -1 if ((set & bit) != 0)
    let joined = set | bit
    for (valid in SPEC_SETS) {
        return joined if ((joined & ~valid) == 0)
    }
    return -1
}

//! Where a list of specifiers stands, which decides the storage classes and function specifiers it
//! takes: none in a type name, `register` alone in a parameter, any in a declaration.
enum CSpecifiers {
    TYPE_NAME
    PARAMETER
    DECLARATION
}

//! the set `set` of storage classes with the one of kind `k` added, or -1 when C11 6.7.1p2 forbids
//! the pair: one storage class, `_Thread_local` beside `static` or `extern` only; a repeated one
//! stays, as clang takes it with a warning
[arch(at="ARCHITECTURE_PARSER.md#c-declarations")]
def private with_storage(set, k : int) : int {
    let bit = 1 << (k - int(CTok.TYPEDEF))
    let thread = 1 << (int(CTok.THREAD_LOCAL) - int(CTok.TYPEDEF))
    let joined = set | bit
    let others = joined & ~thread
    let static_or_extern = (1 << (int(CTok.STATIC) - int(CTok.TYPEDEF))) | (1 << (int(CTok.EXTERN) - int(CTok.TYPEDEF)))
    let two_classes = (others & (others - 1)) != 0
    let thread_misplaced = (joined & thread) != 0 && (others & ~static_or_extern) != 0
    return two_classes || thread_misplaced ? -1 : joined
}

//! Specifiers and qualifiers at the cursor, as a list; storage classes and function specifiers as
//! `place` allows them. An identifier is a typedef name only while no type specifier
//! came before it; a type specifier that does not combine with those before it is an error.
//! `typed` answers whether a type specifier came.
[arch(at="ARCHITECTURE_PARSER.md#c-typedef-table")]
def private specifiers(var p : CParser; place : CSpecifiers; var typed : bool&) : int {
    var list = CList()
    var set = 0
    var storage = 0
    while (!p.failed) {
        let k = kind(p)
        let is_storage = k >= int(CTok.TYPEDEF) && k <= int(CTok.NORETURN)
        if (is_storage && place == CSpecifiers.PARAMETER && k != int(CTok.REGISTER)) {
            fail(p, "'register' as a parameter's storage class")
            break
        } elif (is_storage && place == CSpecifiers.DECLARATION && k <= int(CTok.THREAD_LOCAL)) {
            storage = with_storage(storage, k)
            if (storage < 0) {
                fail(p, "a storage class that combines with those before it")
                break
            }
        }
        let typedef_name = k == int(CTok.IDENTIFIER) && set == 0 && c_is_typedef(p, sym(p))
        if (typedef_name || is_type_keyword(k) || (k >= int(CTok.STRUCT) && k <= int(CTok.ENUM)) || k == int(CTok.TYPEOF)) {
            set = with_specifier(set, k)
            if (set < 0) {
                fail(p, "a type specifier that combines with those before it")
                break
            }
        }
        var n = -1
        if (is_type_keyword(k) || is_qualifier(k) || (is_storage && place != CSpecifiers.TYPE_NAME)) {
            if (k == int(CTok.ATOMIC) && kind_at(p, 1) == int(CTok.LPAREN)) {
                refuse(p, "the _Atomic(type) specifier")
                break
            }
            n = node(p, CNode.SPEC_KEYWORD, p.pos, k)
            p.pos++
        } elif (k == int(CTok.IDENTIFIER)) {
            break if (!typedef_name)
            n = node(p, CNode.SPEC_TYPEDEF_NAME, p.pos, 0, sym(p))
            p.pos++
        } elif (k >= int(CTok.STRUCT) && k <= int(CTok.ENUM)) {
            n = tag_specifier(p)
        } elif (k == int(CTok.TYPEOF) || k == int(CTok.ALIGNAS)) {
            n = typeof_or_alignas(p)
        } elif (k == int(CTok.ATTRIBUTE)) {
            n = attribute(p)
        } else {
            let what = refused_word(k)
            if (!empty(what)) {
                refuse(p, what)
            }
            break
        }
        c_append(p.ast, list, n)
    }
    typed = set != 0
    return list.head
}

//! the refusal of a specifier list starting at token `at` that holds no type specifier: C99 has no
//! implicit `int`
def private untyped(var p : CParser; at : int) {
    p.pos = at
    refuse(p, "a specifier list with no type specifier")
}

//! qualifiers and attributes after a `*` or inside `[]`
def private pointer_qualifiers(var p : CParser) : int {
    var list = CList()
    while (!p.failed) {
        let k = kind(p)
        if (is_qualifier(k)) {
            c_append(p.ast, list, node(p, CNode.SPEC_KEYWORD, p.pos, k))
            p.pos++
        } elif (k == int(CTok.ATTRIBUTE)) {
            c_append(p.ast, list, attribute(p))
        } else {
            break
        }
    }
    return list.head
}

//! What a declarator may be: one that names something, an abstract one, or either (a parameter).
enum CDeclarator {
    NAMED
    ABSTRACT
    EITHER
}

//! the `(` at the cursor opens a nested declarator, not a parameter list: decided by the first
//! token past any attributes after it
[arch(at="ARCHITECTURE_PARSER.md#c-type-names")]
def private nested_paren(p : CParser; mode : CDeclarator) : bool {
    return true if (mode == CDeclarator.NAMED)
    var at = p.pos + 1
    while (at < p.last && p.unit.toks[at].kind == int(CTok.ATTRIBUTE)) {
        at++
        var depth = 0
        while (at < p.last) {
            let k = p.unit.toks[at].kind
            at++
            depth += k == int(CTok.LPAREN) ? 1 : k == int(CTok.RPAREN) ? -1 : 0
            break if (depth == 0)
        }
    }
    let tok = p.unit.toks[min(at, p.last)]
    let k = tok.kind
    return (k == int(CTok.STAR) || k == int(CTok.LPAREN) || k == int(CTok.LBRACKET)
        || (mode == CDeclarator.EITHER && k == int(CTok.IDENTIFIER) && !c_is_typedef(p, tok.sym)))
}

//! the `d_name` node of declarator `d`, -1 for an abstract one
def private name_node(ast : CAst; d : int) : int {
    var at = d
    while (at >= 0) {
        return at if (ast.nodes[at].kind == CNode.D_NAME)
        at = ast.nodes[at].a
    }
    return -1
}

//! The name a declarator declares, -1 for an abstract one.
def c_declarator_name(ast : CAst; d : int) : int {
    let name = name_node(ast, d)
    return name < 0 ? -1 : ast.nodes[name].a
}

//! an old-style identifier list (C11 6.7.6.3p3) at the cursor into node `f`, its names ordinary
def private identifier_list(var p : CParser; f : int) {
    var list = CList()
    while (!p.failed) {
        if (kind(p) != int(CTok.IDENTIFIER) || c_is_typedef(p, sym(p))) {
            fail(p, "a parameter name")
            break
        }
        c_append(p.ast, list, node(p, CNode.IDENT_PARAM, p.pos, 0, sym(p)))
        p.pos++
        break if (!accept(p, CTok.COMMA))
    }
    p.ast.nodes[f].op = 2
    p.ast.nodes[f].b = list.head
}

//! a function declarator's parameters, in a prototype scope of their own, into node `f`; in a
//! named declarator an identifier no typedef binds opens an old-style identifier list
[arch(at="ARCHITECTURE_PARSER.md#c-type-names")]
def private parameters(var p : CParser; f : int; mode : CDeclarator) {
    var list = CList()
    var variadic = 0
    if (mode == CDeclarator.NAMED && kind(p) == int(CTok.IDENTIFIER) && !c_is_typedef(p, sym(p))) {
        identifier_list(p, f)
        return
    }
    if (kind(p) != int(CTok.RPAREN) && enter(p)) {
        c_scope_open(p)
        while (!p.failed) {
            if (accept(p, CTok.ELLIPSIS)) {
                variadic = 1
                break
            }
            let at = p.pos
            var typed = false
            let specs = specifiers(p, CSpecifiers.PARAMETER, typed)
            if (specs < 0) {
                fail(p, "a parameter declaration")
                break
            } elif (!typed) {
                untyped(p, at)
                break
            }
            let d = declarator(p, CDeclarator.EITHER)
            c_declare(p, c_declarator_name(p.ast, d), CBinding.ORDINARY)
            let attrs = attributes(p)
            c_append(p.ast, list, node(p, CNode.PARAM, at, 0, specs, d, attrs))
            break if (!accept(p, CTok.COMMA))
        }
        c_scope_close(p)
        leave(p)
    }
    p.ast.nodes[f].op = variadic
    p.ast.nodes[f].b = list.head
}

//! the array and function suffixes after the direct declarator `inner`
def private declarator_suffixes(var p : CParser; first : int; mode : CDeclarator) : int {
    var inner = first
    while (!p.failed) {
        let at = start_of(p, inner)
        if (accept(p, CTok.LBRACKET)) {
            var flags = accept(p, CTok.STATIC) ? 1 : 0
            let quals = pointer_qualifiers(p)
            flags |= accept(p, CTok.STATIC) ? 1 : 0
            var size = -1
            if (kind(p) == int(CTok.STAR) && kind_at(p, 1) == int(CTok.RBRACKET)) {
                flags |= 2
                p.pos++
            } elif (kind(p) != int(CTok.RBRACKET)) {
                size = c_assignment(p)
            }
            take(p, CTok.RBRACKET)
            inner = node(p, CNode.D_ARRAY, at, flags, inner, size, quals)
        } elif (accept(p, CTok.LPAREN)) {
            let n = node(p, CNode.D_FUNCTION, at, 0, inner)
            parameters(p, n, mode)
            take(p, CTok.RPAREN)
            inner = n
        } else {
            break
        }
    }
    return inner
}

//! A declarator of `mode` at the cursor; an abstract one with nothing in it is -1.
[arch(at="ARCHITECTURE_PARSER.md#c-type-names")]
def private declarator(var p : CParser; mode : CDeclarator) : int {
    let at = p.pos
    var inner = -1
    if (kind(p) == int(CTok.STAR)) {
        return -1 if (!enter(p))
        p.pos++
        let quals = pointer_qualifiers(p)
        inner = node(p, CNode.D_POINTER, at, 0, declarator(p, mode), quals)
        leave(p)
        return inner
    }
    if (kind(p) == int(CTok.IDENTIFIER) && mode != CDeclarator.ABSTRACT) {
        inner = node(p, CNode.D_NAME, at, 0, sym(p))
        p.pos++
    } elif (kind(p) == int(CTok.LPAREN) && nested_paren(p, mode)) {
        return -1 if (!enter(p))
        p.pos++
        let attrs = attributes(p)
        inner = node(p, CNode.D_PAREN, at, 0, declarator(p, mode), attrs)
        take(p, CTok.RPAREN)
        leave(p)
    } elif (mode == CDeclarator.NAMED) {
        fail(p, "a declarator")
        return -1
    }
    return declarator_suffixes(p, inner, mode)
}

//! A type name at the cursor (C11 6.7.7): specifiers and qualifiers, then an abstract declarator.
def c_type_name(var p : CParser) : int {
    let at = p.pos
    return -1 if (!enter(p))
    var typed = false
    let specs = specifiers(p, CSpecifiers.TYPE_NAME, typed)
    var n = -1
    if (specs < 0) {
        fail(p, "a type name")
    } elif (!typed) {
        untyped(p, at)
    } else {
        n = node(p, CNode.TYPE_NAME, at, 0, specs, declarator(p, CDeclarator.ABSTRACT))
    }
    leave(p)
    return n
}

//! one string literal expression: adjacent literals, left for a later pass to join
def private string_literal(var p : CParser) : int {
    let at = p.pos
    while (kind(p) == int(CTok.STRING_LITERAL)) {
        p.pos++
    }
    return node(p, CNode.STRING, at, 0, at, p.pos - at)
}

//! `.member` and `[index]` designators, as a list; `range` allows GNU `[first ... last]`
def private designators(var p : CParser; gnu_range : bool) : int {
    var list = CList()
    while (!p.failed) {
        let at = p.pos
        if (accept(p, CTok.PERIOD)) {
            if (kind(p) != int(CTok.IDENTIFIER)) {
                fail(p, "a member name")
                break
            }
            c_append(p.ast, list, node(p, CNode.DESIG_FIELD, at, 0, sym(p)))
            p.pos++
        } elif (accept(p, CTok.LBRACKET)) {
            let first = c_constant_expression(p)
            let last = gnu_range && accept(p, CTok.ELLIPSIS) ? c_constant_expression(p) : -1
            take(p, CTok.RBRACKET)
            c_append(p.ast, list, node(p, CNode.DESIG_INDEX, at, 0, first, last))
        } else {
            break
        }
    }
    return list.head
}

//! `{ [designators =] initializer, ... [,] }` at the cursor
def private init_list(var p : CParser) : int {
    let at = p.pos
    return -1 if (!enter(p))
    p.pos++
    var items = CList()
    while (!p.failed && kind(p) != int(CTok.RBRACE)) {
        let item_at = p.pos
        let desigs = designators(p, true)
        if (desigs >= 0) {
            take(p, CTok.ASSIGN)
        } elif (kind(p) == int(CTok.IDENTIFIER) && kind_at(p, 1) == int(CTok.COLON)) {
            refuse(p, "the old GNU designator 'member:'")
            break
        }
        let value = kind(p) == int(CTok.LBRACE) ? init_list(p) : c_assignment(p)
        c_append(p.ast, items, node(p, CNode.INIT_ITEM, item_at, 0, desigs, value))
        break if (!accept(p, CTok.COMMA))
    }
    take(p, CTok.RBRACE)
    leave(p)
    return node(p, CNode.INIT_LIST, at, 0, items.head)
}

def private postfix(var p : CParser; first : int) : int {
    var lhs = first
    while (!p.failed) {
        let at = start_of(p, lhs)
        let k = kind(p)
        if (accept(p, CTok.LBRACKET)) {
            let index = c_expression(p)
            take(p, CTok.RBRACKET)
            lhs = node(p, CNode.INDEX, at, 0, lhs, index)
        } elif (accept(p, CTok.LPAREN)) {
            var args = CList()
            if (kind(p) != int(CTok.RPAREN)) {
                c_append(p.ast, args, c_assignment(p))
                while (!p.failed && accept(p, CTok.COMMA)) {
                    c_append(p.ast, args, c_assignment(p))
                }
            }
            take(p, CTok.RPAREN)
            lhs = node(p, CNode.CALL, at, 0, lhs, args.head)
        } elif (k == int(CTok.PERIOD) || k == int(CTok.ARROW)) {
            p.pos++
            if (kind(p) != int(CTok.IDENTIFIER)) {
                fail(p, "a member name")
                break
            }
            lhs = node(p, CNode.MEMBER, at, k, lhs, sym(p))
            p.pos++
        } elif (k == int(CTok.INC) || k == int(CTok.DEC)) {
            p.pos++
            lhs = node(p, CNode.POSTFIX, at, k, lhs)
        } else {
            break
        }
    }
    return lhs
}

//! `(T){...}` after its type name `t`, the cursor at `{`; postfix operators may follow it
def private compound_literal(var p : CParser; at, t : int) : int {
    let list = init_list(p)
    return postfix(p, node(p, CNode.COMPOUND_LITERAL, at, 0, t, list))
}

//! `__builtin_offsetof(T, member-designator)`, the cursor past the keyword
def private offsetof_expr(var p : CParser; at : int) : int {
    take(p, CTok.LPAREN)
    let t = c_type_name(p)
    take(p, CTok.COMMA)
    var path = CList()
    if (kind(p) != int(CTok.IDENTIFIER)) {
        fail(p, "a member name")
        return -1
    }
    c_append(p.ast, path, node(p, CNode.DESIG_FIELD, p.pos, 0, sym(p)))
    p.pos++
    c_append(p.ast, path, designators(p, false))
    take(p, CTok.RPAREN)
    return node(p, CNode.OFFSETOF, at, 0, t, path.head)
}

def private primary(var p : CParser) : int {
    let at = p.pos
    let k = kind(p)
    if (k == int(CTok.IDENTIFIER) && !c_is_typedef(p, sym(p))) {
        p.pos++
        return node(p, CNode.IDENT, at, 0, p.unit.toks[at].sym)
    } elif (k == int(CTok.INT_CONSTANT) || k == int(CTok.FLOAT_CONSTANT) || k == int(CTok.CHAR_CONSTANT) || k == int(CTok.FUNC_NAME)) {
        p.pos++
        let kinds = fixed_array(CNode.INT, CNode.FLOAT, CNode.CHAR)
        return node(p, k == int(CTok.FUNC_NAME) ? CNode.FUNC_NAME : kinds[k - int(CTok.INT_CONSTANT)], at, 0, at)
    } elif (k == int(CTok.STRING_LITERAL)) {
        return string_literal(p)
    } elif (k == int(CTok.LPAREN)) {
        if (kind_at(p, 1) == int(CTok.LBRACE)) {
            refuse(p, "a statement expression")
            return -1
        }
        p.pos++
        let e = c_expression(p)
        take(p, CTok.RPAREN)
        return node(p, CNode.PAREN, at, 0, e)
    } elif (k == int(CTok.VA_ARG)) {
        p.pos++
        take(p, CTok.LPAREN)
        let e = c_assignment(p)
        take(p, CTok.COMMA)
        let t = c_type_name(p)
        take(p, CTok.RPAREN)
        return node(p, CNode.VA_ARG, at, 0, e, t)
    } elif (k == int(CTok.OFFSETOF)) {
        p.pos++
        return offsetof_expr(p, at)
    } elif (k == int(CTok.TYPES_COMPATIBLE)) {
        p.pos++
        take(p, CTok.LPAREN)
        let first = c_type_name(p)
        take(p, CTok.COMMA)
        let second = c_type_name(p)
        take(p, CTok.RPAREN)
        return node(p, CNode.TYPES_COMPATIBLE, at, 0, first, second)
    }
    let what = refused_word(k)
    if (!empty(what)) {
        refuse(p, what)
    } else {
        fail(p, "an expression")
    }
    return -1
}

//! `sizeof`, `_Alignof` or `__alignof__` at `at`, the cursor past it: of a parenthesised type name,
//! or of an expression, a compound literal included
[arch(at="ARCHITECTURE_PARSER.md#c-expressions")]
def private size_or_align(var p : CParser; at, k : int) : int {
    let is_size = k == int(CTok.SIZEOF)
    let op = is_size ? 0 : k
    if (kind(p) == int(CTok.LPAREN) && type_starts_at(p, p.pos + 1)) {
        let lp = p.pos
        p.pos++
        let t = c_type_name(p)
        take(p, CTok.RPAREN)
        if (kind(p) != int(CTok.LBRACE)) {
            return node(p, is_size ? CNode.SIZEOF_TYPE : CNode.ALIGNOF_TYPE, at, op, t)
        }
        let lit = compound_literal(p, lp, t)
        return node(p, is_size ? CNode.SIZEOF_EXPR : CNode.ALIGNOF_EXPR, at, op, lit)
    }
    let e = unary(p)
    return node(p, is_size ? CNode.SIZEOF_EXPR : CNode.ALIGNOF_EXPR, at, op, e)
}

//! `k` starts a unary expression by a prefix operator or keyword
//! a compound literal where a unary expression stands (the operand of `++`, `--`, `sizeof`): `(`, a
//! type name, `)` and the `{` a cast would not need
def private paren_compound_literal(var p : CParser) : int {
    let at = p.pos
    return -1 if (!enter(p))
    p.pos++
    let t = c_type_name(p)
    take(p, CTok.RPAREN)
    var n = -1
    if (kind(p) == int(CTok.LBRACE)) {
        n = compound_literal(p, at, t)
    } else {
        fail(p, "'\{' after a parenthesised type name")
    }
    leave(p)
    return n
}

def private is_prefix(k : int) : bool {
    return (k == int(CTok.INC) || k == int(CTok.DEC) || k == int(CTok.AMP) || k == int(CTok.STAR) || k == int(CTok.PLUS)
        || k == int(CTok.MINUS) || k == int(CTok.TILDE) || k == int(CTok.EXCLAIM) || k == int(CTok.SIZEOF)
        || k == int(CTok.ALIGNOF) || k == int(CTok.GNU_ALIGNOF) || k == int(CTok.EXTENSION))
}

def private unary(var p : CParser) : int {
    let at = p.pos
    let k = kind(p)
    if (k == int(CTok.AND_AND)) {
        refuse(p, "a label address (&&label)")
        return -1
    } elif (k == int(CTok.LPAREN) && type_starts_at(p, p.pos + 1)) {
        return paren_compound_literal(p)
    } elif (!is_prefix(k)) {
        return postfix(p, primary(p))
    }
    return -1 if (!enter(p))
    var n = -1
    if (k == int(CTok.INC) || k == int(CTok.DEC)) {
        p.pos++
        n = node(p, CNode.UNARY, at, k, unary(p))
    } elif (k != int(CTok.SIZEOF) && k != int(CTok.ALIGNOF) && k != int(CTok.GNU_ALIGNOF) && k != int(CTok.EXTENSION)) {
        p.pos++
        n = node(p, CNode.UNARY, at, k, cast_expr(p))
    } elif (k == int(CTok.SIZEOF) || k == int(CTok.ALIGNOF) || k == int(CTok.GNU_ALIGNOF)) {
        p.pos++
        n = size_or_align(p, at, k)
    } else {
        p.pos++
        n = node(p, CNode.EXTENSION, at, 0, cast_expr(p))
    }
    leave(p)
    return n
}

//! a cast `(T) e` or a compound literal `(T){...}` when a type name follows the `(`, else a unary
//! expression
[arch(at="ARCHITECTURE_PARSER.md#c-expressions")]
def private cast_expr(var p : CParser) : int {
    return unary(p) if (kind(p) != int(CTok.LPAREN) || !type_starts_at(p, p.pos + 1))
    let at = p.pos
    return -1 if (!enter(p))
    p.pos++
    let t = c_type_name(p)
    take(p, CTok.RPAREN)
    var n = -1
    if (kind(p) == int(CTok.LBRACE)) {
        n = compound_literal(p, at, t)
    } else {
        n = node(p, CNode.CAST, at, 0, t, cast_expr(p))
    }
    leave(p)
    return n
}

//! the binding level of binary operator `k` (C11 6.5.5 to 6.5.14), 0 for a token that is none
def private binary_level(k : int) : int {
    if (k == int(CTok.STAR) || k == int(CTok.SLASH) || k == int(CTok.PERCENT)) {
        return 10
    } elif (k == int(CTok.PLUS) || k == int(CTok.MINUS)) {
        return 9
    } elif (k == int(CTok.SHL) || k == int(CTok.SHR)) {
        return 8
    } elif (k == int(CTok.LESS) || k == int(CTok.GREATER) || k == int(CTok.LE) || k == int(CTok.GE)) {
        return 7
    } elif (k == int(CTok.EQ) || k == int(CTok.NE)) {
        return 6
    } elif (k == int(CTok.AMP)) {
        return 5
    } elif (k == int(CTok.CARET)) {
        return 4
    } elif (k == int(CTok.PIPE)) {
        return 3
    } elif (k == int(CTok.AND_AND)) {
        return 2
    }
    return k == int(CTok.OR_OR) ? 1 : 0
}

//! the operator on top of `p.operators` applied to the two operands on top of `p.operands`
def private reduce(var p : CParser) {
    let top = length(p.operands) - 1
    let lhs = p.operands[top - 1]
    let rhs = p.operands[top]
    let op = p.operators[length(p.operators) - 1]
    p.operators |> pop()
    p.operands |> pop()
    let n = node(p, CNode.BINARY, start_of(p, lhs), op, lhs, rhs)
    p.operands[top - 1] = n
}

//! the left-associative binary operators by operator precedence over explicit stacks, so a binary
//! expression of any shape costs no recursion: an operator waits on `p.operators` until one that
//! binds no tighter follows it
[arch(at="ARCHITECTURE_PARSER.md#c-expressions")]
def private binary(var p : CParser) : int {
    let base = length(p.operators)
    let first = cast_expr(p)
    p.operands |> push(first)
    while (!p.failed) {
        let k = kind(p)
        let level = binary_level(k)
        break if (level == 0)
        while (length(p.operators) > base && binary_level(p.operators[length(p.operators) - 1]) >= level) {
            reduce(p)
        }
        p.operators |> push(k)
        p.pos++
        let operand = cast_expr(p)
        p.operands |> push(operand)
    }
    while (length(p.operators) > base) {
        reduce(p)
    }
    let result = p.operands[length(p.operands) - 1]
    p.operands |> pop()
    return result
}

def private conditional(var p : CParser) : int {
    let c = binary(p)
    return c if (p.failed || !accept(p, CTok.QUESTION))
    let then_value = kind(p) != int(CTok.COLON) ? c_expression(p) : -1
    take(p, CTok.COLON)
    return -1 if (!enter(p))
    let else_value = conditional(p)
    leave(p)
    return node(p, CNode.COND, start_of(p, c), 0, c, then_value, else_value)
}

//! A constant expression at the cursor (C11 6.6): a conditional expression, one nesting level.
[arch(at="ARCHITECTURE_PARSER.md#c-parser-errors")]
def c_constant_expression(var p : CParser) : int {
    return -1 if (!enter(p))
    let n = conditional(p)
    leave(p)
    return n
}

def private is_assign_op(k : int) : bool => k == int(CTok.ASSIGN) || (k >= int(CTok.MUL_ASSIGN) && k <= int(CTok.OR_ASSIGN))

//! An assignment expression at the cursor (C11 6.5.16); its left operand is not checked here.
[arch(at="ARCHITECTURE_PARSER.md#c-parser-errors")]
def c_assignment(var p : CParser) : int {
    return -1 if (!enter(p))
    var n = conditional(p)
    let k = kind(p)
    if (!p.failed && is_assign_op(k)) {
        p.pos++
        let rhs = c_assignment(p)
        n = node(p, CNode.ASSIGN, start_of(p, n), k, n, rhs)
    }
    leave(p)
    return n
}

//! An expression at the cursor (C11 6.5.17): assignments joined by the comma operator.
def c_expression(var p : CParser) : int {
    var lhs = c_assignment(p)
    while (!p.failed && accept(p, CTok.COMMA)) {
        let rhs = c_assignment(p)
        lhs = node(p, CNode.BINARY, start_of(p, lhs), int(CTok.COMMA), lhs, rhs)
    }
    return lhs
}

//! The end of the unit at the cursor, or an error naming the token there.
def c_expect_end(var p : CParser) {
    if (!p.failed && kind(p) != int(CTok.EOF)) {
        fail(p, "end of input")
    }
}

//! The function declarator a declarator applies to its name through parentheses only: the one a
//! function definition's parameters come from; -1 when there is none.
def c_name_function(ast : CAst; d : int) : int {
    var at = d
    while (at >= 0) {
        let n = ast.nodes[at]
        if (n.kind == CNode.D_FUNCTION) {
            var inner = n.a
            while (inner >= 0 && ast.nodes[inner].kind == CNode.D_PAREN) {
                inner = ast.nodes[inner].a
            }
            return at if (inner >= 0 && ast.nodes[inner].kind == CNode.D_NAME)
        }
        return -1 if (n.kind == CNode.D_NAME)
        at = n.a
    }
    return -1
}

//! the specifier list `specs` holds `typedef`
def private declares_typedef(ast : CAst; specs : int) : bool {
    var at = specs
    while (at >= 0) {
        return true if (ast.nodes[at].kind == CNode.SPEC_KEYWORD && ast.nodes[at].op == int(CTok.TYPEDEF))
        at = ast.nodes[at].next
    }
    return false
}

//! the first old-style identifier list in declarator `d`, -1 when it has none
def private identifier_list_in(ast : CAst; d : int) : int {
    var at = d
    while (at >= 0) {
        let n = ast.nodes[at]
        return at if (n.kind == CNode.D_FUNCTION && n.op == 2)
        return -1 if (n.kind == CNode.D_NAME)
        at = n.a
    }
    return -1
}

//! `_Static_assert(condition, message)` and its `;`, the cursor at the keyword; the message is
//! optional, as clang takes it under gnu17
def private static_assert_decl(var p : CParser) : int {
    let at = p.pos
    p.pos++
    take(p, CTok.LPAREN)
    let condition = c_constant_expression(p)
    var message = -1
    if (accept(p, CTok.COMMA)) {
        if (kind(p) != int(CTok.STRING_LITERAL)) {
            fail(p, "a string literal")
            return -1
        }
        message = string_literal(p)
    }
    take(p, CTok.RPAREN)
    take(p, CTok.SEMI)
    return node(p, CNode.STATIC_ASSERT, at, 0, condition, message)
}

//! a declarator's tail after it: a GNU asm label `__asm__("name")`, then attributes; `before` holds
//! the attributes written before the declarator
def private init_declarator(var p : CParser; d, before : int) : int {
    var asm_name = -1
    if (kind(p) == int(CTok.ASM)) {
        let at = p.pos
        p.pos++
        take(p, CTok.LPAREN)
        if (kind(p) != int(CTok.STRING_LITERAL)) {
            fail(p, "a string literal")
            return -1
        }
        let name = string_literal(p)
        take(p, CTok.RPAREN)
        asm_name = node(p, CNode.ASM_LABEL, at, 0, name)
    }
    var attrs = CList()
    c_append(p.ast, attrs, before)
    c_append(p.ast, attrs, attributes(p))
    let n = node(p, CNode.INIT_DECL, start_of(p, d), 0, d, -1, asm_name)
    p.ast.nodes[n].d = attrs.head
    return n
}

//! Where a declaration stands, which decides what it may be: at file scope a function definition,
//! a declaration of attributes alone and a `;` alone too; in a block; or in an old-style
//! definition's declaration list, where it types names of the identifier list.
enum CPlace {
    FILE
    BLOCK
    OLD_STYLE
}

//! the specifier list `specs` holds attributes only
def private attributes_only(ast : CAst; specs : int) : bool {
    var at = specs
    while (at >= 0) {
        return false if (ast.nodes[at].kind != CNode.ATTRIBUTE)
        at = ast.nodes[at].next
    }
    return true
}

//! the first declarator `d` and its init-declarator `id` at file scope start a function definition:
//! `d` declares a function whose own declarator holds the only identifier list, `id` has no asm
//! label, the specifiers no `typedef`, and a body follows, or a declaration list after an
//! identifier list
[arch(at="ARCHITECTURE_PARSER.md#c-definitions")]
def private starts_definition(p : CParser; d, id : int; binding : CBinding) : bool {
    let f = c_name_function(p.ast, d)
    return false if (p.failed || f < 0 || binding != CBinding.ORDINARY || p.ast.nodes[id].c >= 0)
    let ids = identifier_list_in(p.ast, d)
    return false if (ids >= 0 && ids != f)
    let k = kind(p)
    return k == int(CTok.LBRACE) || (ids == f && k != int(CTok.SEMI) && k != int(CTok.COMMA) && k != int(CTok.ASSIGN))
}

//! the name declarator `d` declares in an old-style definition's declaration list, typed by `d` in
//! the identifier list of function declarator `f`; an error at the name when the list does not hold
//! it or a declaration before typed it
[arch(at="ARCHITECTURE_PARSER.md#c-definitions")]
def private type_old_style_param(var p : CParser; f, d : int) {
    let name = name_node(p.ast, d)
    var param = p.ast.nodes[f].b
    while (param >= 0 && p.ast.nodes[param].a != p.ast.nodes[name].a) {
        param = p.ast.nodes[param].next
    }
    if (param < 0 || p.ast.nodes[param].b >= 0) {
        p.pos = p.ast.nodes[name].tok
        fail(p, param < 0 ? "a name of the identifier list" : "a parameter declared once")
        return
    }
    p.ast.nodes[param].b = d
}

//! Bind the parameter names of function declarator `f` as ordinary identifiers in the innermost
//! scope: the scope a definition's body is read in.
[arch(at="ARCHITECTURE_PARSER.md#c-definitions")]
def c_parameters_declare(var p : CParser; f : int) {
    var param = p.ast.nodes[f].b
    while (param >= 0) {
        let n = p.ast.nodes[param]
        c_declare(p, n.kind == CNode.IDENT_PARAM ? n.a : c_declarator_name(p.ast, n.b), CBinding.ORDINARY)
        param = n.next
    }
}

//! a function body at its `{`, kept as its tokens to the `}` that balances it
def private body(var p : CParser) : int {
    let at = p.pos
    let last = balanced(p, CTok.LBRACE, CTok.RBRACE, "'\}' closing the function body")
    return last < 0 ? -1 : node(p, CNode.BODY, at, 0, at, last)
}

//! a function definition after its first declarator, whose init-declarator is `id` and function
//! declarator `f`: the name bound in the scope around it, then a scope for the parameters, which an
//! old-style declaration list types, every name of the identifier list once; then the body
[arch(at="ARCHITECTURE_PARSER.md#c-definitions")]
def private definition(var p : CParser; at, extension, specs, id, f : int) : int {
    c_declare(p, c_declarator_name(p.ast, p.ast.nodes[id].a), CBinding.ORDINARY)
    c_scope_open(p)
    var old = CList()
    if (p.ast.nodes[f].op == 2) {
        while (!p.failed && kind(p) != int(CTok.LBRACE)) {
            c_append(p.ast, old, declaration(p, CPlace.OLD_STYLE, f))
        }
        var param = p.ast.nodes[f].b
        while (!p.failed && param >= 0) {
            if (p.ast.nodes[param].b < 0) {
                fail(p, "a declaration of parameter '{pp_symbol_text(p.unit.lx, p.ast.nodes[param].a)}'")
            }
            param = p.ast.nodes[param].next
        }
    }
    c_parameters_declare(p, f)
    let text = p.failed ? -1 : body(p)
    c_scope_close(p)
    let n = node(p, CNode.FUNC_DEF, at, extension, specs, id, old.head)
    p.ast.nodes[n].d = text
    return n
}

//! a declaration at the cursor where `place` says, and its `;`, or a function definition at file
//! scope; `f` is the function declarator of an old-style declaration list
[arch(at="ARCHITECTURE_PARSER.md#c-declarations")]
def private declaration(var p : CParser; place : CPlace; f : int) : int {
    let at = p.pos
    var extension = 0
    while (accept(p, CTok.EXTENSION)) {
        extension = 1
    }
    let k = kind(p)
    if (k == int(CTok.STATIC_ASSERT) && place != CPlace.OLD_STYLE) {
        return static_assert_decl(p)
    } elif (k == int(CTok.ASM) && place == CPlace.FILE) {
        refuse(p, "a file-scope asm")
        return -1
    } elif (k == int(CTok.SEMI) && place == CPlace.FILE) {
        p.pos++
        return -1
    }
    let specs_at = p.pos
    var typed = false
    let specs = specifiers(p, place == CPlace.OLD_STYLE ? CSpecifiers.PARAMETER : CSpecifiers.DECLARATION, typed)
    if (specs < 0) {
        fail(p, "a declaration")
        return -1
    } elif (!typed && !(place == CPlace.FILE && kind(p) == int(CTok.SEMI) && attributes_only(p.ast, specs))) {
        untyped(p, specs_at)
        return -1
    }
    let binding = declares_typedef(p.ast, specs) ? CBinding.TYPEDEF : CBinding.ORDINARY
    var list = CList()
    var first = true
    var more = kind(p) != int(CTok.SEMI)
    while (!p.failed && more) {
        let before = first ? -1 : attributes(p)
        let d = declarator(p, CDeclarator.NAMED)
        let id = init_declarator(p, d, before)
        if (first && place == CPlace.FILE && starts_definition(p, d, id, binding)) {
            return definition(p, at, extension, specs, id, c_name_function(p.ast, d))
        }
        let ids = identifier_list_in(p.ast, d)
        if (ids >= 0 && !p.failed) {
            p.pos = p.ast.nodes[p.ast.nodes[ids].b].tok
            refuse(p, "an identifier list outside a function definition")
            break
        } elif (place == CPlace.OLD_STYLE && !p.failed) {
            type_old_style_param(p, f, d)
        }
        first = false
        c_declare(p, c_declarator_name(p.ast, d), binding)
        if (binding == CBinding.ORDINARY && place != CPlace.OLD_STYLE && accept(p, CTok.ASSIGN)) {
            let value = kind(p) == int(CTok.LBRACE) ? init_list(p) : c_assignment(p)
            if (id >= 0) {
                p.ast.nodes[id].b = value
            }
        }
        c_append(p.ast, list, id)
        more = accept(p, CTok.COMMA)
    }
    take(p, CTok.SEMI)
    return node(p, CNode.DECL, at, extension, specs, list.head)
}

//! A declaration in a block at the cursor and its `;` (C11 6.7): `__extension__`s, specifiers, then
//! init-declarators, each name bound in the innermost scope right after its declarator - as a
//! typedef name under `typedef`, else as an ordinary identifier - so its own initializer sees it.
//! A `_Static_assert` is a declaration too. A function definition has no place here, and an
//! identifier list outside one is refused.
def c_declaration(var p : CParser) : int => declaration(p, CPlace.BLOCK, -1)

//! The unit at the cursor to its end (C11 6.9): its external declarations, function definitions
//! among them, as the list of a `unit` node. A `;` alone declares nothing and makes no node; a
//! file-scope asm is refused.
[arch(at="ARCHITECTURE_PARSER.md#c-definitions")]
def c_unit(var p : CParser) : int {
    let at = p.pos
    var list = CList()
    while (!p.failed && kind(p) != int(CTok.EOF)) {
        c_append(p.ast, list, declaration(p, CPlace.FILE, -1))
    }
    return node(p, CNode.UNIT, at, 0, list.head)
}
