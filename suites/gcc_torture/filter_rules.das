options gen2

module filter_rules public

require strings
require daslib/strings_boost
require daslib/regex
require daslib/regex_boost

//! The rules of the torture import's filter (`filter.das`): every `execute/*.c` whose text carries a construct the converter or its
//! frontend refuses gets its `skip.txt` line - id, feature, reason, the ledger row that unblocks
//! it, `never` for a construct no emulation reaches - unless `expected_pass.txt` lists the id,
//! since a test that passes is judged, never skipped. The rest ratchet; a test that fails for a
//! reason no rule names is an ordinary failure the run counts.

//! What a rule matches: its `pattern`, a regex over the test's text; an attribute outside
//! `DROPPED_ATTRIBUTES` and `LAYOUT_ATTRIBUTES`; attributes outside `DROPPED_ATTRIBUTES`, every one
//! in `LAYOUT_ATTRIBUTES`; or a `__builtin_*` name outside `MAPPED_BUILTINS`.
enum RuleKind {
    regex
    attributes
    layout
    builtins
}

//! A rule: what it matches (`kind`, and `pattern` for a regex), and the skip line it writes.
struct Rule {
    kind : RuleKind = RuleKind.regex
    pattern : string
    feature : string
    reason : string
    phase : string
}

let REFUSED_INPUT = "the pinned clang refuses the input and the pipeline has no other frontend"

// an asm keyword, then its qualifiers in any order, each in its spellings with and without
// underscores, the longer first
let ASM_HEAD = "\\b(__asm__|__asm|asm)(\\s|__volatile__|__volatile|volatile|__inline__|__inline|inline)*"

//! The rules in the order they fire, the first match naming the line: the constructs no emulation
//! reaches (`never`), then the rows that will carry one, in the order a test meets them; so a test
//! with a GNU keyword and an attribute is a GNU keyword's, and one clang refuses is never's
//! whatever else it holds.
let RULES <- [
    Rule(pattern = "{ASM_HEAD}(\\(\\s*(\"[^\"]|\"\"\\s*:\\s*[^:\\s)]|\"\"\\s*:\\s*:\\s*[^:\\s)])|goto\\b)", feature = "inline asm", reason = "machine code or register binding; no emulation exists in the das runtime", phase = "never"),
    Rule(pattern = "-finstrument-functions", feature = "-finstrument-functions", reason = "checks gcc's -finstrument-functions output", phase = "never"),
    Rule(pattern = "__builtin_va_arg_pack|__builtin_apply\\b", feature = "GNU argument forwarding builtins", reason = REFUSED_INPUT, phase = "never"),
    Rule(pattern = "__builtin_(shuffle|isinff|isinfl|mul_overflow_p)\\b", feature = "GCC builtins clang does not know", reason = REFUSED_INPUT, phase = "never"),
    Rule(pattern = "\\n[ \\t]+struct[^;\{()=]*\\\{([^\{\}]|\\\{[^\{\}]*\\\})*\\[\\s*[a-z_][A-Za-z0-9_]*\\s*\\]", feature = "variable-length array in a struct", reason = REFUSED_INPUT, phase = "never"),
    Rule(pattern = "__builtin_(return_address|frame_address)\\b", feature = "return and frame addresses", reason = "the das runtime exposes no frame or return addresses; a null mapping would lie to the test", phase = "never"),
    Rule(pattern = "_Float[0-9]|__float128|__fp16|_Decimal", feature = "non-standard floating types", reason = "_Float16, __float128 and _Decimal have no das type and no exact emulation; _Decimal is also an input the pinned clang refuses", phase = "never"),
    Rule(pattern = "__sync_|__atomic_|__thread|_Thread_local", feature = "atomics and thread-local storage", reason = "the das runtime runs one thread; an atomic or thread-local object has no other thread to differ from", phase = "never"),
    Rule(pattern = "dg-(additional-)?options \"[^\"]*(-std=gnu89|-fpermissive)", feature = "permissive input", reason = "the test asks gcc for -std=gnu89 or -fpermissive, which the converter's clang invocation does not pass", phase = "P7.8"),
    Rule(pattern = "__builtin_exit\\b", feature = "permissive input", reason = "clang declares no `__builtin_exit`, and its default refuses the implicit declaration; under the permissive flags the emitter maps it to `exit`", phase = "P7.8"),
    Rule(pattern = "_Complex|\\b__complex(__)?\\b|\\b__real(__)?\\b|\\b__imag(__)?\\b", feature = "_Complex", reason = "complex arithmetic is not lowered yet", phase = "P7.5"),
    Rule(pattern = "(^|[\\s(,=\\[\{:?&*+!<>|;])(L|u8|u|U)\"", feature = "wide string literals", reason = "a wide string literal is not lowered yet; the emitter fails closed on one", phase = "P7.5"),
    Rule(pattern = "\\n[ \\t]+extern\\s+[A-Za-z_][A-Za-z0-9_ \\t*]*\\(", feature = "block-scope function declaration", reason = "a function declared inside a function body is not lowered yet", phase = "P7.5"),
    Rule(pattern = "__u?int128", feature = "__int128", reason = "a 128-bit integer through c_runtime is not built yet", phase = "P7.6"),
    Rule(pattern = "vector_size", feature = "GNU vector extension", reason = "GNU vector types are not lowered yet", phase = "P7.6"),
    Rule(pattern = "__label__|[=,(\{:?]\\s*&&\\s*[A-Za-z_]|\\breturn\\s+&&|goto\\s*\\*", feature = "address of a label and local labels", reason = "labels as values through the switch re-dispatch and local labels are not lowered yet", phase = "P7.6"),
    Rule(pattern = "case [^:\n]*\\.\\.\\.", feature = "GNU case range", reason = "`case a ... b` is not lowered yet", phase = "P7.6"),
    Rule(pattern = "__typeof|\\btypeof *\\(|__extension__|__alignof", feature = "GNU keywords", reason = "typeof, __extension__ and __alignof__ are not lowered yet", phase = "P7.6"),
    Rule(kind = RuleKind.attributes, feature = "__attribute__", reason = "an attribute outside the dumper's dropped list (linkage, run-time behaviour) is not lowered yet", phase = "P7.6"),
    Rule(kind = RuleKind.layout, feature = "packed or aligned layout", reason = "a packed record is marshal-only, and an alignment das cannot spell (a variable's, a record's past its members) is not lowered yet", phase = "P7.6"),
    Rule(pattern = "__builtin_(add|sub|mul)_overflow", feature = "GCC overflow builtins", reason = "the checked arithmetic builtins are not lowered yet", phase = "P7.6"),
    Rule(pattern = "__builtin_(setjmp|longjmp)\\b", feature = "__builtin_setjmp", reason = "the builtin setjmp pair through the setjmp lowering is not lowered yet", phase = "P7.6"),
    Rule(kind = RuleKind.builtins, feature = "__builtin_* calls", reason = "a builtin outside the emitter's shim list is not lowered yet", phase = "P7.6")
]

//! The attributes the layout reads (`converter/ARCHITECTURE_DUMPER.md`, attributes and asm): a test
//! whose other attributes are all dropped is a layout's.
let LAYOUT_ATTRIBUTES <- {"aligned", "packed"}

//! The attributes the dumper drops, as GCC spells them less their underscores
//! (`converter/ARCHITECTURE_DUMPER.md`, attributes and asm), with `noclone`, `noipa`, `optimize`
//! and `externally_visible`, which clang ignores; a test whose attributes are all here is not
//! skipped.
let DROPPED_ATTRIBUTES <- {"noinline", "noclone", "noipa", "unused", "used", "noreturn", "const", "pure", "always_inline", "nothrow", "cold", "hot", "visibility", "format", "nonnull", "malloc", "warn_unused_result", "deprecated", "weak", "optimize", "may_alias", "section", "leaf", "no_instrument_function", "alloc_size", "returns_nonnull", "nodebug", "fallthrough", "externally_visible", "gnu_inline", "mode"}

//! The builtins the converter lowers (`converter/ARCHITECTURE_EMITTER.md`, the shim list): the
//! libc twins, the hints and the c_runtime builtins.
let MAPPED_BUILTINS <- {"alloca", "abort", "exit", "memcpy", "memmove", "memset", "memcmp", "strlen", "strcpy", "strncpy", "strcmp", "strncmp", "strchr", "printf", "sprintf", "snprintf", "malloc", "calloc", "free", "abs", "copysign", "fabs", "expect", "constant_p", "prefetch", "unreachable", "trap", "huge_val", "offsetof", "va_start", "va_end", "va_copy", "va_arg", "va_list", "c23_va_start", "signbit", "signbitf", "bswap16", "bswap32", "bswap64", "ffs", "ffsl", "ffsll", "ctz", "ctzl", "ctzll", "clz", "clzl", "clzll", "popcount", "popcountl", "popcountll", "parity", "parityl", "parityll", "clrsb", "clrsbl", "clrsbll"}

//! Every attribute name in `text`'s `__attribute__((...))` lists, underscores stripped
//! (`__noinline__` is `noinline`).
def attribute_names(text : string) : array<string> {
    var names : array<string>
    var heads <- regex_compile("__attribute(__)?\\s*\\(\\(")
    var ident <- regex_compile("[A-Za-z_][A-Za-z0-9_]*")
    var starts : array<int>
    var spans : array<int2>
    regex_foreach(heads, text) $(at) {
        starts |> push(at.y)
        return true
    }
    peek_data(text) $(bytes) {
        for (start in starts) {
            // the entries of the list: cut at a comma between the two parentheses, up to the
            // parenthesis that closes them
            var depth = 2
            var from = start
            var idx = start
            while (idx < length(bytes) && depth >= 2) {
                let ch = int(bytes[idx])
                if (ch == '(') {
                    depth++
                } elif (ch == ')') {
                    depth--
                }
                if ((ch == ',' && depth == 2) || depth < 2) {
                    spans |> push(int2(from, idx))
                    from = idx + 1
                }
                idx++
            }
        }
    }
    peek_data(text) $(view) {
        for (span in spans) {
            let entry = slice(view, span.x, span.y)
            let at = regex_search(ident, entry)
            if (at.x >= 0) {
                names |> push(strip_underscores(slice(entry, at.x, at.y)))
            }
        }
    }
    return <- names
}

// a GCC attribute or keyword spelling less its leading and trailing underscores
def private strip_underscores(name : string) : string {
    var first = 0
    var last = length(name)
    while (first < last && starts_with(slice(name, first), "_")) {
        first++
    }
    while (last > first && ends_with(slice(name, first, last), "_")) {
        last--
    }
    return slice(name, first, last)
}

//! The `__builtin_*` names in `text` the converter does not lower.
def unmapped_builtins(text : string) : array<string> {
    var out : array<string>
    var re <- regex_compile("__builtin_[A-Za-z0-9_]+")
    regex_foreach(re, text) $(at) {
        let name = slice(text, at.x + 10, at.y)
        if (!key_exists(MAPPED_BUILTINS, name)) {
            out |> push(name)
        }
        return true
    }
    return <- out
}

//! The index of the first rule `text` matches, -1 for none.
def first_rule(var compiled : array<Regex>; text : string) : int {
    let kept <- [for (n in attribute_names(text)); n; where !key_exists(DROPPED_ATTRIBUTES, n)]
    let layout_only = !empty(kept) && empty([for (n in kept); n; where !key_exists(LAYOUT_ATTRIBUTES, n)])
    for (idx, rule in range(length(RULES)), RULES) {
        if (rule.kind == RuleKind.attributes) {
            if (!empty(kept) && !layout_only) {
                return idx
            }
        } elif (rule.kind == RuleKind.layout) {
            if (layout_only) {
                return idx
            }
        } elif (rule.kind == RuleKind.builtins) {
            if (!empty(unmapped_builtins(text))) {
                return idx
            }
        } elif (regex_search(compiled[idx], text).x >= 0) {
            return idx
        }
    }
    return -1
}

//! The `skip.txt` lines of `ids`, each the first rule its text (`text_of`) matches, less the ids
//! `passing` lists: a test that passes is judged, never skipped.
def skip_lines(var compiled : array<Regex>; ids : array<string>; passing : table<string>; text_of : block<(id : string) : string>) : array<string> {
    var lines : array<string>
    for (id in ids) {
        let idx = key_exists(passing, id) ? -1 : first_rule(compiled, invoke(text_of, id))
        if (idx >= 0) {
            lines |> push("{id}\t{RULES[idx].feature}\t{RULES[idx].reason}\t{RULES[idx].phase}")
        }
    }
    return <- lines
}

def compile_rules : array<Regex> {
    var compiled : array<Regex>
    compiled |> reserve(length(RULES))
    // a rule of another kind keeps its index with a regex never compiled, never searched
    for (rule in RULES) {
        var re <- rule.kind == RuleKind.regex ? regex_compile(rule.pattern) : Regex()
        compiled |> emplace(re)
    }
    return <- compiled
}
