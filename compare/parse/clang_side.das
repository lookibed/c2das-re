options gen2
options indenting = 4

module clang_side public

require strings
require math
require daslib/json_boost
require daslib/strings_boost

//! The clang side of the parse oracle (`compare/parse/ARCHITECTURE.md`): clang's
//! `-ast-dump=json` tree of a preprocessed unit reduced to the oracle's line form, one line per
//! entity a file-scope declaration declares.

//! Where each physical line of a preprocessed unit stands, as its line markers place it: the byte
//! each line starts at, and the file and line it presents.
struct PresumedMap {
    starts : array<int>
    files : array<string>
    lines : array<int>
}

//! The place a byte offset of the unit stands at, as the line markers present it.
struct Place {
    file : string
    line : int
    col : int
}

//! A place as a key: file, line and column, tab-separated.
def place_key(at : Place) : string => "{at.file}\t{at.line}\t{at.col}"

//! A place as a line of the form writes it, `@line:col`; `@?` for none.
def place_text(at : Place) : string => at.line > 0 ? "@{at.line}:{at.col}" : "@?"

// the line number and the bytes between the quotes of a line marker `line`: `# <line> "<file>"
// <flags>` as `clang -E` writes it, or `#line <line> "<file>"`; a line of no such shape gives line 0
def private marker(line : string) : tuple<line : int; file : string> {
    var mark = (line = 0, file = "")
    peek_data(line) $(b) {
        let stop = length(b)
        var at = starts_with(line, "#line") ? 5 : 1
        while (at < stop && b[at] == uint8(' ')) {
            at++
        }
        let digits_from = at
        var number = 0
        while (at < stop && is_number(int(b[at]))) {
            number = number * 10 + int(b[at]) - '0'
            at++
        }
        return if (at == digits_from)
        mark.line = number
        while (at < stop && b[at] == uint8(' ')) {
            at++
        }
        return if (at >= stop || b[at] != uint8('"'))
        let name_from = at + 1
        at = name_from
        while (at < stop && b[at] != uint8('"')) {
            at += b[at] == uint8('\\') ? 2 : 1
        }
        mark.file = slice(b, name_from, min(at, stop))
    }
    return mark
}

//! The presumed place of every line of the preprocessed text `text`, whose own name is `name`:
//! a line marker names the line and, when it has one, the file of the line after it.
[arch(at="ARCHITECTURE.md#places")]
def presumed_map(text, name : string) : PresumedMap {
    var map : PresumedMap
    var file = name
    var line = 1
    var start = 0
    let lines <- split(text, "\n")
    map.starts |> reserve(length(lines))
    map.files |> reserve(length(lines))
    map.lines |> reserve(length(lines))
    for (text_line in lines) {
        map.starts |> push(start)
        map.files |> push(file)
        map.lines |> push(line)
        start += length(text_line) + 1
        let mark = starts_with(text_line, "#") ? marker(text_line) : (line = 0, file = "")
        if (mark.line > 0) {
            line = mark.line
            if (!empty(mark.file)) {
                file = mark.file
            }
        } else {
            line++
        }
    }
    return <- map
}

//! The place byte `offset` stands at; line 0 for a negative offset.
def place_of(map : PresumedMap; offset : int) : Place {
    return Place() if (offset < 0 || empty(map.starts))
    var lo = 0
    var hi = length(map.starts) - 1
    while (lo < hi) {
        let mid = (lo + hi + 1) / 2
        if (map.starts[mid] <= offset) {
            lo = mid
        } else {
            hi = mid - 1
        }
    }
    return Place(file = map.files[lo], line = map.lines[lo], col = offset - map.starts[lo] + 1)
}

//! One line of the form: the file it stands in, its text, and, on clang's side, the cause clang's
//! semantics give for a difference the line may show ("" for none).
struct FormLine {
    file : string
    text : string
    cause : string
}

//! The cause of a difference in the type of a library function clang knows as a builtin: clang
//! gives a redeclaration its own type, the builtin's merged with the written one.
let LIBRARY_BUILTIN = "a library builtin: clang's own type"

//! A name an entity of a file-scope declaration binds in the ordinary name space, and whether as a
//! typedef name.
struct BoundName {
    name : string
    is_typedef : bool
}

//! One file-scope declaration of clang's tree: the place of its first token, its lines (one per
//! entity it declares, none for a tag declaration), the names it binds, and the constructs in it the
//! oracle does not compare yet.
struct ClangTop {
    key : string
    lines : array<FormLine>
    names : array<BoundName>
    not_compared : array<string>
}

//! A unit's file-scope declarations as clang reads them, or the error that stopped the reading.
struct ClangUnit {
    tops : array<ClangTop>
    error : string
}

def private present(v : JsonValue?) : bool => v != null && !(v is _null)

def private kind_of(js : JsonValue?) : string => js?["kind"] ?? ""

// the offset of a location object: a macro's location by its expansion, none (-1) when clang gives none
def private offset_of(at : JsonValue?) : int {
    let spot = present(at?["expansionLoc"]) ? at?["expansionLoc"] : at
    return present(spot?["offset"]) ? int(spot?["offset"] ?? 0l) : -1
}

def private begin_of(map : PresumedMap; js : JsonValue?) : Place => place_of(map, offset_of(js?["range"]?["begin"]))

def private loc_of(map : PresumedMap; js : JsonValue?) : Place => place_of(map, offset_of(js?["loc"]))

// each child of `js`, its `inner` array
def private each_child(js : JsonValue?; blk : block<(c : JsonValue?) : void>) {
    let inner = js?["inner"]
    if (inner != null && inner is _array) {
        for (c in inner as _array) {
            invoke(blk, c)
        }
    }
}

//! A type as clang spells it, less what the parser keeps as attribute nodes: every
//! `__attribute__((...))` clang writes into a spelling, with the blank it leaves.
[arch(at="ARCHITECTURE.md#compared")]
def clang_type(spelling : string) : string {
    let open = "__attribute__(("
    return spelling if (find(spelling, open) < 0)
    let kept = build_string() $(var w) {
        peek_data(spelling) $(b) {
            var at = 0
            let size = length(b)
            while (at < size) {
                let found = find(spelling, open, at)
                if (found < 0) {
                    w |> write(slice(b, at, size))
                    break
                }
                w |> write(slice(b, at, found))
                var depth = 0
                at = found
                while (at < size) {
                    depth += b[at] == uint8('(') ? 1 : b[at] == uint8(')') ? -1 : 0
                    at++
                    break if (depth == 0 && b[at - 1] == uint8(')'))
                }
            }
        }
    }
    return strip(replace(kept, "  ", " "))
}

def private type_text(js : JsonValue?) : string => "\"{clang_type(js?["qualType"] ?? "")}\""

// the expression kinds clang inserts and the parser has no node for: their one child stands for them
let private TRANSPARENT <- ["ImplicitCastExpr", "ConstantExpr", "FullExpr", "ExprWithCleanups"]

// the literal kinds and their names in the form; an integer's value is compared, no other literal's
let private LITERALS <- {"FloatingLiteral" => "float", "CharacterLiteral" => "char", "StringLiteral" => "string"}

def private is_expression(k : string) : bool => !empty(k) && !ends_with(k, "Attr") && !ends_with(k, "Decl") && !ends_with(k, "Type") && !ends_with(k, "Comment")

// the reductions of the children of `js` that are expressions
def private expression_children(map : PresumedMap; js : JsonValue?) : array<string> {
    var parts : array<string>
    each_child(js) $(c) {
        if (is_expression(kind_of(c))) {
            parts |> push(clang_expression(map, c))
        }
    }
    return <- parts
}

// the form of a leaf node `js` of kind `k` at place `at`; "" for a kind that is no leaf
def private leaf_form(js : JsonValue?; k, at : string) : string {
    if (k == "DeclRefExpr") {
        return "(ident{at} {js?["referencedDecl"]?["name"] ?? ""})"
    } elif (k == "IntegerLiteral") {
        return "(int{at} {js?["value"] ?? "?"})"
    } elif (LITERALS |> key_exists(k)) {
        return "({LITERALS?[k] ?? ""}{at})"
    } elif (k == "PredefinedExpr") {
        return "(func_name{at})"
    } elif (k == "InitListExpr") {
        return "(init_list{at})"
    } elif (k == "OffsetOfExpr") {
        return "(offsetof{at})"
    }
    return ""
}

// the form of an operator node `js` of kind `k` at place `at` over its operands `parts`; "" for
// a kind that is no operator, or a count of operands it does not take
def private operator_form(js : JsonValue?; k, at : string; parts : array<string>) : string {
    let n = length(parts)
    if (k == "ParenExpr" && n == 1) {
        return "(paren{at} {parts[0]})"
    } elif ((k == "BinaryOperator" || k == "CompoundAssignOperator") && n == 2) {
        let op = js?["opcode"] ?? ""
        let what = (k == "CompoundAssignOperator" || op == "=") ? "assign" : "binary"
        return "({what}{at} {op} {parts[0]} {parts[1]})"
    } elif (k == "ConditionalOperator" && n == 3) {
        return "(cond{at} {parts[0]} {parts[1]} {parts[2]})"
    } elif (k == "BinaryConditionalOperator" && n == 4) {
        // the common operand, its opaque copies as the condition and the value if true, the value if false
        return "(cond{at} {parts[0]} - {parts[3]})"
    } elif (k == "UnaryOperator" && n == 1) {
        let op = js?["opcode"] ?? ""
        return "(extension{at} {parts[0]})" if (op == "__extension__")
        return "({(js?["isPostfix"] ?? false) ? "postfix" : "unary"}{at} {op} {parts[0]})"
    } elif (k == "CallExpr" && n >= 1) {
        return "(call{at} {parts[0]} [{join([for (p, i in parts, count()); p; where i > 0], " ")}])"
    } elif (k == "ChooseExpr" && n == 3) {
        // `__builtin_choose_expr` is a call of a builtin name to the parser
        return "(call{at} (ident{at} __builtin_choose_expr) [{join(parts, " ")}])"
    } elif (k == "ArraySubscriptExpr" && n == 2) {
        return "(index{at} {parts[0]} {parts[1]})"
    } elif (k == "MemberExpr" && n == 1) {
        let name = js?["name"] ?? ""
        // the access of an anonymous record member that clang inserts
        return parts[0] if (empty(name))
        return "(member{at} {(js?["isArrow"] ?? false) ? "->" : "."} {parts[0]} {name})"
    }
    return ""
}

// the form of a node `js` of kind `k` at place `at` that holds a type, over its operands `parts`;
// "" for any other kind
def private typed_form(js : JsonValue?; k, at : string; parts : array<string>) : string {
    let n = length(parts)
    if (k == "CStyleCastExpr" && n == 1) {
        return "(cast{at} {type_text(js?["type"])} {parts[0]})"
    } elif (k == "UnaryExprOrTypeTraitExpr") {
        let name = js?["name"] ?? ""
        let what = name == "sizeof" ? "sizeof" : "alignof"
        let keyword = name == "sizeof" ? "" : " {name}"
        return "({what}_type{at}{keyword} {type_text(js?["argType"])})" if (present(js?["argType"]))
        return "({what}_expr{at}{keyword} {parts[0]})" if (n == 1)
    } elif (k == "CompoundLiteralExpr" && n == 1) {
        return "(compound_literal{at} {type_text(js?["type"])} {parts[0]})"
    } elif (k == "VAArgExpr" && n == 1) {
        return "(va_arg{at} {parts[0]} {type_text(js?["type"])})"
    } elif (k == "TypeTraitExpr") {
        var types : array<string>
        each_child(js) $(c) {
            if (ends_with(kind_of(c), "Type")) {
                types |> push(type_text(c?["type"]))
            }
        }
        return "(types_compatible{at} {join(types, " ")})"
    }
    return ""
}

//! The expression `js` in the oracle's form (`ARCHITECTURE.md#compared`): clang's node kinds named
//! as the parser's dump names them, each with the place of its first token; a kind the form does not
//! name is `(unknown <kind>@...)`.
[arch(at="ARCHITECTURE.md#compared")]
def clang_expression(map : PresumedMap; js : JsonValue?) : string {
    return "-" if (!present(js))
    let k = kind_of(js)
    let parts <- expression_children(map, js)
    if (has_value(TRANSPARENT, k)) {
        return length(parts) == 1 ? parts[0] : "(unknown {k})"
    }
    let at = place_text(begin_of(map, js))
    let leaf = leaf_form(js, k, at)
    return leaf if (!empty(leaf))
    let op = operator_form(js, k, at, parts)
    return op if (!empty(op))
    let typed = typed_form(js, k, at, parts)
    return typed if (!empty(typed))
    return "(unknown {k}{at})"
}

// the flags of a declaration's line: its storage class, thread storage, `inline`
def private decl_flags(js : JsonValue?) : string {
    var flags = ""
    let storage = js?["storageClass"] ?? ""
    if (!empty(storage)) {
        flags += " {storage}"
    }
    if (present(js?["tls"])) {
        flags += " thread_local"
    }
    if (js?["inline"] ?? false) {
        flags += " inline"
    }
    return flags
}

// the names an enum's body binds, in the record bodies too
def private enumerators(js : JsonValue?; var names : array<BoundName>) {
    each_child(js) $(c) {
        let k = kind_of(c)
        if (k == "EnumConstantDecl") {
            names |> push(BoundName(name = c?["name"] ?? ""))
        } elif (k == "EnumDecl" || k == "RecordDecl") {
            enumerators(c, names)
        }
    }
}

// the lines, names and uncompared constructs of the file-scope declaration `js`
def private clang_top(map : PresumedMap; js : JsonValue?) : ClangTop {
    var top = ClangTop(key = place_key(begin_of(map, js)))
    let k = kind_of(js)
    let name = js?["name"] ?? ""
    let loc = loc_of(map, js)
    if (k == "TypedefDecl") {
        top.lines |> push(FormLine(file = loc.file, text = "(typedef {name}{place_text(loc)} {type_text(js?["type"])})"))
        top.names |> push(BoundName(name = name, is_typedef = true))
    } elif (k == "VarDecl") {
        let init <- expression_children(map, js)
        let value = empty(init) ? "" : " = {init[0]}"
        top.lines |> push(FormLine(file = loc.file, text = "(decl {name}{place_text(loc)} {type_text(js?["type"])}{decl_flags(js)}{value})"))
        top.names |> push(BoundName(name = name))
    } elif (k == "FunctionDecl") {
        var params : array<string>
        var builtin = false
        each_child(js) $(c) {
            let ck = kind_of(c)
            if (ck == "ParmVarDecl" && !(c?["isImplicit"] ?? false)) {
                let pname = c?["name"] ?? ""
                params |> push(empty(pname) ? "-" : "{pname}{place_text(loc_of(map, c))}")
            } elif (ck == "CompoundStmt") {
                top.not_compared |> push("a function body")
            } elif (ck == "BuiltinAttr") {
                builtin = true
            }
        }
        let list = empty(params) ? "" : " [{join(params, " ")}]"
        let line = "(decl {name}{place_text(loc)} {type_text(js?["type"])}{decl_flags(js)}{list})"
        top.lines |> push(FormLine(file = loc.file, text = line, cause = builtin ? LIBRARY_BUILTIN : ""))
        top.names |> push(BoundName(name = name))
    } elif (k == "StaticAssertDecl") {
        let at = begin_of(map, js)
        var parts <- expression_children(map, js)
        if (length(parts) == 1) {
            parts |> push("-")
        }
        top.lines |> push(FormLine(file = at.file, text = "(static_assert{place_text(at)} {join(parts, " ")})"))
    } elif (k == "RecordDecl" || k == "EnumDecl") {
        var enumerated = false
        each_child(js) $(c) {
            enumerated = enumerated || kind_of(c) == "EnumConstantDecl"
        }
        let body = k == "RecordDecl" ? (js?["completeDefinition"] ?? false) : enumerated
        if (body) {
            top.not_compared |> push(k == "RecordDecl" ? "a {js?["tagUsed"] ?? "struct"} body" : "an enum body")
        }
        enumerators(js, top.names)
    } else {
        let at = begin_of(map, js)
        top.lines |> push(FormLine(file = at.file, text = "(unknown {k}{place_text(at)})"))
    }
    return <- top
}

//! The file-scope declarations of clang's JSON dump `json` of the preprocessed text `text`, whose
//! own name is `name`; the implicit declarations clang makes before a unit are left out.
[arch(at="ARCHITECTURE.md#compared")]
def clang_unit(json, text, name : string) : ClangUnit {
    var unit : ClangUnit
    let map <- presumed_map(text, name)
    var error : string
    var js = read_json(json, error)
    if (js == null) {
        unit.error = "clang's JSON: {error}"
        return <- unit
    }
    each_child(js) $(c) {
        if (!(c?["isImplicit"] ?? false) && offset_of(c?["loc"]) >= 0) {
            unit.tops |> emplace(clang_top(map, c))
        }
    }
    unsafe {
        delete js
    }
    return <- unit
}
