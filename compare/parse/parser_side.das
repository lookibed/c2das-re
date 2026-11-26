options gen2
options indenting = 4

module parser_side public

require strings
require daslib/strings_boost
require clang_side
require ../../frontend/c_parser.das

//! The parser side of the parse oracle (`compare/parse/ARCHITECTURE.md`): a preprocessed unit
//! parsed declaration by declaration, and its tree reduced to the oracle's line form, the types
//! spelled as clang spells them.

def private nd(p : CParser; n : int) : CNodeRec => p.ast.nodes[n]

//! The place token `t` stands at.
def token_place(var p : CParser; t : int) : Place {
    let tok = p.unit.toks[t]
    return Place(file = c_file_name(p.unit, tok.file), line = tok.line, col = tok.col)
}

def private at_text(var p : CParser; n : int) : string => place_text(token_place(p, nd(p, n).tok))

def private symbol(var p : CParser; s : int) : string => s < 0 ? "" : pp_symbol_text(p.unit.lx, s)

//! The value of the integer constant spelled `spelling` in decimal, as clang writes it; "?" for a
//! spelling past 64 bits or not an integer constant.
[arch(at="ARCHITECTURE.md#compared")]
def integer_value(spelling : string) : string {
    var value = 0ul
    var valid = false
    peek_data(spelling) $(b) {
        var stop = length(b)
        while (stop > 0) {
            let suffix = int(b[stop - 1]) | 0x20
            break if (suffix != 'u' && suffix != 'l')
            stop--
        }
        var at = 0
        var base = 10ul
        let lead = stop > 1 && b[0] == uint8('0')
        let prefix = stop > 2 ? int(b[1]) | 0x20 : 0
        if (lead && prefix == 'x') {
            base = 16ul
            at = 2
        } elif (lead && prefix == 'b') {
            base = 2ul
            at = 2
        } elif (lead) {
            base = 8ul
            at = 1
        }
        return if (at >= stop)
        while (at < stop) {
            let c = int(b[at]) | 0x20
            let digit = is_number(c) ? uint64(c - '0') : (c >= 'a' && c <= 'f') ? uint64(c - 'a' + 10) : 99ul
            return if (digit >= base || value > (0xFFFFFFFFFFFFFFFFul - digit) / base)
            value = value * base + digit
            at++
        }
        valid = true
    }
    return "?" if (!valid)
    var digits : array<string>
    while (true) {
        digits |> push(to_char(int(value % 10ul) + '0'))
        value /= 10ul
        break if (value == 0ul)
    }
    return join([for (i in range(length(digits))); digits[length(digits) - 1 - i]], "")
}

// the qualifiers of list `list` in clang's order, `const volatile restrict`; `atomic` answers
// whether `_Atomic` is among them
def private qualifiers(p : CParser; list : int; var atomic : bool&) : string {
    var has : bool[3]
    var at = list
    while (at >= 0) {
        let n = nd(p, at)
        if (n.kind == CNode.SPEC_KEYWORD) {
            if (n.op == int(CTok.CONST)) {
                has[0] = true
            } elif (n.op == int(CTok.VOLATILE)) {
                has[1] = true
            } elif (n.op == int(CTok.RESTRICT)) {
                has[2] = true
            } elif (n.op == int(CTok.ATOMIC)) {
                atomic = true
            }
        }
        at = n.next
    }
    let words <- fixed_array("const", "volatile", "restrict")
    return join([for (w, i in words, count()); w; where has[i]], " ")
}

// how many times keyword `k` stands in a specifier list, from the counts by kind past `VOID`
def private keyword_count(count : int[64]; k : CTok) : int => count[int(k) - int(CTok.VOID)]

// the canonical name of the builtin type the keyword counts `count` make, clang's
def private builtin_name(count : int[64]) : string {
    let unsigned = keyword_count(count, CTok.UNSIGNED) > 0
    let longs = keyword_count(count, CTok.LONG)
    if (keyword_count(count, CTok.VOID) > 0) {
        return "void"
    } elif (keyword_count(count, CTok.BOOL) > 0) {
        return "_Bool"
    } elif (keyword_count(count, CTok.CHAR) > 0) {
        return unsigned ? "unsigned char" : keyword_count(count, CTok.SIGNED) > 0 ? "signed char" : "char"
    } elif (keyword_count(count, CTok.FLOAT) > 0) {
        return "float"
    } elif (keyword_count(count, CTok.DOUBLE) > 0) {
        return longs > 0 ? "long double" : "double"
    } elif (keyword_count(count, CTok.SHORT) > 0) {
        return unsigned ? "unsigned short" : "short"
    } elif (longs > 0) {
        let width = longs > 1 ? "long long" : "long"
        return unsigned ? "unsigned {width}" : width
    }
    let alone = keyword_count(count, CTok.INT) == 0 && keyword_count(count, CTok.SIGNED) == 0 && !unsigned
    // GNU `_Complex` alone is `_Complex double`
    return "double" if (alone && keyword_count(count, CTok.COMPLEX) > 0)
    return unsigned ? "unsigned int" : "int"
}

//! The type specifiers and qualifiers of list `specs` as clang spells the type they make: a
//! builtin type by its canonical name, a typedef name, a tag with its keyword; "?" for `typeof`,
//! whose spelling is not the tree's to tell.
[arch(at="ARCHITECTURE.md#compared")]
def base_spelling(var p : CParser; specs : int) : string {
    var count : int[64]
    var named = ""
    var at = specs
    while (at >= 0) {
        let n = nd(p, at)
        if (n.kind == CNode.SPEC_KEYWORD) {
            if (n.op >= int(CTok.VOID) && n.op < int(CTok.VOID) + 64) {
                count[n.op - int(CTok.VOID)]++
            }
        } elif (n.kind == CNode.SPEC_TYPEDEF_NAME) {
            named = symbol(p, n.a)
        } elif (n.kind == CNode.SPEC_RECORD || n.kind == CNode.SPEC_ENUM) {
            named = "{n.kind == CNode.SPEC_ENUM ? "enum" : c_kind_name(n.op)} {symbol(p, n.a)}"
        } elif (n.kind == CNode.SPEC_TYPEOF_EXPR || n.kind == CNode.SPEC_TYPEOF_TYPE) {
            return "?"
        }
        at = n.next
    }
    var base = empty(named) ? builtin_name(count) : named
    if (keyword_count(count, CTok.COMPLEX) > 0) {
        base = "_Complex {base}"
    }
    var atomic = false
    let quals = qualifiers(p, specs, atomic)
    if (atomic) {
        base = "_Atomic({base})"
    }
    return empty(quals) ? base : "{quals} {base}"
}

// the size of an array declarator as clang spells it: the value of an integer constant, empty for
// none, `*` for `[*]`, `?` for any other expression (clang writes its value or its text)
def private array_size(p : CParser; n : CNodeRec) : string {
    return "*" if ((n.op & 2) != 0)
    return "" if (n.b < 0)
    let size = nd(p, n.b)
    return size.kind == CNode.INT ? integer_value(c_spelling(p.unit, size.a)) : "?"
}

//! The type that specifier list `specs` and declarator `d` make, as clang spells it. `decay`
//! spells a parameter: an array adjusts to a pointer and a function to a pointer to it.
//! `completed` marks a declarator whose initializer completes an array of no size, so its size is
//! `?`.
[arch(at="ARCHITECTURE.md#compared")]
def spell_type(var p : CParser; specs, d : int; decay, completed : bool) : string {
    let base = base_spelling(p, specs)
    return "?" if (base == "?")
    var chain : array<int>
    var at = d
    while (at >= 0) {
        let n = nd(p, at)
        if (n.kind == CNode.D_POINTER || n.kind == CNode.D_ARRAY || n.kind == CNode.D_FUNCTION) {
            chain |> push(at)
        }
        at = n.kind == CNode.D_NAME ? -1 : n.a
    }
    // the node nearest the name is the outermost type: the text grows from it to the base, on its
    // left (pointers, the parentheses' opening) and on its right (suffixes, the closing)
    var left, right : array<string>
    var after_pointer = false
    for (back in range(length(chain))) {
        let n = nd(p, chain[length(chain) - 1 - back])
        let outermost = back == 0
        var atomic = false
        if (n.kind == CNode.D_POINTER || (outermost && decay && n.kind == CNode.D_ARRAY)) {
            let q = qualifiers(p, n.kind == CNode.D_POINTER ? n.b : n.c, atomic)
            return "?" if (atomic)
            // a blank parts the qualifiers from what stands left of the text, never from a suffix
            let blank = empty(q) || empty(left) ? "" : " "
            left |> push("*{q}{blank}")
            after_pointer = true
            continue
        }
        if (outermost && decay) {
            left |> push("*")
            after_pointer = true
        }
        if (after_pointer) {
            left |> push("(")
            right |> push(")")
        }
        if (n.kind == CNode.D_ARRAY) {
            let size = array_size(p, n)
            right |> push("[{(empty(size) && completed && outermost) ? "?" : size}]")
        } else {
            let params = parameter_types(p, n)
            return "?" if (params == "?")
            right |> push("({params})")
        }
        after_pointer = false
    }
    return base if (empty(left) && empty(right))
    let text = join([for (i in range(length(left))); left[length(left) - 1 - i]], "") + join(right, "")
    return starts_with(text, "[") ? "{base}{text}" : "{base} {text}"
}

// the single parameter `(void)`
def private only_void(p : CParser; f : CNodeRec) : bool {
    return false if (f.b < 0 || nd(p, f.b).next >= 0 || nd(p, f.b).b >= 0 || nd(p, f.b).kind != CNode.PARAM)
    let specs = nd(p, f.b).a
    return nd(p, specs).kind == CNode.SPEC_KEYWORD && nd(p, specs).op == int(CTok.VOID) && nd(p, specs).next < 0
}

// the parameter types of function declarator `f` as clang spells them; "?" when one is not the
// tree's to tell, or the list is an old-style identifier list
def private parameter_types(var p : CParser; f : CNodeRec) : string {
    return "?" if (f.op == 2)
    return "void" if (only_void(p, f))
    var parts : array<string>
    var at = f.b
    while (at >= 0) {
        let prm = nd(p, at)
        let t = spell_type(p, prm.a, prm.b, true, false)
        return "?" if (t == "?")
        parts |> push(t)
        at = prm.next
    }
    if (f.op == 1) {
        parts |> push("...")
    }
    return join(parts, ", ")
}

def private type_name_text(var p : CParser; t : int; completed : bool) : string => "\"{spell_type(p, nd(p, t).a, nd(p, t).b, false, completed)}\""

// the expressions of list `list`, blank-separated
def private list_text(var p : CParser; list : int) : string {
    var parts : array<string>
    var at = list
    while (at >= 0) {
        parts |> push(parser_expression(p, at))
        at = nd(p, at).next
    }
    return join(parts, " ")
}

//! The expression under node `n` in the oracle's form (`ARCHITECTURE.md#compared`).
[arch(at="ARCHITECTURE.md#compared")]
def parser_expression(var p : CParser; n : int) : string {
    return "-" if (n < 0)
    let e = nd(p, n)
    let at = at_text(p, n)
    let k = e.kind
    if (k == CNode.IDENT) {
        return "(ident{at} {symbol(p, e.a)})"
    } elif (k == CNode.INT) {
        return "(int{at} {integer_value(c_spelling(p.unit, e.a))})"
    } elif (k == CNode.FLOAT || k == CNode.CHAR || k == CNode.STRING || k == CNode.FUNC_NAME || k == CNode.INIT_LIST || k == CNode.OFFSETOF) {
        return "({NODE_FORMS[int(k)]._0}{at})"
    } elif (k == CNode.PAREN || k == CNode.EXTENSION || k == CNode.SIZEOF_EXPR) {
        return "({NODE_FORMS[int(k)]._0}{at} {parser_expression(p, e.a)})"
    } elif (k == CNode.BINARY || k == CNode.ASSIGN || k == CNode.INDEX) {
        let op = k == CNode.INDEX ? "" : " {c_kind_name(e.op)}"
        return "({NODE_FORMS[int(k)]._0}{at}{op} {parser_expression(p, e.a)} {parser_expression(p, e.b)})"
    } elif (k == CNode.COND) {
        return "(cond{at} {parser_expression(p, e.a)} {parser_expression(p, e.b)} {parser_expression(p, e.c)})"
    } elif (k == CNode.UNARY || k == CNode.POSTFIX) {
        return "({NODE_FORMS[int(k)]._0}{at} {c_kind_name(e.op)} {parser_expression(p, e.a)})"
    } elif (k == CNode.CAST) {
        return "(cast{at} {type_name_text(p, e.a, false)} {parser_expression(p, e.b)})"
    } elif (k == CNode.SIZEOF_TYPE) {
        return "(sizeof_type{at} {type_name_text(p, e.a, false)})"
    } elif (k == CNode.ALIGNOF_EXPR || k == CNode.ALIGNOF_TYPE) {
        let keyword = e.op == int(CTok.ALIGNOF) ? "alignof" : "__alignof"
        let operand = k == CNode.ALIGNOF_TYPE ? type_name_text(p, e.a, false) : parser_expression(p, e.a)
        return "({NODE_FORMS[int(k)]._0}{at} {keyword} {operand})"
    } elif (k == CNode.CALL) {
        return "(call{at} {parser_expression(p, e.a)} [{list_text(p, e.b)}])"
    } elif (k == CNode.MEMBER) {
        return "(member{at} {c_kind_name(e.op)} {parser_expression(p, e.a)} {symbol(p, e.b)})"
    } elif (k == CNode.COMPOUND_LITERAL) {
        return "(compound_literal{at} {type_name_text(p, e.a, true)} {parser_expression(p, e.b)})"
    } elif (k == CNode.VA_ARG) {
        return "(va_arg{at} {parser_expression(p, e.a)} {type_name_text(p, e.b, false)})"
    } elif (k == CNode.TYPES_COMPATIBLE) {
        return "(types_compatible{at} {type_name_text(p, e.a, false)} {type_name_text(p, e.b, false)})"
    }
    return "(unknown {NODE_FORMS[int(k)]._0}{at})"
}

// the specifier list `specs` holds keyword `k`
def private has_keyword(p : CParser; specs : int; k : CTok) : bool {
    var at = specs
    while (at >= 0) {
        return true if (nd(p, at).kind == CNode.SPEC_KEYWORD && nd(p, at).op == int(k))
        at = nd(p, at).next
    }
    return false
}

// the flags of a declaration's line from its specifiers, in the clang side's order
def private specifier_flags(p : CParser; specs : int) : string {
    var flags = ""
    if (has_keyword(p, specs, CTok.STATIC)) {
        flags += " static"
    } elif (has_keyword(p, specs, CTok.EXTERN)) {
        flags += " extern"
    }
    if (has_keyword(p, specs, CTok.THREAD_LOCAL)) {
        flags += " thread_local"
    }
    if (has_keyword(p, specs, CTok.INLINE)) {
        flags += " inline"
    }
    return flags
}

// the `D_NAME` node of declarator `d`, -1 for an abstract one
def private name_node(p : CParser; d : int) : int {
    var at = d
    while (at >= 0) {
        return at if (nd(p, at).kind == CNode.D_NAME)
        at = nd(p, at).a
    }
    return -1
}

//! The lines of the file-scope declaration `n`, each with the file it stands in: one per
//! declarator, or the `_Static_assert`'s.
[arch(at="ARCHITECTURE.md#compared")]
def parser_lines(var p : CParser; n : int) : array<FormLine> {
    var lines : array<FormLine>
    let decl = nd(p, n)
    if (decl.kind == CNode.STATIC_ASSERT) {
        let at = token_place(p, decl.tok)
        lines |> push(FormLine(file = at.file, text = "(static_assert{place_text(at)} {parser_expression(p, decl.a)} {parser_expression(p, decl.b)})"))
        return <- lines
    }
    let specs = decl.a
    let is_typedef = has_keyword(p, specs, CTok.TYPEDEF)
    let flags = specifier_flags(p, specs)
    var id = decl.b
    while (id >= 0) {
        let init = nd(p, id)
        let name = name_node(p, init.a)
        let at = token_place(p, nd(p, name).tok)
        let head = "{symbol(p, nd(p, name).a)}{place_text(at)} \"{spell_type(p, specs, init.a, false, init.b >= 0)}\""
        if (is_typedef) {
            lines |> push(FormLine(file = at.file, text = "(typedef {head})"))
        } else {
            var params = ""
            let f = c_name_function(p.ast, init.a)
            if (f >= 0 && !only_void(p, nd(p, f))) {
                var inscope names : array<string>
                var prm = nd(p, f).b
                while (prm >= 0) {
                    let pn = name_node(p, nd(p, prm).b)
                    names |> push(pn < 0 ? "-" : "{symbol(p, nd(p, pn).a)}{at_text(p, pn)}")
                    prm = nd(p, prm).next
                }
                params = empty(names) ? "" : " [{join(names, " ")}]"
            }
            let value = init.b >= 0 ? " = {parser_expression(p, init.b)}" : ""
            lines |> push(FormLine(file = at.file, text = "(decl {head}{flags}{params}{value})"))
        }
        id = init.next
    }
    return <- lines
}

//! A file-scope declaration the parser refused as a construct it does not parse: the construct,
//! the located message, and its tokens, which the oracle skips.
struct Skipped {
    construct : string
    message : string
    first : int
    last : int
}

//! A unit read declaration by declaration: the file-scope declarations parsed, the ones skipped,
//! and the error that stopped the reading, "" when it read to the end.
struct ParsedUnit {
    items : array<int>
    skipped : array<Skipped>
    skipped_places : table<string; bool>    //!< the place keys of every skipped token
    error : string
}

// the construct a refusal names, "" for an error that is no refusal: `<file>:<line>:<col>: <construct>
// is not parsed`, the construct past the first `: ` that follows a `:<digits>`
def private refused_construct(message : string) : string {
    let tail = " is not parsed"
    return "" if (!ends_with(message, tail))
    var construct = ""
    peek_data(message) $(b) {
        let stop = length(b) - length(tail)
        for (i in range(1, stop)) {
            continue if (b[i] != uint8(':') || b[i + 1] != uint8(' '))
            var j = i - 1
            while (j >= 0 && is_number(int(b[j]))) {
                j--
            }
            if (j >= 0 && j < i - 1 && b[j] == uint8(':')) {
                construct = slice(b, i + 2, stop)
                break
            }
        }
    }
    return construct
}

//! The token past the file-scope declaration that starts at token `first`, by its brackets: its
//! `;` at the outer level, or the `}` that closes a function body - the first brace group when
//! `body`, else a brace group the outer level opens right after a `)`.
[arch(at="ARCHITECTURE.md#stand-in")]
def declaration_end(p : CParser; first : int; body : bool) : int {
    var depth = 0
    var in_body = false
    var at = first
    while (at < p.last) {
        let k = p.unit.toks[at].kind
        if (k == int(CTok.LPAREN) || k == int(CTok.LBRACKET) || k == int(CTok.LBRACE)) {
            if (k == int(CTok.LBRACE) && depth == 0 && (body || (at > first && p.unit.toks[at - 1].kind == int(CTok.RPAREN)))) {
                in_body = true
            }
            depth++
        } elif (k == int(CTok.RPAREN) || k == int(CTok.RBRACKET) || k == int(CTok.RBRACE)) {
            depth--
            return at + 1 if (k == int(CTok.RBRACE) && depth == 0 && in_body)
        } elif (k == int(CTok.SEMI) && depth == 0 && !body) {
            return at + 1
        }
        at++
    }
    return p.last
}

//! The unit `text`, named `name`, read declaration by declaration: the stand-in for the parser's
//! unit entry (`ARCHITECTURE.md#stand-in`). A `;` alone is passed over. A declaration the parser
//! refuses as a construct it does not parse is skipped to its end, and the names clang's
//! declarations `tops` bind in the skipped tokens are bound in the parser's table, so the reading
//! goes on as if the parser had read them. Any other error stops the reading.
[arch(at="ARCHITECTURE.md#stand-in")]
def parse_unit(var p : CParser; text, name : string; tops : array<ClangTop>) : ParsedUnit {
    var unit : ParsedUnit
    if (!c_parser_open_text(p, text, name)) {
        unit.error = p.err
        return <- unit
    }
    while (p.unit.toks[p.pos].kind != int(CTok.EOF)) {
        if (p.unit.toks[p.pos].kind == int(CTok.SEMI)) {
            p.pos++
            continue
        }
        let first = p.pos
        let scopes = length(p.scopes.marks)
        let n = c_declaration(p)
        if (!p.failed) {
            unit.items |> push(n)
            continue
        }
        let construct = refused_construct(p.err)
        if (empty(construct)) {
            unit.error = p.err
            break
        }
        let body = construct == "a function definition" || construct == "an identifier list outside a function definition"
        let stop = declaration_end(p, first, body)
        unit.skipped |> push(Skipped(construct = construct, message = p.err, first = first, last = stop - 1))
        while (length(p.scopes.marks) > scopes) {
            c_scope_close(p)
        }
        var inscope keys : table<string; bool>
        for (t in range(first, stop)) {
            let key = place_key(token_place(p, t))
            keys.insert(key, true)
            unit.skipped_places.insert(key, true)
        }
        for (top in tops) {
            if (keys |> key_exists(top.key)) {
                for (bound in top.names) {
                    c_declare(p, c_symbol(p.unit, bound.name), bound.is_typedef ? CBinding.TYPEDEF : CBinding.ORDINARY)
                }
            }
        }
        p.failed = false
        p.err = ""
        p.depth = 0
        p.operators |> clear()
        p.operands |> clear()
        p.pos = stop
    }
    return <- unit
}
