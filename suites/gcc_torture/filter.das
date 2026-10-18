options gen2

require strings
require daslib/strings_boost
require daslib/fio
require daslib/regex
require daslib/regex_boost

//! The torture import's filter (`daslang suites/gcc_torture/filter.das` from the repository
//! root, after a fetch): every `execute/*.c` whose text carries a GNU extension outside the
//! dialect, or a construct a later row owns, gets its `skip.txt` line - id, feature, reason,
//! the phase that unblocks it, `never` for a feature the dialect excludes. The rest ratchet.

let TESTS_DIR = "suites/gcc_torture/fetch/gcc/gcc/testsuite/gcc.c-torture/execute"
let SKIP_LEDGER = "suites/gcc_torture/skip.txt"

struct Rule {
    pattern : string
    feature : string
    reason : string
    phase : string
}

// first match wins: the dialect's exclusions before the rows that will carry a construct
let RULES <- [
    Rule(pattern = "\\basm\\b|__asm__", feature = "inline asm", reason = "machine code has no das spelling (c-ir-spec section 9)", phase = "never"),
    Rule(pattern = "_Complex|__complex__|__real__|__imag__", feature = "_Complex", reason = "complex arithmetic is outside the dialect (c-ir-spec section 9)", phase = "never"),
    Rule(pattern = "__int128", feature = "__int128", reason = "no 128-bit integer in das or the dialect", phase = "never"),
    Rule(pattern = "_Float[0-9]|__float128|__fp16|_Decimal", feature = "non-standard floating types", reason = "float and double are the dialect's floating types", phase = "never"),
    Rule(pattern = "vector_size", feature = "GNU vector extension", reason = "SIMD vector types are outside the dialect", phase = "never"),
    Rule(pattern = "__sync_|__atomic_|__thread|_Thread_local", feature = "atomics and thread-local storage", reason = "single-threaded dialect", phase = "never"),
    Rule(pattern = "__label__|&&[A-Za-z_]", feature = "computed goto and local labels", reason = "the goto row lowers labels, and computed goto rides on das's integer labels", phase = "P3"),
    Rule(pattern = "__builtin_", feature = "__builtin_* calls", reason = "a builtin maps through a shim list that the punning tier grows", phase = "P4"),
    Rule(pattern = "__attribute__", feature = "__attribute__", reason = "an attribute reaches the dialect through the sidecar (packed, aligned) or is dropped (noinline), neither read yet", phase = "P4"),
    Rule(pattern = "__typeof|\\btypeof *\\(|__extension__|__alignof", feature = "GNU keywords", reason = "typeof, __extension__ and __alignof__ have no row", phase = "never"),
    Rule(pattern = "case [^:\n]*\\.\\.\\.", feature = "GNU case range", reason = "`case a ... b` is a GNU extension; the dialect's switch takes one value per label", phase = "never")
]

def file_text(path : string) : string {
    var text = ""
    fopen(path, "rb") $(f) {
        if (f != null) {
            text = fread(f)
        }
    }
    return text
}

[export]
def main : int {
    if (!fexist(TESTS_DIR)) {
        to_log(LOG_ERROR, "{TESTS_DIR} is missing: run suites/gcc_torture/fetch.sh\n")
        return 2
    }
    var compiled : array<Regex>
    compiled |> reserve(length(RULES))
    for (rule in RULES) {
        var re <- regex_compile(rule.pattern)
        compiled |> emplace(re)
    }
    var ids : array<string>
    dir(TESTS_DIR) $(name) {
        if (name |> ends_with(".c")) {
            ids |> push(slice(name, 0, length(name) - 2))
        }
    }
    ids |> sort()
    var lines : array<string>
    for (id in ids) {
        let text = file_text("{TESTS_DIR}/{id}.c")
        for (idx, rule in range(length(RULES)), RULES) {
            if (regex_search(compiled[idx], text).x >= 0) {
                lines |> push("{id}\t{rule.feature}\t{rule.reason}\t{rule.phase}")
                break
            }
        }
    }
    fopen(SKIP_LEDGER, "wb") $(f) {
        if (f != null) {
            fwrite(f, "# gcc-torture execute tests never run, one per line: id, feature, reason, the phase that\n# unblocks it (never for a feature the dialect excludes), tab-separated; written by\n# suites/gcc_torture/filter.das over the fetched tree. A test that merely does not pass yet\n# is not listed; the ratchet reports it.\n")
            for (line in lines) {
                fwrite(f, "{line}\n")
            }
        }
    }
    to_log(LOG_INFO, "filter: {length(lines)} of {length(ids)} tests skipped\n")
    return 0
}
