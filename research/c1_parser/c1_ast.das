options gen2
options indenting = 4

module c1_ast shared public

// The C.1 parser probe's shared data: the token kinds, the token array, the identifier interner,
// the AST both candidate parsers build, the typedef scope table both consult, and the dump both
// trees are compared through. Tokens and nodes live in arrays and refer to each other by index;
// identifiers are interned as integers over the source bytes, so lexing and parsing allocate no
// string per token.

require strings
require daslib/enum_trait

//! Token kinds. A single-character punctuator keeps its byte; every other kind is past 255.
enum TK {
    EOF = 0
    BANG = 33
    PERCENT = 37
    AMP = 38
    LPAREN = 40
    RPAREN = 41
    STAR = 42
    PLUS = 43
    COMMA = 44
    MINUS = 45
    DOT = 46
    SLASH = 47
    COLON = 58
    SEMI = 59
    LT = 60
    ASSIGN = 61
    GT = 62
    QUESTION = 63
    LBRACKET = 91
    RBRACKET = 93
    CARET = 94
    LBRACE = 123
    PIPE = 124
    RBRACE = 125
    TILDE = 126
    IDENTIFIER = 256
    TYPEDEF_NAME = 257
    I_CONSTANT = 258
    F_CONSTANT = 259
    C_CONSTANT = 260
    STRING_LITERAL = 261
    ARROW = 262
    INC = 263
    DEC = 264
    SHL = 265
    SHR = 266
    LE = 267
    GE = 268
    EQ = 269
    NE = 270
    ANDAND = 271
    OROR = 272
    MUL_ASSIGN = 273
    DIV_ASSIGN = 274
    MOD_ASSIGN = 275
    ADD_ASSIGN = 276
    SUB_ASSIGN = 277
    SHL_ASSIGN = 278
    SHR_ASSIGN = 279
    AND_ASSIGN = 280
    XOR_ASSIGN = 281
    OR_ASSIGN = 282
    ELLIPSIS = 283
    AUTO = 300
    BREAK = 301
    CASE = 302
    CHAR = 303
    CONST = 304
    CONTINUE = 305
    DEFAULT = 306
    DO = 307
    DOUBLE = 308
    ELSE = 309
    ENUM = 310
    EXTERN = 311
    FLOAT = 312
    FOR = 313
    GOTO = 314
    IF = 315
    INLINE = 316
    INT = 317
    LONG = 318
    REGISTER = 319
    RESTRICT = 320
    RETURN = 321
    SHORT = 322
    SIGNED = 323
    SIZEOF = 324
    STATIC = 325
    STRUCT = 326
    SWITCH = 327
    TYPEDEF = 328
    UNION = 329
    UNSIGNED = 330
    VOID = 331
    VOLATILE = 332
    WHILE = 333
    BOOL = 334
    COMPLEX = 335
    ALIGNAS = 336
    ALIGNOF = 337
    NORETURN = 338
    STATIC_ASSERT = 339
    THREAD_LOCAL = 340
    GENERIC = 341
    ATOMIC = 342
    IMAGINARY = 343
    ATTRIBUTE = 344
    ASM = 345
    EXTENSION = 346
    TYPEOF = 347
    ALIGNOF_GNU = 348
    VA_ARG = 349
    OFFSETOF = 350
    FUNC_NAME = 351
    LABEL_KW = 352
    INT128 = 353
    AUTO_TYPE = 354
}

//! The spellings the lexer turns into keyword kinds, GNU alternates included; each is interned
//! first, so a symbol below `length(KEYWORDS)` is a keyword and `KEYWORD_KINDS` holds its kind.
let KEYWORDS <- fixed_array("auto", "break", "case", "char", "const", "continue", "default", "do", "double",
    "else", "enum", "extern", "float", "for", "goto", "if", "inline", "int", "long", "register", "restrict",
    "return", "short", "signed", "sizeof", "static", "struct", "switch", "typedef", "union", "unsigned",
    "void", "volatile", "while", "_Bool", "_Complex", "_Alignas", "_Alignof", "_Noreturn", "_Static_assert",
    "_Thread_local", "_Generic", "_Atomic", "_Imaginary", "__attribute__", "__attribute", "__asm__", "__asm",
    "asm", "__extension__", "__typeof__", "__typeof", "typeof", "__alignof__", "__alignof",
    "__builtin_va_arg", "__builtin_offsetof", "__func__", "__FUNCTION__", "__PRETTY_FUNCTION__",
    "__inline", "__inline__", "__restrict", "__restrict__", "__const", "__const__", "__volatile",
    "__volatile__", "__signed", "__signed__", "__thread", "__label__", "__int128", "__auto_type",
    "__complex__", "__complex")

let KEYWORD_KINDS <- fixed_array(TK.AUTO, TK.BREAK, TK.CASE, TK.CHAR, TK.CONST, TK.CONTINUE, TK.DEFAULT, TK.DO,
    TK.DOUBLE, TK.ELSE, TK.ENUM, TK.EXTERN, TK.FLOAT, TK.FOR, TK.GOTO, TK.IF, TK.INLINE, TK.INT, TK.LONG,
    TK.REGISTER, TK.RESTRICT, TK.RETURN, TK.SHORT, TK.SIGNED, TK.SIZEOF, TK.STATIC, TK.STRUCT, TK.SWITCH,
    TK.TYPEDEF, TK.UNION, TK.UNSIGNED, TK.VOID, TK.VOLATILE, TK.WHILE, TK.BOOL, TK.COMPLEX, TK.ALIGNAS,
    TK.ALIGNOF, TK.NORETURN, TK.STATIC_ASSERT, TK.THREAD_LOCAL, TK.GENERIC, TK.ATOMIC, TK.IMAGINARY,
    TK.ATTRIBUTE, TK.ATTRIBUTE, TK.ASM, TK.ASM, TK.ASM, TK.EXTENSION, TK.TYPEOF, TK.TYPEOF, TK.TYPEOF,
    TK.ALIGNOF_GNU, TK.ALIGNOF_GNU, TK.VA_ARG, TK.OFFSETOF, TK.FUNC_NAME, TK.FUNC_NAME, TK.FUNC_NAME,
    TK.INLINE, TK.INLINE, TK.RESTRICT, TK.RESTRICT, TK.CONST, TK.CONST, TK.VOLATILE, TK.VOLATILE,
    TK.SIGNED, TK.SIGNED, TK.THREAD_LOCAL, TK.LABEL_KW, TK.INT128, TK.AUTO_TYPE, TK.COMPLEX, TK.COMPLEX)

//! A token: its kind, its bytes `[start, start + len)` of the source, the location of its first
//! byte (`file` an index of `Source.files`), and its interned symbol (-1 for a non-word).
struct Tok {
    kind : int
    start : int
    len : int
    line : int
    col : int
    file : int
    sym : int
}

//! Names by their bytes: open addressing over FNV-1a hashes, the bytes of every name in one pool.
struct Interner {
    slots : array<int>      //!< symbol + 1 per slot, 0 when empty
    starts : array<int>     //!< per symbol, its first byte in `pool`
    lens : array<int>
    hashes : array<uint>
    pool : array<uint8>
}

def private fnv(bytes : array<uint8>; start, len : int) : uint {
    var h = 2166136261u
    for (i in range(start, start + len)) {
        h = (h ^ uint(bytes[i])) * 16777619u
    }
    return h
}

def private grow(var it : Interner) {
    let cap = length(it.slots) == 0 ? 1024 : length(it.slots) * 2
    it.slots |> resize(cap)
    for (i in range(cap)) {
        it.slots[i] = 0
    }
    let mask = uint(cap - 1)
    for (sym in range(length(it.hashes))) {
        var at = it.hashes[sym] & mask
        while (it.slots[at] != 0) {
            at = (at + 1u) & mask
        }
        it.slots[at] = sym + 1
    }
}

//! The symbol of `bytes[start, start + len)`, interned on first sight.
def intern(var it : Interner; bytes : array<uint8>; start, len : int) : int {
    if (length(it.hashes) * 2 >= length(it.slots)) {
        grow(it)
    }
    let h = fnv(bytes, start, len)
    let mask = uint(length(it.slots) - 1)
    var at = h & mask
    while (true) {
        let s = it.slots[at]
        if (s == 0) {
            break
        }
        let sym = s - 1
        if (it.hashes[sym] == h && it.lens[sym] == len) {
            var same = true
            let base = it.starts[sym]
            for (i in range(len)) {
                if (it.pool[base + i] != bytes[start + i]) {
                    same = false
                    break
                }
            }
            if (same) {
                return sym
            }
        }
        at = (at + 1u) & mask
    }
    let sym = length(it.hashes)
    it.slots[at] = sym + 1
    it.hashes |> push(h)
    it.starts |> push(length(it.pool))
    it.lens |> push(len)
    for (i in range(len)) {
        it.pool |> push(bytes[start + i])
    }
    return sym
}

//! The spelling of symbol `sym`.
def name_of(it : Interner; sym : int) : string {
    if (sym < 0) {
        return "<none>"
    }
    let base = it.starts[sym]
    return build_string() $(var w) {
        for (i in range(it.lens[sym])) {
            w |> write_char(int(it.pool[base + i]))
        }
    }
}

//! An interner holding the keywords as symbols `0 .. length(KEYWORDS) - 1`.
def keyword_interner : Interner {
    var it : Interner
    for (kw in KEYWORDS) {
        let bytes <- to_bytes(kw)
        intern(it, bytes, 0, length(bytes))
    }
    return <- it
}

//! A lexed translation unit: the bytes, the tokens, the file names the line markers named, the
//! symbols. A lexer error leaves `err` set and the tokens up to it.
struct Source {
    bytes : array<uint8>
    toks : array<Tok>
    files : array<string>
    names : Interner
    err : string
}

//! The spelling of token `t` of `src`.
def tok_text(src : Source; t : int) : string {
    let tok = src.toks[t]
    return build_string() $(var w) {
        for (i in range(tok.start, tok.start + tok.len)) {
            w |> write_char(int(src.bytes[i]))
        }
    }
}

//! `file:line:col` of token `t`.
def tok_where(src : Source; t : int) : string {
    let tok = src.toks[t]
    return "{src.files[tok.file]}:{tok.line}:{tok.col}"
}

//! Node kinds. Each kind's fields `a`, `b`, `c`, `d` and `op` have the roles `ROLES` names.
enum NK {
    TU
    FUNC_DEF
    DECL
    STATIC_ASSERT
    INIT_DECL
    SPEC_KW
    SPEC_TYPEDEF_NAME
    SPEC_RECORD
    SPEC_ENUM
    ENUMERATOR
    SPEC_TYPEOF_EXPR
    SPEC_TYPEOF_TYPE
    SPEC_ALIGNAS_EXPR
    SPEC_ALIGNAS_TYPE
    ATTRIBUTE
    ATTR
    ASM_LABEL
    MEMBER_DECL
    MEMBER_DECLARATOR
    D_NAME
    D_PTR
    D_ARRAY
    D_FUNC
    D_PAREN
    PARAM
    IDENT_PARAM
    TYPENAME
    INIT_LIST
    INIT_ITEM
    DESIG_FIELD
    DESIG_INDEX
    S_COMPOUND
    S_EXPR
    S_NULL
    S_IF
    S_SWITCH
    S_WHILE
    S_DO
    S_FOR
    S_GOTO
    S_GOTO_PTR
    S_CONTINUE
    S_BREAK
    S_RETURN
    S_LABEL
    S_CASE
    S_DEFAULT
    S_ASM
    S_ATTRIBUTED
    ASM_OPERAND
    E_IDENT
    E_INT
    E_FLOAT
    E_CHAR
    E_STRING
    E_FUNC_NAME
    E_PAREN
    E_BINARY
    E_ASSIGN
    E_COND
    E_UNARY
    E_POSTFIX
    E_CAST
    E_SIZEOF_EXPR
    E_SIZEOF_TYPE
    E_ALIGNOF_EXPR
    E_ALIGNOF_TYPE
    E_CALL
    E_INDEX
    E_MEMBER
    E_COMPOUND_LIT
    E_STMT_EXPR
    E_EXTENSION
    E_VA_ARG
    E_OFFSETOF
    E_LABEL_ADDR
}

//! Per kind, the role of `op`, `a`, `b`, `c`, `d`: `-` unused, `n` a node (-1 none), `l` a list
//! (its first node, chained by `next`; -1 empty), `s` a symbol, `t` a token, `k` a token kind,
//! `i` a plain integer.
let ROLES <- fixed_array(
    "-l---",   // TU: decls
    "-lnln",   // FUNC_DEF: specs, init-declarator, K&R declarations, body
    "-ll--",   // DECL: specs, init-declarators
    "-nn--",   // STATIC_ASSERT: condition, message
    "-nnnl",   // INIT_DECL: declarator, initializer, asm label, attributes
    "k----",   // SPEC_KW
    "-s---",   // SPEC_TYPEDEF_NAME
    "ksli-",   // SPEC_RECORD: struct|union, tag, members, has body
    "-sli-",   // SPEC_ENUM: tag, enumerators, has body
    "-snl-",   // ENUMERATOR: name, value, attributes
    "-n---",   // SPEC_TYPEOF_EXPR
    "-n---",   // SPEC_TYPEOF_TYPE
    "-n---",   // SPEC_ALIGNAS_EXPR
    "-n---",   // SPEC_ALIGNAS_TYPE
    "-l---",   // ATTRIBUTE: attrs of one __attribute__((...))
    "-sli-",   // ATTR: name, args, has parens
    "-n---",   // ASM_LABEL: string
    "-ll--",   // MEMBER_DECL: specs, member declarators
    "-nnl-",   // MEMBER_DECLARATOR: declarator, width, attributes
    "-s---",   // D_NAME
    "-nl--",   // D_PTR: inner, qualifiers
    "inl--",   // D_ARRAY: flags (1 static, 2 star), inner, size, qualifiers
    "inl--",   // D_FUNC: flags (1 variadic, 2 identifier list), inner, params
    "-nl--",   // D_PAREN: inner, attributes
    "-ln--",   // PARAM: specs, declarator
    "-s---",   // IDENT_PARAM
    "-ln--",   // TYPENAME: specs, abstract declarator
    "-l---",   // INIT_LIST
    "-ln--",   // INIT_ITEM: designators, initializer
    "-s---",   // DESIG_FIELD
    "-nn--",   // DESIG_INDEX: index, GNU range end
    "-l---",   // S_COMPOUND
    "-n---",   // S_EXPR
    "-----",   // S_NULL
    "-nnn-",   // S_IF
    "-nn--",   // S_SWITCH
    "-nn--",   // S_WHILE
    "-nn--",   // S_DO: body, condition
    "-nnnn",   // S_FOR: init (declaration or expression), condition, step, body
    "-s---",   // S_GOTO
    "-n---",   // S_GOTO_PTR
    "-----",   // S_CONTINUE
    "-----",   // S_BREAK
    "-n---",   // S_RETURN
    "-snl-",   // S_LABEL: label, statement, attributes
    "-nnn-",   // S_CASE: low, GNU high, statement
    "-n---",   // S_DEFAULT
    "ilnnl",   // S_ASM: qualifier flags, template, outputs, inputs, clobbers
    "-ln--",   // S_ATTRIBUTED: attributes, statement
    "-nns-",   // ASM_OPERAND: constraint, expression, symbolic name
    "-s---",   // E_IDENT
    "-t---",   // E_INT
    "-t---",   // E_FLOAT
    "-t---",   // E_CHAR
    "-ti--",   // E_STRING: first token, token count
    "-s---",   // E_FUNC_NAME
    "-n---",   // E_PAREN
    "knn--",   // E_BINARY
    "knn--",   // E_ASSIGN
    "-nnn-",   // E_COND: condition, then (-1 for GNU ?:), else
    "kn---",   // E_UNARY
    "kn---",   // E_POSTFIX
    "-nn--",   // E_CAST: type, operand
    "-n---",   // E_SIZEOF_EXPR
    "-n---",   // E_SIZEOF_TYPE
    "kn---",   // E_ALIGNOF_EXPR
    "kn---",   // E_ALIGNOF_TYPE
    "-nl--",   // E_CALL: callee, args
    "-nn--",   // E_INDEX
    "kns--",   // E_MEMBER: . or ->, base, member
    "-nn--",   // E_COMPOUND_LIT: type, initializer list
    "-n---",   // E_STMT_EXPR: compound statement
    "-n---",   // E_EXTENSION
    "-nn--",   // E_VA_ARG: va_list expression, type
    "-nl--",   // E_OFFSETOF: type, designators
    "-s---"    // E_LABEL_ADDR
)

//! An AST node; `next` chains the members of a list.
struct Node {
    kind : int
    op : int
    a : int
    b : int
    c : int
    d : int
    next : int
    file : int
    line : int
    col : int
}

//! The tree: every node of a translation unit, the root last built.
struct Ast {
    nodes : array<Node>
    root : int
}

//! A new node of `kind` located at token `t` of `toks`, its fields -1, its `op` 0.
def add_node(var ast : Ast; toks : array<Tok>; kind : NK; t : int) : int {
    let tok = toks[t]
    ast.nodes |> push(Node(kind = int(kind), op = 0, a = -1, b = -1, c = -1, d = -1, next = -1, file = tok.file, line = tok.line, col = tok.col))
    return length(ast.nodes) - 1
}

//! A node of `kind` at the location of node `at`.
def add_node_at(var ast : Ast; kind : NK; at : int) : int {
    var n = ast.nodes[at]
    n.kind = int(kind)
    n.op = 0
    n.a = -1
    n.b = -1
    n.c = -1
    n.d = -1
    n.next = -1
    ast.nodes |> push(n)
    return length(ast.nodes) - 1
}

//! A list under construction: its first and last node, -1 when empty.
struct NodeList {
    head : int
    tail : int
}

def empty_list : NodeList => NodeList(head = -1, tail = -1)

//! Append node `n` (and the chain after it) to `list`.
def append(var ast : Ast; var list : NodeList; n : int) {
    if (n < 0) {
        return
    }
    if (list.head < 0) {
        list.head = n
    } else {
        ast.nodes[list.tail].next = n
    }
    var last = n
    while (ast.nodes[last].next >= 0) {
        last = ast.nodes[last].next
    }
    list.tail = last
}

//! The symbol a declarator declares, -1 for an abstract one.
def declarator_name(ast : Ast; d : int) : int {
    var at = d
    while (at >= 0) {
        let n = ast.nodes[at]
        if (n.kind == int(NK.D_NAME)) {
            return n.a
        }
        at = n.a
    }
    return -1
}

//! The innermost function declarator applied directly to the declared name (through parentheses):
//! the one whose parameters a function definition's body sees; -1 when there is none.
def name_function(ast : Ast; d : int) : int {
    var at = d
    while (at >= 0) {
        let n = ast.nodes[at]
        if (n.kind == int(NK.D_FUNC)) {
            var inner = n.a
            while (inner >= 0 && ast.nodes[inner].kind == int(NK.D_PAREN)) {
                inner = ast.nodes[inner].a
            }
            if (inner >= 0 && ast.nodes[inner].kind == int(NK.D_NAME)) {
                return at
            }
        }
        if (n.kind == int(NK.D_NAME)) {
            return -1
        }
        at = n.a
    }
    return -1
}

//! Typedef names by scope: the binding of every symbol now (0 none, `ORDINARY`, `TYPEDEF`) and an
//! undo log a scope's end rolls back to its mark, so a lookup is one index.
struct Scopes {
    binding : array<int>
    undo : array<int2>
    marks : array<int>
}

let ORDINARY = 1
let TYPEDEF = 2

def scope_open(var sc : Scopes) {
    sc.marks |> push(length(sc.undo))
}

def scope_close(var sc : Scopes) {
    let mark = sc.marks[length(sc.marks) - 1]
    sc.marks |> pop()
    var at = length(sc.undo) - 1
    while (at >= mark) {
        let u = sc.undo[at]
        sc.binding[u.x] = u.y
        at--
    }
    sc.undo |> resize(mark)
}

//! Bind symbol `sym` as `kind` in the innermost scope.
def scope_declare(var sc : Scopes; sym, kind : int) {
    if (sym < 0) {
        return
    }
    if (sym >= length(sc.binding)) {
        let old = length(sc.binding)
        sc.binding |> resize(sym + 1024)
        for (i in range(old, length(sc.binding))) {
            sc.binding[i] = 0
        }
    }
    sc.undo |> push(int2(sym, sc.binding[sym]))
    sc.binding[sym] = kind
}

def is_typedef_name(sc : Scopes; sym : int) : bool => sym < length(sc.binding) && sc.binding[sym] == TYPEDEF

//! The scopes of a unit's start: `__builtin_va_list` is a typedef name, as clang declares it.
def file_scopes(var names : Interner) : Scopes {
    var sc : Scopes
    let bytes <- to_bytes("__builtin_va_list")
    scope_declare(sc, intern(names, bytes, 0, length(bytes)), TYPEDEF)
    return <- sc
}

let private TK_NAMES <- { for (k in each(type<TK>)); int(k) => string(k) }

let private NK_NAMES <- [for (k in each(type<NK>)); string(k)]

//! The spelling of token kind `k`.
def kind_name(k : int) : string {
    if (k > 0 && k < 256) {
        return to_char(k)
    }
    let names = fixed_array("->", "++", "--", "<<", ">>", "<=", ">=", "==", "!=", "&&", "||", "*=", "/=", "%=", "+=", "-=", "<<=", ">>=", "&=", "^=", "|=", "...")
    if (k >= int(TK.ARROW) && k <= int(TK.ELLIPSIS)) {
        return names[k - int(TK.ARROW)]
    }
    for (kw, kind in KEYWORDS, KEYWORD_KINDS) {
        if (int(kind) == k) {
            return kw
        }
    }
    return TK_NAMES?[k] ?? "kind {k}"
}

//! The tree as text, one node per line, two spaces of indent per level; `locs` adds each node's
//! `@file:line:col`. Two parsers built the same tree when their dumps are equal.
def dump_ast(ast : Ast; src : Source; locs : bool) : string {
    return build_string() $(var w) {
        if (ast.root >= 0) {
            dump_node(w, ast, src, locs, ast.root, 0, "")
        }
    }
}

def private dump_node(var w : StringBuilderWriter; ast : Ast; src : Source; locs : bool; at, depth : int; tag : string) {
    let n = ast.nodes[at]
    let roles = ROLES[n.kind]
    for (_ in range(depth)) {
        w |> write("  ")
    }
    if (!empty(tag)) {
        w |> write(tag)
        w |> write(": ")
    }
    w |> write(NK_NAMES[n.kind])
    let fields = fixed_array(n.op, n.a, n.b, n.c, n.d)
    for (i in range(5)) {
        let r = character_at(roles, i)
        let v = fields[i]
        if (r == 'k') {
            w |> write(" '{kind_name(v)}'")
        } elif (r == 's') {
            w |> write(" {name_of(src.names, v)}")
        } elif (r == 'i') {
            w |> write(" {v}")
        } elif (r == 't') {
            if (n.kind == int(NK.E_STRING)) {
                for (k in range(n.b)) {
                    w |> write(" {tok_text(src, v + k)}")
                }
            } else {
                w |> write(" {tok_text(src, v)}")
            }
        }
    }
    if (locs) {
        w |> write(" @{src.files[n.file]}:{n.line}:{n.col}")
    }
    w |> write("\n")
    let slots = fixed_array("op", "a", "b", "c", "d")
    for (i in range(1, 5)) {
        let r = character_at(roles, i)
        let v = fields[i]
        if (r == 'n') {
            if (v >= 0) {
                dump_node(w, ast, src, locs, v, depth + 1, slots[i])
            }
        } elif (r == 'l') {
            var k = v
            while (k >= 0) {
                dump_node(w, ast, src, locs, k, depth + 1, slots[i])
                k = ast.nodes[k].next
            }
        }
    }
}
