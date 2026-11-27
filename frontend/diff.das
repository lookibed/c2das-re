options gen2
options indenting = 4

module diff public

require math
require strings
require daslib/strings_boost
require ../converter/cir.das public

//! The byte diff of two dumpers' C-IR (`ARCHITECTURE_DIFF.md`): each text read back and written
//! again with the macro fields and the producer cleared, the two results compared byte for byte.
//! Pure: it reads two texts, never a file or a process.

// the macro fields of expression `x` and the expressions under it cleared
def private strip_expr(var x : CirExpr?) {
    return if (x == null)
    x.macro = ""
    delete x.fn_macro
    delete x.macro_args
    strip_expr(x.a)
    strip_expr(x.b)
    strip_expr(x.c)
    strip_expr(x.fn)
    strip_expr(x.base)
    strip_expr(x.i)
    strip_expr(x.init)
    strip_expr(x.list)
    for (arg in x.args) {
        strip_expr(arg)
    }
    for (item in x.init_items) {
        strip_expr(item.v)
    }
}

// the macro fields of statement `s` and everything under it cleared
def private strip_stmt(var s : CirStmt?) {
    return if (s == null)
    delete s.fn_macro
    strip_expr(s.init)
    strip_expr(s.e)
    strip_expr(s.cond)
    strip_expr(s.inc)
    for (kid in s.body) {
        strip_stmt(kid)
    }
    strip_stmt(s.init_s)
    strip_stmt(s.then_s)
    strip_stmt(s.else_s)
    strip_stmt(s.body_s)
}

//! C-IR text `text` read and written again with the fields the diff sets aside cleared: the unit's
//! `macros`, every node's `macro`, `fn_macro` and `macro_args` (docs/c-ir-spec.md section 6.2-6.3,
//! the one normalization the spec allows), and the producer, which names the dumper. "" with
//! `error` set for a text the C-IR reader refuses.
[arch(at="ARCHITECTURE_DIFF.md#cir-diff")]
def cir_normalized(text : string; var error : string&) : string {
    var tu <- read_cir(text, error)
    if (!empty(error)) {
        delete_tu(tu)
        return ""
    }
    tu.producer = ""
    delete tu.macros
    for (d in tu.decls) {
        strip_expr(d.init)
        strip_stmt(d.body)
    }
    let normalized = write_cir(tu)
    delete_tu(tu)
    return normalized
}

//! The first difference of C-IR texts `ours` and `theirs` after `cir_normalized`, "" when they are
//! byte-identical: `line N: ours <line> | theirs <line>`, or which text the reader refuses.
[arch(at="ARCHITECTURE_DIFF.md#cir-diff")]
def cir_diff(ours, theirs : string) : string {
    var error : string
    let a = cir_normalized(ours, error)
    return "ours: {error}" if (!empty(error))
    let b = cir_normalized(theirs, error)
    return "theirs: {error}" if (!empty(error))
    return "" if (a == b)
    let la <- split(a, "\n")
    let lb <- split(b, "\n")
    for (i in range(min(length(la), length(lb)))) {
        if (la[i] != lb[i]) {
            return "line {i + 1}: ours {strip(la[i])} | theirs {strip(lb[i])}"
        }
    }
    return "line {min(length(la), length(lb)) + 1}: one text ends"
}
