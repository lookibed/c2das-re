options gen2

module audit_constructs public

require strings
require daslib/strings_boost
require daslib/fio
require daslib/json_boost

//! The constructs of the interpreter audit on Lua (P7.0b): each a kernel under
//! `perf/kernels/audit/`, the text whose occurrences in Lua's hot modules count its sites, and a
//! rewrite of the kernel's converted module into the spelling a fix would emit, so the two
//! interpreter times of one kernel give the construct's own cost (`ARCHITECTURE_AUDIT.md`).

//! the folder of the audit's kernels
let AUDIT_KERNELS = "perf/kernels/audit"

//! Lua's hot modules, by the file stem the converter names each module or fragment after
let HOT_FILES <- ["lvm", "ltable", "lgc", "ldo"]

//! A converted module's text rewritten into the alternative spelling: the new text, or "" with
//! `error` naming the text the rewrite did not find.
typedef Rewrite = function<(text : string; var error : string&) : string>

//! One construct: `name` as the table names it, the `kernel` that isolates it, the `spelling`
//! spelling the rewrite gives, and `sites`, the text counted in Lua's hot modules.
struct Construct {
    name : string
    kernel : string
    spelling : string
    sites : string
    rewrite : Rewrite
}

//! `text` with every `old` replaced by `by`, or "" with `error` set when `old` does not occur.
def replaced(text, old, by : string; var error : string&) : string {
    if (find(text, old) < 0) {
        error = "no `{old}` in the converted module"
        return ""
    }
    return replace(text, old, by)
}

//! `replaced` over each pair in order, stopping at the first that does not occur.
def replaced_all(text : string; pairs : array<tuple<old : string; by : string>>; var error : string&) : string {
    var out = text
    for (p in pairs) {
        out = replaced(out, p.old, p.by, error)
        if (empty(out)) {
            return ""
        }
    }
    return out
}

let private PLAIN_CASE = "if (_goto == 0 && _cond == "

//! The former `_flag` switch chain (before P7.0c) of a switch a goto re-dispatches: every plain case
//! of one label `if (_goto == 0 && _cond == K) \{` (a case of several labels, `(_cond == A ||
//! _cond == B)`, is left as it is: the audit kernel has none) becomes `_flag ||= _goto == 0 && _cond == K` followed by
//! `if (_flag) \{`, which the flag loop's `var _flag = false` serves. A plain case leaves the switch
//! at its end, so the flag it sets is never read: the two spellings run the same program, and the
//! converted time over this rewrite's is the inverse of the chain's cost.
def flag_chain(text : string; var error : string&) : string {
    let lines <- split(text, "\n")
    var out : array<string>
    out |> reserve(length(lines) + 64)
    var taken = 0
    for (line in lines) {
        let head = strip_left(line)
        if (head |> starts_with(PLAIN_CASE) && head |> ends_with(") \{")) {
            let indent = slice(line, 0, length(line) - length(head))
            out |> push("{indent}_flag ||= _goto == 0 && _cond == {slice(head, length(PLAIN_CASE), length(head) - 3)}")
            out |> push("{indent}if (_flag) \{")
            taken++
        } else {
            out |> push(line)
        }
    }
    if (taken == 0) {
        error = "no plain switch case in the converted module"
        return ""
    }
    return join(out, "\n")
}

let private ADDR_DEREF = "addr(deref("

// what a closing parenthesis ends in `unwrap_addr_deref`'s scan
enum private Paren {
    plain
    addr_call
    deref_call
}

// whether `bytes` holds `word` at `at`
def private holds_at(bytes : array<uint8>#; at : int; word : array<uint8>#) : bool {
    if (at + length(word) > length(bytes)) {
        return false
    }
    for (i in range(length(word))) {
        if (bytes[at + i] != word[i]) {
            return false
        }
    }
    return true
}

//! Every `addr(deref(<pointer>))` as `(<pointer>)`: the address of what a pointer points at is the
//! pointer. One pass over the bytes with a stack of open parentheses, so a nested one unwraps too.
def unwrap_addr_deref(text : string; var error : string&) : string {
    if (find(text, ADDR_DEREF) < 0) {
        error = "no `{ADDR_DEREF}` in the converted module"
        return ""
    }
    var out : string
    peek_data(ADDR_DEREF) $(word) {
        peek_data(text) $(bytes) {
            out = unwrapped(bytes, word, error)
        }
    }
    return empty(error) ? out : ""
}

// the scan of `unwrap_addr_deref` over the text's `bytes`, `word` the bytes of `ADDR_DEREF`
def private unwrapped(bytes, word : array<uint8>#; var error : string&) : string {
    var inscope stack : array<Paren>
    return build_string() $(writer) {
        var i = 0
        while (i < length(bytes) && empty(error)) {
            let c = int(bytes[i])
            if (holds_at(bytes, i, word)) {
                write_char(writer, '(')
                stack |> push_from([Paren.addr_call, Paren.deref_call])
                i += length(word)
                continue
            }
            if (c == '(') {
                stack |> push(Paren.plain)
            } elif (c == ')' && !empty(stack)) {
                let top = stack |> back()
                stack |> pop()
                if (top == Paren.deref_call) {
                    if (i + 1 >= length(bytes) || int(bytes[i + 1]) != ')') {
                        error = "an unbalanced `{ADDR_DEREF}` before byte {i}"
                    }
                    stack |> pop()
                    write_char(writer, ')')
                    i += 2
                    continue
                }
            }
            write_char(writer, c)
            i++
        }
    }
}

def private union_members(text : string; var error : string&) : string {
    return replaced_all(text, [(old = "addr(reinterpret<GCUnion?>(v.value_.gc).h)", by = "reinterpret<Table?>(v.value_.gc)"),
                               (old = "addr(reinterpret<GCUnion?>(v.value_.gc).cl)", by = "reinterpret<Closure?>(v.value_.gc)")], error)
}

def private slot_casts(text : string; var error : string&) : string {
    return replaced_all(text, [(old = "addr((base + a + 1).val)", by = "reinterpret<TValue?>(base + a + 1)"),
                               (old = "addr((base + a).val)", by = "reinterpret<TValue?>(base + a)"),
                               (old = "addr((base + a + 2).val)", by = "reinterpret<TValue?>(base + a + 2)")], error)
}

def private folded_masks(text : string; var error : string&) : string {
    return replaced_all(text, [(old = "i >> 0u & ~(~uint(0) << 7u) << 0u", by = "i & 127u"),
                               (old = "~(~uint(0) << 8u) << 0u", by = "255u"),
                               (old = "uint(0 + 7 + 8 + 1 + 8)", by = "24u"),
                               (old = "uint(0 + 7 + 8 + 1)", by = "16u"),
                               (old = "uint(0 + 7)", by = "7u")], error)
}

// the test before P7.0e, the hint's operand widened to `long` and tested against 0: the converter
// writes `trap != 0` since, so the rewrite restores the round trip and the row's factor is the
// inverse of its cost
def private expect_roundtrip(text : string; var error : string&) : string => replaced(text, "if (trap != 0) \{", "if (int64(trap != 0 ? 1 : 0) != 0) \{", error)

def private plain_load(text : string; var error : string&) : string => replaced(text, "c_volatile_load(ci.trap)", "ci.trap", error)

let private SETJMP_LOOP = join([
    "    var _sj_run = true",
    "    var _sj_val = 0",
    "    while (_sj_run) \{",
    "        _sj_run = false",
    "        try \{",
    "            if (_sj_val == 0) \{",
    "                protected_call__body(k)",
    "            \}",
    "            protected_call__error_jmp = lj.previous",
    "            return c_volatile_load(lj.status)",
    "        \} recover \{",
    "            if (c_jmp_target != addr(lj.b)) \{",
    "                panic(\"longjmp\")",
    "            \}",
    "            c_jmp_target = null",
    "            _sj_val = lj.b.val",
    "            _sj_run = true",
    "        \}",
    "    \}",
    "    return 0"], "\n")

let private FLAT_TRY = join([
    "    try \{",
    "        protected_call__body(k)",
    "    \} recover \{",
    "        if (c_jmp_target != addr(lj.b)) \{",
    "            panic(\"longjmp\")",
    "        \}",
    "        c_jmp_target = null",
    "    \}",
    "    protected_call__error_jmp = lj.previous",
    "    return c_volatile_load(lj.status)"], "\n")

let private NO_TRY = join([
    "    protected_call__body(k)",
    "    protected_call__error_jmp = lj.previous",
    "    return c_volatile_load(lj.status)"], "\n")

def private flat_try(text : string; var error : string&) : string => replaced(text, SETJMP_LOOP, FLAT_TRY, error)

def private no_try(text : string; var error : string&) : string => replaced(text, SETJMP_LOOP, NO_TRY, error)

def private inlined_call(text : string; var error : string&) : string {
    let body = "let key_r = (key + int64(r)) % int64(70)\n                var v : int64? = uint64(key_r) - uint64(1u) < uint64(t.alimit) ? addr(deref(t._c_array + (key_r - int64(1)))) : null"
    return replaced(text, "var v : int64? = small_call__luaH_getint(t, (key + int64(r)) % int64(70))", body, error)
}

def private byte_read(text : string; var error : string&) : string => replaced(text, "uint(uint8(deref(str + (l - uint64(1)))))", "uint(deref(str + (l - uint64(1))))", error)

def private enum_reinterpret(text : string; var error : string&) : string => replaced(text, "enum_from_int(type<OpCode>, int((enum_cast__code[pc] ^ uint(r)) & 7u))", "unsafe(reinterpret<OpCode>(int((enum_cast__code[pc] ^ uint(r)) & 7u)))", error)

// the wrap casts before P7.0d: the converter folds `int64(uint64(a) op uint64(b))` into `a op
// int64(b)` since, an assignment of it into `a op= int64(b)`, so the rewrite restores the casts and
// the row's factor is the inverse of their cost
def private wrap_casts(text : string; var error : string&) : string {
    return replaced_all(text, [(old = "acc += int64(imm)", by = "acc = int64(uint64(acc) + uint64(imm))"),
                               (old = "acc ^= wrap_cast__regs[k] * int64(3)", by = "acc = int64(uint64(acc) ^ uint64(int64(uint64(wrap_cast__regs[k]) * uint64(3))))")], error)
}

def private literal_sizes(text : string; var error : string&) : string => replaced_all(text, [(old = "typeinfo sizeof(type<Pair>)", by = "16"), (old = "typeinfo sizeof(type<int64>)", by = "8")], error)

//! Every construct the audit measures, in the table's order.
def constructs : array<Construct> {
    return <- [
        Construct(name = "`_flag` switch chain", kernel = "dispatch_switch", spelling = "flag-chain", sites = "if (_goto == 0 && _cond ==", rewrite = @@flag_chain),
        Construct(name = "union member through `reinterpret<GCUnion?>`", kernel = "union_access", spelling = "member-cast", sites = "reinterpret<GCUnion?>(", rewrite = @@union_members),
        Construct(name = "`addr((p + i).f)` on a stack slot", kernel = "stack_ptr", spelling = "slot-cast", sites = "addr((", rewrite = @@slot_casts),
        Construct(name = "`addr(deref(p + i))` indexing", kernel = "node_index", spelling = "pointer", sites = ADDR_DEREF, rewrite = @@unwrap_addr_deref),
        Construct(name = "`enum_from_int` on the opcode", kernel = "enum_cast", spelling = "reinterpret", sites = "enum_from_int(", rewrite = @@enum_reinterpret),
        Construct(name = "macro mask arithmetic on `uint`", kernel = "instr_decode", spelling = "folded", sites = "~(~uint(0) <<", rewrite = @@folded_masks),
        Construct(name = "`int64(x != 0 ? 1 : 0) != 0` test", kernel = "trap_check", spelling = "expect-roundtrip", sites = "? 1 : 0) != 0", rewrite = @@expect_roundtrip),
        Construct(name = "`c_volatile_load` of a volatile field", kernel = "trap_check", spelling = "plain-load", sites = "c_volatile_load(", rewrite = @@plain_load),
        Construct(name = "`setjmp` trampoline (`while (_sj_run)`)", kernel = "protected_call", spelling = "flat-try", sites = "while (_sj_run)", rewrite = @@flat_try),
        Construct(name = "`try`/`recover` itself", kernel = "protected_call", spelling = "no-try", sites = "\} recover \{", rewrite = @@no_try),
        Construct(name = "a call of a small function (`luaH_get*`)", kernel = "small_call", spelling = "inlined", sites = "luaH_get", rewrite = @@inlined_call),
        Construct(name = "`uint8(deref(p + i))` byte read", kernel = "string_hash", spelling = "no-cast", sites = "uint8(deref(", rewrite = @@byte_read),
        Construct(name = "wrap casts `int64(uint64(a) op uint64(b))`", kernel = "wrap_cast", spelling = "wrap-casts", sites = "int64(uint64(", rewrite = @@wrap_casts),
        Construct(name = "`typeinfo sizeof` in a hot loop", kernel = "sizeof_scale", spelling = "literal", sites = "typeinfo sizeof", rewrite = @@literal_sizes)
    ]
}

//! The occurrences of `needle` in `text`.
def occurrences(text, needle : string) : int {
    var n = 0
    var at = find(text, needle)
    while (at >= 0) {
        n++
        at = find(text, needle, at + length(needle))
    }
    return n
}

//! The text of Lua's hot module `stem` in the converted program folder `dir`: the scc layout's
//! fragment `<stem>.das.inc`, else the module `<stem>.das`; "" when neither is there.
def hot_text(dir, stem : string) : string {
    for (file in ["{stem}.das.inc", "{stem}.das"]) {
        let path = path_join(dir, file)
        if (fexist(path)) {
            return fread(path)
        }
    }
    return ""
}

//! Each construct's sites per hot module of the converted program folder `dir`, or `error` when
//! a hot module is missing.
def site_counts(dir : string) : JsonValue? {
    var texts : table<string; string>
    for (stem in HOT_FILES) {
        texts[stem] = hot_text(dir, stem)
        if (empty(texts[stem])) {
            return JV({"error" => JV("no {stem} in {dir}: convert Lua first (lua/run.das --filter lua --layout scc)")})
        }
    }
    var rows <- {for (c in constructs()); c.spelling => JV({for (stem in HOT_FILES); stem => JV(occurrences(texts[stem], c.sites))})}
    return JV(rows)
}

