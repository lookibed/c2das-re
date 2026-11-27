options gen2
options indenting = 4

module parser_side public

require strings
require daslib/strings_boost
require daslib/cmp
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
        } elif ((n.kind == CNode.SPEC_RECORD || n.kind == CNode.SPEC_ENUM) && n.a < 0) {
            // clang names a tag with no name by its place and its owner, which the tree does not spell
            return "?"
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
//! `?`. A part the tree cannot spell is `?` alone, the rest of the type spelled around it.
[arch(at="ARCHITECTURE.md#compared")]
def spell_type(var p : CParser; specs, d : int; decay, completed : bool) : string {
    var chain : array<int>
    var at = d
    while (at >= 0) {
        let n = nd(p, at)
        if (n.kind == CNode.D_POINTER || n.kind == CNode.D_ARRAY || n.kind == CNode.D_FUNCTION) {
            chain |> push(at)
        }
        at = n.kind == CNode.D_NAME ? -1 : n.a
    }
    // the node nearest the name is the outermost type, the first of `outward`
    let outward <- [for (i in range(length(chain))); chain[length(chain) - 1 - i]]
    return spell_chain(p, base_spelling(p, specs), outward, 0, decay, completed, false)
}

// the type of declarator nodes `outward[from..]`, outermost first, around the type `base`: the text
// grows from the outermost node to the base, on its left (pointers, the parentheses' opening) and on
// its right (suffixes, the closing). `bare` spells the node at `from` with no qualifiers: it is
// the pointer an `_Atomic(...)` wraps, the qualifiers written outside it
def private spell_chain(var p : CParser; base : string; outward : array<int>; from : int; decay, completed, bare : bool) : string {
    var left, right : array<string>
    var after_pointer = false
    var inner_base = base
    for (i in range(from, length(outward))) {
        let n = nd(p, outward[i])
        let outermost = i == 0
        if (n.kind == CNode.D_POINTER || (outermost && decay && n.kind == CNode.D_ARRAY)) {
            var atomic = false
            let q = i == from && bare ? "" : qualifiers(p, n.kind == CNode.D_POINTER ? n.b : n.c, atomic)
            if (atomic) {
                // clang spells an `_Atomic` pointer `_Atomic(<the pointer's type>)`, its other
                // qualifiers before it, and the outer parts around that
                let wrapped = spell_chain(p, base, outward, i, false, completed, true)
                inner_base = empty(q) ? "_Atomic({wrapped})" : "{q} _Atomic({wrapped})"
                break
            }
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
            right |> push("({parameter_types(p, n)})")
        }
        after_pointer = false
    }
    return inner_base if (empty(left) && empty(right))
    let text = join([for (i in range(length(left))); left[length(left) - 1 - i]], "") + join(right, "")
    return starts_with(text, "[") ? "{inner_base}{text}" : "{inner_base} {text}"
}

// the single parameter `(void)`
def private only_void(p : CParser; f : CNodeRec) : bool {
    return false if (f.b < 0 || nd(p, f.b).next >= 0 || nd(p, f.b).b >= 0 || nd(p, f.b).kind != CNode.PARAM)
    let specs = nd(p, f.b).a
    return nd(p, specs).kind == CNode.SPEC_KEYWORD && nd(p, specs).op == int(CTok.VOID) && nd(p, specs).next < 0
}

//! The specifiers of the declaration in a definition's old-style declaration list whose
//! init-declarator has declarator `d`; -1 for none.
def old_style_specifiers(p : CParser; d : int) : int {
    for (n in p.ast.nodes) {
        continue if (n.kind != CNode.DECL)
        var id = n.b
        while (id >= 0) {
            return n.a if (nd(p, id).a == d)
            id = nd(p, id).next
        }
    }
    return -1
}

//! The declared type of old-style parameter `ip` (an identifier list's name) as its declaration
//! list types it, adjusted as a parameter; `int` when no declaration names it.
def old_style_type(var p : CParser; ip : int) : string {
    let d = nd(p, ip).b
    return "int" if (d < 0)
    return spell_type(p, old_style_specifiers(p, d), d, true, false)
}

// the type an old-style parameter of declared type `declared` has in its function's type: the
// default argument promotions (C11 6.5.2.2p6), as clang writes the function's type: the integer
// types below `int` and `_Bool` promote to `int`, `float` to `double`, a qualifier of the parameter
// itself is dropped; a typedef name or an enum promotes by a type the tree does not hold, `?`
def private promoted(var p : CParser; ip : int) : string {
    let d = nd(p, ip).b
    return "int" if (d < 0)
    let specs = old_style_specifiers(p, d)
    var declared = spell_type(p, specs, d, true, false)
    var plain = true
    var at = d
    while (at >= 0) {
        let k = nd(p, at).kind
        plain = plain && (k == CNode.D_NAME || k == CNode.D_PAREN)
        at = k == CNode.D_NAME ? -1 : nd(p, at).a
    }
    return declared if (!plain)
    var t = specs
    while (t >= 0) {
        let k = nd(p, t).kind
        return "?" if (k == CNode.SPEC_TYPEDEF_NAME || k == CNode.SPEC_ENUM)
        t = nd(p, t).next
    }
    for (q in fixed_array("const ", "volatile ", "restrict ")) {
        declared = replace(declared, q, "")
    }
    let to_int <- ["char", "signed char", "unsigned char", "short", "unsigned short", "_Bool"]
    return "int" if (has_value(to_int, declared))
    return declared == "float" ? "double" : declared
}

// the parameter types of function declarator `f` as clang spells them; for an old-style
// identifier list, each parameter's promoted type
def private parameter_types(var p : CParser; f : CNodeRec) : string {
    return "void" if (only_void(p, f))
    var parts : array<string>
    var at = f.b
    while (at >= 0) {
        let prm = nd(p, at)
        parts |> push(f.op == 2 ? promoted(p, at) : spell_type(p, prm.a, prm.b, true, false))
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
    } elif (k == CNode.FLOAT || k == CNode.CHAR || k == CNode.STRING || k == CNode.FUNC_NAME || k == CNode.INIT_LIST || k == CNode.OFFSETOF || k == CNode.STMT_EXPR) {
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

// the line of init-declarator `id` of a declaration whose specifiers are `specs`: a typedef's, or
// a declaration's with its flags, its parameter names and its initializer
def private declarator_line(var p : CParser; specs, id : int; is_typedef : bool; flags : string) : FormLine {
    let init = nd(p, id)
    let name = name_node(p, init.a)
    let at = token_place(p, nd(p, name).tok)
    let head = "{symbol(p, nd(p, name).a)}{place_text(at)} \"{spell_type(p, specs, init.a, false, init.b >= 0)}\""
    if (is_typedef) {
        return FormLine(file = at.file, text = "(typedef {head})")
    }
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
    return FormLine(file = at.file, text = "(decl {head}{flags}{params}{value})")
}

// a line at token `tok`'s place with text `text`
def private line_at(var p : CParser; tok : int; text : string) : FormLine => FormLine(file = token_place(p, tok).file, text = text)

// the token of the name of the tag whose keyword is token `keyword`, past any attributes; -1 for none
def private tag_name_token(p : CParser; keyword : int) : int {
    var t = keyword + 1
    while (t < p.last && p.unit.toks[t].kind == int(CTok.ATTRIBUTE)) {
        t++
        var depth = 0
        while (t < p.last) {
            let k = p.unit.toks[t].kind
            t++
            depth += k == int(CTok.LPAREN) ? 1 : k == int(CTok.RPAREN) ? -1 : 0
            break if (depth == 0)
        }
    }
    return p.unit.toks[t].kind == int(CTok.IDENTIFIER) ? t : -1
}

// the lines of a record or enum body that specifier `n` holds: the tag's line, each member's or
// enumerator's, the bodies the members' specifiers hold before them, and `(end)`
[arch(at="ARCHITECTURE.md#compared")]
def private body_lines(var p : CParser; n : int; var lines : array<FormLine>) {
    let tag = nd(p, n)
    let name_tok = tag.a >= 0 ? tag_name_token(p, tag.tok) : -1
    let at_tok = name_tok >= 0 ? name_tok : tag.tok
    let what = tag.kind == CNode.SPEC_ENUM ? "enum" : "record " + c_kind_name(tag.op)
    let tag_name = tag.a >= 0 ? symbol(p, tag.a) : "-"
    lines |> push(line_at(p, at_tok, "({what} {tag_name}{place_text(token_place(p, at_tok))})"))
    var item = tag.c
    while (item >= 0) {
        let m = nd(p, item)
        if (m.kind == CNode.ENUMERATOR) {
            let value = m.b >= 0 ? parser_expression(p, m.b) : "-"
            lines |> push(line_at(p, m.tok, "(enumerator {symbol(p, m.a)}{at_text(p, item)} = {value})"))
        } elif (m.kind == CNode.STATIC_ASSERT) {
            lines |> push_from(parser_lines(p, item))
        } elif (m.kind == CNode.MEMBER_DECL) {
            tag_lines(p, m.a, lines)
            if (m.b < 0) {
                forward_line(p, m.a, lines)
            }
            var md = m.b
            while (md >= 0) {
                let f = nd(p, md)
                var inscope nested : array<int>
                collect_bodies(p, f.a, -1, nested, nested)
                collect_bodies(p, f.b, -1, nested, nested)
                bodies_in_order(p, nested, lines)
                let name = name_node(p, f.a)
                let place_tok = name >= 0 ? nd(p, name).tok : m.tok
                let field_name = name >= 0 ? symbol(p, nd(p, name).a) : "-"
                let width = f.b >= 0 ? " : {parser_expression(p, f.b)}" : ""
                lines |> push(line_at(p, place_tok, "(field {field_name}{place_text(token_place(p, place_tok))} \"{spell_type(p, m.a, f.a, false, false)}\"{width})"))
                md = f.next
            }
        }
        item = m.next
    }
    lines |> push(line_at(p, at_tok, "(end)"))
}

// the body lines of every record or enum body specifier list `specs` holds
def private tag_lines(var p : CParser; specs : int; var lines : array<FormLine>) {
    var at = specs
    while (at >= 0) {
        let k = nd(p, at).kind
        if ((k == CNode.SPEC_RECORD || k == CNode.SPEC_ENUM) && nd(p, at).b == 1) {
            body_lines(p, at, lines)
        }
        at = nd(p, at).next
    }
}

//! What a tag body clang's JSON leaves out stands in: a parameter of a function's own declarator
//! (clang keeps it in the function, which its JSON does not show), or a declarator or a type name
//! inside a function body (clang keeps it in the function's scope, not in the statement).
let NOT_IN_PARAMETER = "a tag body in a function's own parameter declaration"
let NOT_IN_BLOCK = "a tag body in a declarator or a type name inside a function body"

// the tag bodies under node `n` (the node and the lists its fields hold), in `printed`; those in
// the parameters of function declarator `own` itself, in `owned` (a body deeper in such a
// parameter's declarator is in `printed`). The walk stops at a body, whose own members
// `body_lines` reads, and at a statement expression, which is not compared
def private collect_bodies(var p : CParser; n, own : int; var printed, owned : array<int>) {
    return if (n < 0)
    let node = nd(p, n)
    let k = node.kind
    if ((k == CNode.SPEC_RECORD || k == CNode.SPEC_ENUM) && node.b == 1) {
        printed |> push(n)
        return
    }
    return if (k == CNode.STMT_EXPR)
    if (n == own) {
        collect_bodies(p, node.a, own, printed, owned)
        var prm = node.b
        while (prm >= 0) {
            if (nd(p, prm).kind == CNode.PARAM) {
                var spec = nd(p, prm).a
                while (spec >= 0) {
                    collect_bodies(p, spec, -1, owned, owned)
                    spec = nd(p, spec).next
                }
                collect_bodies(p, nd(p, prm).b, -1, printed, owned)
            }
            prm = nd(p, prm).next
        }
        return
    }
    let fields = fixed_array(node.a, node.b, node.c, node.d)
    var roles : int[4]
    peek_data(NODE_FORMS[int(k)]._1) $(form) {
        for (i in range(4)) {
            roles[i] = int(form[i + 1])
        }
    }
    for (role, i in roles, count()) {
        if (role == 'n') {
            collect_bodies(p, fields[i], own, printed, owned)
        } elif (role == 'l') {
            var item = fields[i]
            while (item >= 0) {
                collect_bodies(p, item, own, printed, owned)
                item = nd(p, item).next
            }
        }
    }
}

// the body lines of tag bodies `bodies`, in the order of their tokens: the order clang declares them
def private bodies_in_order(var p : CParser; var bodies : array<int>; var lines : array<FormLine>) {
    sort(bodies) <| cmp_by(nd(p, _).tok)
    for (b in bodies) {
        body_lines(p, b, lines)
    }
}

// a note per body of `bodies`, which the oracle cannot compare, for `reason`
def private note_bodies(var p : CParser; bodies : array<int>; reason : string; var lines : array<FormLine>) {
    lines |> reserve(length(lines) + length(bodies))
    for (b in bodies) {
        lines |> push(FormLine(file = token_place(p, nd(p, b).tok).file, note = reason))
    }
}

// a note per tag body under expression `e` inside a function body
def private note_expression(var p : CParser; e : int; var lines : array<FormLine>) {
    var inscope found : array<int>
    collect_bodies(p, e, -1, found, found)
    note_bodies(p, found, NOT_IN_BLOCK, lines)
}

// the line of a tag declared with no body by specifier list `specs` alone (`struct S;`), none when
// the list holds no such tag
def private forward_line(var p : CParser; specs : int; var lines : array<FormLine>) {
    var at = specs
    while (at >= 0) {
        let n = nd(p, at)
        if ((n.kind == CNode.SPEC_RECORD || n.kind == CNode.SPEC_ENUM) && n.b != 1 && n.a >= 0) {
            let name_tok = tag_name_token(p, n.tok)
            let what = n.kind == CNode.SPEC_ENUM ? "enum" : c_kind_name(n.op)
            lines |> push(line_at(p, name_tok, "(tag {what} {symbol(p, n.a)}{place_text(token_place(p, name_tok))})"))
        }
        at = n.next
    }
}

// a definition's parameter lines, each with the type it is declared with: a prototype's
// parameters adjusted as clang adjusts them, an identifier list's names typed by the declaration
// list
def private parameter_lines(var p : CParser; f : int; var lines : array<FormLine>) {
    return if (f < 0 || only_void(p, nd(p, f)))
    var prm = nd(p, f).b
    while (prm >= 0) {
        let n = nd(p, prm)
        if (n.kind == CNode.IDENT_PARAM) {
            let named = n.b >= 0 ? name_node(p, n.b) : -1
            let at = named >= 0 ? at_text(p, named) : at_text(p, prm)
            lines |> push(line_at(p, n.tok, "(param {symbol(p, n.a)}{at} \"{old_style_type(p, prm)}\")"))
        } else {
            let pn = name_node(p, n.b)
            let head = pn < 0 ? "-" : "{symbol(p, nd(p, pn).a)}{at_text(p, pn)}"
            lines |> push(line_at(p, n.tok, "(param {head} \"{spell_type(p, n.a, n.b, true, false)}\")"))
        }
        prm = n.next
    }
}

// init-declarator `id`'s line with the tag bodies its declarator and initializer hold: outside a
// function body clang lists those of the declarator before the line and those of the initializer
// after it, and keeps those of a function's own parameters, which are noted; inside a function body
// it keeps them all, each noted
def private declarator_lines(var p : CParser; specs, id : int; is_typedef, in_block : bool; flags : string; var lines : array<FormLine>) {
    let init = nd(p, id)
    let own = is_typedef ? -1 : c_name_function(p.ast, init.a)
    var inscope before, owned, after : array<int>
    collect_bodies(p, init.a, own, before, owned)
    collect_bodies(p, init.b, -1, after, after)
    note_bodies(p, owned, NOT_IN_PARAMETER, lines)
    if (in_block) {
        note_bodies(p, before, NOT_IN_BLOCK, lines)
        note_bodies(p, after, NOT_IN_BLOCK, lines)
        lines |> push(declarator_line(p, specs, id, is_typedef, flags))
        return
    }
    bodies_in_order(p, before, lines)
    lines |> push(declarator_line(p, specs, id, is_typedef, flags))
    bodies_in_order(p, after, lines)
}

//! The lines of declaration `n`, each with the file it stands in: the bodies its specifiers hold,
//! a tag it declares with no body, then one line per declarator with the bodies it holds, or the
//! `_Static_assert`'s; for a function definition the bodies its old-style declaration list holds
//! (clang lists them at file scope), its line, its parameters' lines and its body's lines.
//! `in_block` marks a declaration inside a function body.
[arch(at="ARCHITECTURE.md#compared")]
def parser_lines(var p : CParser; n : int; in_block : bool = false) : array<FormLine> {
    var lines : array<FormLine>
    let decl = nd(p, n)
    if (decl.kind == CNode.STATIC_ASSERT) {
        let at = token_place(p, decl.tok)
        lines |> push(FormLine(file = at.file, text = "(static_assert{place_text(at)} {parser_expression(p, decl.a)} {parser_expression(p, decl.b)})"))
        return <- lines
    }
    let specs = decl.a
    tag_lines(p, specs, lines)
    let flags = specifier_flags(p, specs)
    if (decl.kind == CNode.FUNC_DEF) {
        var old = decl.c
        while (old >= 0) {
            var inscope kept : array<int>
            collect_bodies(p, old, -1, kept, kept)
            bodies_in_order(p, kept, lines)
            old = nd(p, old).next
        }
        declarator_lines(p, specs, decl.b, false, false, flags, lines)
        parameter_lines(p, c_name_function(p.ast, nd(p, decl.b).a), lines)
        statement_lines(p, decl.d, lines)
        return <- lines
    }
    if (decl.b < 0) {
        forward_line(p, specs, lines)
    }
    let is_typedef = has_keyword(p, specs, CTok.TYPEDEF)
    var id = decl.b
    while (id >= 0) {
        declarator_lines(p, specs, id, is_typedef, in_block, flags, lines)
        id = nd(p, id).next
    }
    return <- lines
}

// a block item's lines: a declaration's, or a statement's
def private item_lines(var p : CParser; n : int; var lines : array<FormLine>) {
    let k = nd(p, n).kind
    if (k == CNode.DECL || k == CNode.STATIC_ASSERT) {
        lines |> push_from(parser_lines(p, n, true))
    } else {
        statement_lines(p, n, lines)
    }
}

//! The lines of statement `s` and the statements under it, in order (`ARCHITECTURE.md#compared`):
//! one line per statement with its kind, place and expressions, a block closed by `(end)`.
[arch(at="ARCHITECTURE.md#compared")]
def statement_lines(var p : CParser; s : int; var lines : array<FormLine>) {
    if (s < 0) {
        // a label at a block's end: clang gives it a null statement
        lines |> push(FormLine(file = token_place(p, p.pos).file, text = "(null)"))
        return
    }
    let n = nd(p, s)
    let at = at_text(p, s)
    let k = n.kind
    if (k == CNode.COMPOUND) {
        lines |> push(line_at(p, n.tok, "(compound{at})"))
        var item = n.a
        while (item >= 0) {
            item_lines(p, item, lines)
            item = nd(p, item).next
        }
        lines |> push(line_at(p, n.tok, "(end)"))
    } elif (k == CNode.EXPR_STMT) {
        note_expression(p, n.a, lines)
        lines |> push(line_at(p, n.tok, "(expr{at} {parser_expression(p, n.a)})"))
    } elif (k == CNode.NULL_STMT) {
        lines |> push(line_at(p, n.tok, "(null)"))
    } elif (k == CNode.LABEL) {
        lines |> push(line_at(p, n.tok, "(label{at} {symbol(p, n.a)})"))
        if (n.b >= 0) {
            item_lines(p, n.b, lines)
        } else {
            statement_lines(p, -1, lines)
        }
    } elif (k == CNode.CASE) {
        note_expression(p, n.a, lines)
        lines |> push(line_at(p, n.tok, "(case{at} {parser_expression(p, n.a)} {parser_expression(p, n.b)})"))
        item_lines(p, n.c, lines)
    } elif (k == CNode.DEFAULT) {
        lines |> push(line_at(p, n.tok, "(default{at})"))
        item_lines(p, n.a, lines)
    } elif (k == CNode.IF) {
        note_expression(p, n.a, lines)
        lines |> push(line_at(p, n.tok, "(if{at} {parser_expression(p, n.a)} {n.c >= 0 ? "else" : "-"})"))
        statement_lines(p, n.b, lines)
        if (n.c >= 0) {
            statement_lines(p, n.c, lines)
        }
    } elif (k == CNode.SWITCH || k == CNode.WHILE) {
        note_expression(p, n.a, lines)
        lines |> push(line_at(p, n.tok, "({NODE_FORMS[int(k)]._0}{at} {parser_expression(p, n.a)})"))
        statement_lines(p, n.b, lines)
    } elif (k == CNode.DO) {
        note_expression(p, n.b, lines)
        lines |> push(line_at(p, n.tok, "(do{at} {parser_expression(p, n.b)})"))
        statement_lines(p, n.a, lines)
    } elif (k == CNode.FOR) {
        let is_decl = n.a >= 0 && nd(p, n.a).kind == CNode.DECL
        let init = is_decl ? "decl" : parser_expression(p, n.a)
        lines |> push(line_at(p, n.tok, "(for{at} {init} {parser_expression(p, n.b)} {parser_expression(p, n.c)})"))
        if (is_decl) {
            lines |> push_from(parser_lines(p, n.a, true))
        } else {
            note_expression(p, n.a, lines)
        }
        note_expression(p, n.b, lines)
        note_expression(p, n.c, lines)
        statement_lines(p, n.d, lines)
    } else {
        if (k == CNode.RETURN) {
            note_expression(p, n.a, lines)
        }
        lines |> push(line_at(p, n.tok, leaf_text(p, s)))
    }
}

// the line of a statement with no statement under it: `goto`, `continue`, `break`, `asm`, `return`
def private leaf_text(var p : CParser; s : int) : string {
    let n = nd(p, s)
    let at = at_text(p, s)
    let k = n.kind
    if (k == CNode.GOTO) {
        return "(goto{at} {symbol(p, n.a)})"
    } elif (k == CNode.CONTINUE || k == CNode.BREAK || k == CNode.ASM) {
        return "({NODE_FORMS[int(k)]._0}{at})"
    } elif (k == CNode.RETURN) {
        return "(return{at} {parser_expression(p, n.a)})"
    }
    return "(unknown {NODE_FORMS[int(k)]._0}{at})"
}

//! A unit read by the parser's unit entry: its external declarations, or the error that stopped
//! it and, for a refusal, the construct it names.
struct ParsedUnit {
    items : array<int>
    error : string
    construct : string
}

//! The construct a refusal names, "" for an error that is no refusal: `<file>:<line>:<col>:
//! <construct> is not parsed`, the construct past the first `: ` that follows a `:<digits>`.
def refused_construct(message : string) : string {
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

//! The unit `text`, named `name`, through the parser's unit entry, `c_unit`
//! (`ARCHITECTURE.md#unit`): its external declarations, or its first error.
[arch(at="ARCHITECTURE.md#unit")]
def parse_unit(var p : CParser; text, name : string) : ParsedUnit {
    var unit : ParsedUnit
    if (!c_parser_open_text(p, text, name)) {
        unit.error = p.err
        return <- unit
    }
    let u = c_unit(p)
    if (p.failed) {
        unit.error = p.err
        unit.construct = refused_construct(p.err)
        return <- unit
    }
    var at = nd(p, u).a
    while (at >= 0) {
        unit.items |> push(at)
        at = nd(p, at).next
    }
    return <- unit
}
