options gen2
options indenting = 4

module c_ast public

require strings
require daslib/strings_boost
require c_tokens public

//! The kind of a C AST node. `NODE_FORMS` holds, per kind in this order, its dump name and the
//! roles of its fields.
enum CNode {
    IDENT
    INT
    FLOAT
    CHAR
    STRING
    FUNC_NAME
    PAREN
    BINARY
    ASSIGN
    COND
    UNARY
    POSTFIX
    CAST
    SIZEOF_EXPR
    SIZEOF_TYPE
    ALIGNOF_EXPR
    ALIGNOF_TYPE
    CALL
    INDEX
    MEMBER
    COMPOUND_LITERAL
    EXTENSION
    VA_ARG
    OFFSETOF
    TYPES_COMPATIBLE
    INIT_LIST
    INIT_ITEM
    DESIG_FIELD
    DESIG_INDEX
    TYPE_NAME
    SPEC_KEYWORD
    SPEC_TYPEDEF_NAME
    SPEC_RECORD
    SPEC_ENUM
    SPEC_TYPEOF_EXPR
    SPEC_TYPEOF_TYPE
    SPEC_ALIGNAS_EXPR
    SPEC_ALIGNAS_TYPE
    ATTRIBUTE
    D_NAME
    D_POINTER
    D_ARRAY
    D_FUNCTION
    D_PAREN
    PARAM
}

//! Per node kind, its dump name and the roles of `op`, `a`, `b`, `c`, `d`: `-` unused, `n` a node
//! (-1 none), `l` a list (its first node, the rest chained by `next`; -1 empty), `s` a symbol (-1
//! none), `t` a token, `k` a token kind, `i` an integer, `r` a token range (`a` the first token,
//! `b` the last, dumped as the bytes between them).
let NODE_FORMS <- fixed_array(
    ("ident", "-s---"),             // the name
    ("int", "-t---"),
    ("float", "-t---"),
    ("char", "-t---"),
    ("string", "-ti--"),            // the first literal, the count of adjacent literals
    ("func_name", "-t---"),
    ("paren", "-n---"),
    ("binary", "knn--"),            // the operator (`,` included), the operands
    ("assign", "knn--"),
    ("cond", "-nnn-"),              // the condition, the value if true (-1 for GNU `?:`), if false
    ("unary", "kn---"),
    ("postfix", "kn---"),
    ("cast", "-nn--"),              // the type name, the operand
    ("sizeof_expr", "-n---"),
    ("sizeof_type", "-n---"),
    ("alignof_expr", "kn---"),      // `_Alignof` or `__alignof__`, the operand
    ("alignof_type", "kn---"),
    ("call", "-nl--"),              // the callee, the arguments
    ("index", "-nn--"),
    ("member", "kns--"),            // `.` or `->`, the record, the member
    ("compound_literal", "-nn--"),  // the type name, the initializer list
    ("extension", "-n---"),
    ("va_arg", "-nn--"),            // the `va_list`, the type name
    ("offsetof", "-nl--"),          // the type name, the designators
    ("types_compatible", "-nn--"),
    ("init_list", "-l---"),
    ("init", "-ln--"),              // the designators, the initializer
    ("field", "-s---"),
    ("index_desig", "-nn--"),       // the index, the GNU range's last index
    ("type_name", "-ln--"),         // the specifiers, the abstract declarator
    ("spec", "k----"),
    ("typedef_name", "-s---"),
    ("record", "ks--l"),            // `struct` or `union`, the tag, the attributes after the keyword
    ("enum", "-s--l"),              // the tag, the attributes after the keyword
    ("typeof_expr", "-n---"),
    ("typeof_type", "-n---"),
    ("alignas_expr", "-n---"),
    ("alignas_type", "-n---"),
    ("attribute", "-r---"),         // `__attribute__((...))`, its tokens
    ("d_name", "-s---"),
    ("d_pointer", "-nl--"),         // the inner declarator, the qualifiers and attributes
    ("d_array", "innl-"),           // 1 `static`, 2 `[*]`; the inner declarator, the size, the qualifiers
    ("d_function", "inl--"),        // 1 variadic; the inner declarator, the parameters
    ("d_paren", "-nl--"),           // the inner declarator, the attributes
    ("param", "-ln--"))             // the specifiers, the declarator

//! One node: its kind, its fields by `NODE_FORMS`, the next node of the list it is in, and `tok`,
//! the token it starts at, which places it.
struct CNodeRec {
    kind : CNode
    op : int
    a : int
    b : int
    c : int
    d : int
    next : int
    tok : int
}

//! A tree: its nodes in one array, each referring to others by index.
struct CAst {
    nodes : array<CNodeRec>
}

//! A new node of `kind` that starts at token `tok`: every field -1, `op` 0.
def c_node(var ast : CAst; kind : CNode; tok : int) : int {
    ast.nodes |> push(CNodeRec(kind = kind, op = 0, a = -1, b = -1, c = -1, d = -1, next = -1, tok = tok))
    return length(ast.nodes) - 1
}

//! A list under construction: its first and last node, -1 when empty.
struct CList {
    head : int = -1
    tail : int = -1
}

//! Node `n` appended to `list`; -1 appends nothing.
def c_append(var ast : CAst; var list : CList; n : int) {
    return if (n < 0)
    if (list.head < 0) {
        list.head = n
    } else {
        ast.nodes[list.tail].next = n
    }
    list.tail = n
}

//! one step of a dump: a node to write, or `text` when it is not empty
struct private DumpStep {
    node : int
    text : string
}

//! the text of a scalar field of `node` whose role is `role` and value `v`
def private field_text(var unit : CUnit; node : CNodeRec; role, v : int) : string {
    if (role == 'k') {
        return c_kind_name(v)
    } elif (role == 's') {
        return v < 0 ? "-" : pp_symbol_text(unit.lx, v)
    } elif (role == 'i') {
        return "{v}"
    } elif (role == 't') {
        let count = node.kind == CNode.STRING ? node.b : 1
        return join([for (k in range(count)); c_spelling(unit, v + k)], " ")
    }
    let last = unit.toks[node.b]
    return c_text(unit, unit.toks[v].start, last.start + last.len - unit.toks[v].start)
}

//! The tree under node `n` as one line: `(<name> <fields>)`, a missing node `-`, a list `[...]`;
//! `places` writes `@<line>:<col>` after each name. The walk keeps its own stack, so a tree of any
//! depth costs no recursion.
[arch(at="ARCHITECTURE_PARSER.md#c-ast")]
def c_dump(ast : CAst; var unit : CUnit; n : int; places : bool = false) : string {
    return build_string() $(var w) {
        var steps : array<DumpStep>
        var members : array<int>
        steps |> push(DumpStep(node = n))
        while (!empty(steps)) {
            let step = steps[length(steps) - 1]
            steps |> pop()
            if (!empty(step.text)) {
                w |> write(step.text)
                continue
            } elif (step.node < 0) {
                w |> write("-")
                continue
            }
            let node = ast.nodes[step.node]
            let form = NODE_FORMS[int(node.kind)]
            w |> write("(")
            w |> write(form._0)
            if (places) {
                let tok = unit.toks[node.tok]
                w |> write("@{tok.line}:{tok.col}")
            }
            steps |> push(DumpStep(node = -1, text = ")"))
            var roles : int[5]
            for (role, i in form._1, count()) {
                roles[i] = role
            }
            let fields = fixed_array(node.op, node.a, node.b, node.c, node.d)
            for (back in range(5)) {
                let i = 4 - back
                let role = roles[i]
                let v = fields[i]
                if (role == '-' || (role == 'i' && node.kind == CNode.STRING)) {
                    continue
                } elif (role == 'n') {
                    steps |> push(DumpStep(node = v))
                } elif (role == 'l') {
                    members |> clear()
                    var k = v
                    while (k >= 0) {
                        members |> push(k)
                        k = ast.nodes[k].next
                    }
                    steps |> push(DumpStep(node = -1, text = "]"))
                    for (m in range(length(members))) {
                        steps |> push(DumpStep(node = members[length(members) - 1 - m]))
                        if (m + 1 < length(members)) {
                            steps |> push(DumpStep(node = -1, text = " "))
                        }
                    }
                    steps |> push(DumpStep(node = -1, text = "["))
                } else {
                    steps |> push(DumpStep(node = -1, text = field_text(unit, node, role, v)))
                }
                steps |> push(DumpStep(node = -1, text = " "))
            }
        }
    }
}
