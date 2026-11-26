options gen2
require dastest/testing_boost public
require strings
require math
require daslib/fio
require daslib/strings_boost
require ../../frontend/c_defines.das
require ../cir.das
require ../dumper_a.das
require ../pipeline.das
require ../tiers.das

//! The predefined-macro tables against the pinned clang (`frontend/ARCHITECTURE.md` section 3):
//! every macro clang predefines under a dialect's triple is an entry with clang's value or a name
//! of a listed exclusion class, the dumper's flags leave clang with the table's macros and no
//! other, and a program is dumped under them.

// the classes of predefined names no table holds, each a list of names, a trailing `*` standing
// for any rest
let private EXCLUDED <- [
    (title = "compiler identity and version", names = ["__GNUC__", "__GNUC_MINOR__", "__GNUC_PATCHLEVEL__", "__GNUC_STDC_INLINE__", "__GXX_ABI_VERSION", "__VERSION__",
            "__clang__", "__clang_*", "__llvm__", "_MSC_VER", "_MSC_FULL_VER", "_MSC_BUILD", "_MSC_EXTENSIONS", "_MSVC_*", "_CRT_USE_BUILTIN_OFFSETOF",
            "__CONSTANT_CFSTRINGS__", "__PRAGMA_REDEFINE_EXTNAME", "__GCC_ASM_FLAG_OUTPUTS__", "__GCC_HAVE_DWARF2_CFI_ASM"]),
    (title = "code generation", names = ["__NO_INLINE__", "__NO_MATH_INLINES", "__PIC__", "__PIE__", "__pic__", "__pie__", "__code_model_*", "_M_FP_*",
            "__REGISTER_PREFIX__", "__USER_LABEL_PREFIX__", "__GCC_CONSTRUCTIVE_SIZE", "__GCC_DESTRUCTIVE_SIZE"]),
    (title = "CPU features", names = ["__SSE*", "__MMX__", "__FXSR__", "__k8", "__k8__", "__tune_*", "__SEG_*", "__seg_*"]),
    (title = "atomics", names = ["__ATOMIC_*", "__GCC_ATOMIC_*", "__CLANG_ATOMIC_*", "__GCC_HAVE_SYNC_COMPARE_AND_SWAP_*", "__MEMORY_SCOPE_*"]),
    (title = "other languages", names = ["__OBJC_*", "__OPENCL_*"])]

// the entries no clang defines: the converter's own statement
let private CONVERTER_OWN <- ["__STDC_NO_VLA__=1"]

// the flags of every clang run of the dumper besides its macros
let private DUMPER_FLAGS <- ["-funsigned-char", "-w"]

// the exclusion class of `name`, "" when it has none
def private excluded_as(name : string) : string {
    for (group in EXCLUDED) {
        for (pattern in group.names) {
            if (glob_match(pattern, name)) {
                return group.title
            }
        }
    }
    return ""
}

// the macros clang reports after preprocessing an empty file under `triple` and `flags`
// (`-E -dM`), each as a table entry `NAME=value` or `NAME(params)=value`, sorted; one line
// `clang: ...` when it fails or prints anything else
def private clang_macros(triple : string; flags : array<string>) : array<string> {
    var argv <- [default_clang(), "-target", triple]
    argv |> push_from(DUMPER_FLAGS, flags, ["-E", "-dM", "-x", "c", "/dev/null"])
    var out : string
    let rc = run_and_capture(argv, out, 60.0)
    var entries : array<string>
    let define = "#define "
    for (line in split(out, "\n")) {
        if (rc != 0 || (!empty(line) && !(line |> starts_with(define)))) {
            return <- ["clang: exit {rc}: {out}"]
        }
        if (!empty(line)) {
            // clang prints `NAME body` and `NAME(params) body`: a `(` before the first blank
            // opens the parameters
            let rest = slice(line, length(define))
            let blank = find(rest, " ")
            let paren = find(rest, "(")
            let head_end = paren >= 0 && (blank < 0 || paren < blank) ? find(rest, ")") + 1 : (blank < 0 ? length(rest) : blank)
            entries |> push("{slice(rest, 0, head_end)}={slice(rest, min(head_end + 1, length(rest)))}")
        }
    }
    sort(entries)
    return <- entries
}

// `entry` in the one spelling two equal definitions share
def private canonical(entry : string) : string {
    var parsed : Define
    if (!parse_define(entry, parsed)) {
        return "no entry: {entry}"
    }
    return parsed.fn_like ? "{parsed.name}({join(parsed.params, ",")})={parsed.value}" : "{parsed.name}={parsed.value}"
}

def private name_of(entry : string) : string {
    var parsed : Define
    parse_define(entry, parsed)
    return parsed.name
}

// the canonical entries of `dialect`'s table by name
def private table_of(t : T?; dialect : string) : table<string; string> {
    var error : string
    let entries <- read_predefined(predefined_path(dialect), error)
    t |> equal(error, "")
    return <- {for (entry in entries); name_of(entry) => canonical(entry)}
}

// the names of `entries`
def private names_of(entries : array<string>) : table<string> {
    var names : table<string>
    for (entry in entries) {
        names |> insert(name_of(entry))
    }
    return <- names
}

[test(description = "each table is clang's predefined set less the listed exclusion classes, value for value", timeout = 1200)]
def test_tables_partition_clang(t : T?) {
    for (dialect in DIALECTS) {
        t |> run("{dialect}: every macro clang predefines is an entry with clang's value or a name of one exclusion class, never both") @(t : T?) {
            var inscope by_name <- table_of(t, dialect)
            let clang <- clang_macros(target_by_name(dialect).triple, array<string>())
            t |> success(length(clang) > 100, "{dialect}: {clang[0]}")
            for (entry in clang) {
                let name = name_of(entry)
                let group = excluded_as(name)
                if (!empty(group)) {
                    t |> success(!key_exists(by_name, name), "{dialect}: `{name}` is an entry and is excluded as {group}")
                } else {
                    t |> equal(by_name?[name] ?? "{name}: no entry and no exclusion class", canonical(entry), dialect)
                }
            }
        }
        t |> run("{dialect}: every entry is a macro clang predefines, or the converter's own") @(t : T?) {
            var inscope by_name <- table_of(t, dialect)
            var inscope clang_names <- names_of(clang_macros(target_by_name(dialect).triple, array<string>()))
            var own = 0
            for (name, entry in keys(by_name), values(by_name)) {
                if (!key_exists(clang_names, name)) {
                    own++
                    t |> success(has_value(CONVERTER_OWN, entry), "{dialect}: `{entry}` is no macro of clang's and none of the converter's own")
                }
            }
            t |> equal(own, length(CONVERTER_OWN))
        }
        t |> run("{dialect}: every macro `-undef` leaves is an entry with its value") @(t : T?) {
            var inscope by_name <- table_of(t, dialect)
            let left <- clang_macros(target_by_name(dialect).triple, ["-undef"])
            t |> success(length(left) >= 7 && length(left) < 20, "{dialect}: -undef leaves {length(left)}: {left[0]}")
            for (entry in left) {
                t |> equal(by_name?[name_of(entry)] ?? "{entry}: left by -undef, no entry", canonical(entry), dialect)
            }
        }
    }
    t |> run("every name and prefix of an exclusion class matches a macro clang predefines under a dialect") @(t : T?) {
        var all : array<string>
        for (dialect in DIALECTS) {
            all |> push_from(clang_macros(target_by_name(dialect).triple, array<string>()))
        }
        for (group in EXCLUDED) {
            for (pattern in group.names) {
                var hit = false
                for (entry in all) {
                    hit = hit || glob_match(pattern, name_of(entry))
                }
                t |> success(hit, "`{pattern}` of `{group.title}` matches no macro clang predefines")
            }
        }
    }
}

[test(description = "the dumper's macro flags leave clang with the table's macros and the converter's, and no other", timeout = 1200)]
def test_dumper_macro_flags(t : T?) {
    for (dialect in DIALECTS) {
        t |> run("{dialect}: `-undef`, the table in its order as -D, then the converter's own define; clang takes them with no error") @(t : T?) {
            var error : string
            let flags <- frontend_macro_flags(predefined_table(target_by_name(dialect)), error)
            t |> equal(error, "")
            var table_error : string
            let entries <- read_predefined(predefined_path(dialect), table_error)
            var expected <- ["-undef"]
            expected |> push_from([for (entry in entries); "-D{entry}"], CONVERTER_DEFINES)
            t |> equal(join(flags, "\n"), join(expected, "\n"))
            var defined <- [for (entry in entries); canonical(entry)]
            defined |> push_from([for (flag in CONVERTER_DEFINES); canonical(slice(flag, 2))])
            sort(defined)
            let seen <- clang_macros(target_by_name(dialect).triple, flags)
            t |> equal(join([for (entry in seen); canonical(entry)], "\n"), join(defined, "\n"))
        }
    }
    t |> run("a table that is missing fails naming its path, and gives no flag to run clang under") @(t : T?) {
        let missing = path_join(test_temp_dir(), "no_such_dialect.defs")
        var error : string
        let flags <- frontend_macro_flags(missing, error)
        t |> equal(error, "{missing}: no such predefined-macro table")
        t |> equal(length(flags), 0)
    }
}

// a program printing which compiler names it sees, a table macro in an expression and in an
// `#if`, and `__STDC_VERSION__`
let private IDENTITY_SOURCE = "int printf(const char *, ...);\n#if defined(__GNUC__) || defined(__clang__) || defined(_MSC_VER) || defined(__llvm__)\n#define WHO 1\n#else\n#define WHO 0\n#endif\n#if __SIZEOF_INT__ == 4 && __STDC_NO_VLA__\n#define SIZED 1\n#else\n#define SIZED 0\n#endif\nint main(void) \{ int top = __INT_MAX__; long version = __STDC_VERSION__; printf(\"%d %d %d %ld %d\\n\", WHO, SIZED, top, version, __CHAR_BIT__ * (int)sizeof(__SIZE_TYPE__)); return 0; \}\n"

// `IDENTITY_SOURCE` converted under `dialect` in `<dir>/<name>`, `sidecar` beside it when given,
// and run under the interpreter: its output
def private identity_run(t : T?; dir, name, dialect, sidecar : string) : string {
    let at = path_join(dir, name)
    mkdir_rec(at)
    let c_path = path_join(at, "identity.c")
    fwrite(c_path, IDENTITY_SOURCE)
    if (!empty(sidecar)) {
        fwrite(path_join(at, "identity.c2das"), sidecar)
    }
    let conv <- convert(c_path, path_join(at, "out"), dialect)
    if (!conv.ok) {
        t |> failure(conv.error)
        return ""
    }
    var output : string
    let rc = run_tier(conv.das_path, "interp", at, output, CONVERTED_MODULES)
    t |> equal(rc, 0, output)
    return output
}

[test(description = "a program is dumped under the table: no compiler's name, the table's values, a sidecar define over them", timeout = 1200)]
def test_dump_under_the_table(t : T?) {
    var dir_error : string
    let dir = create_temp_directory("c2das_predefined", dir_error)
    if (!empty(dir_error)) {
        t |> failure("no temp directory: {dir_error}")
        return
    }
    t |> run("under both dialects the program sees no compiler's name, and the table's sizes, limits and language") @(t : T?) {
        for (dialect in DIALECTS) {
            t |> equal(identity_run(t, dir, dialect, dialect, ""), "0 1 2147483647 201710 64\n", dialect)
        }
    }
    t |> run("a sidecar's define of a table's name comes later and wins") @(t : T?) {
        let side = "\{\"defines\": [\"__STDC_VERSION__=199901L\", \"__GNUC__=4\"]\}\n"
        t |> equal(identity_run(t, dir, "sidecar", "linux", side), "1 1 2147483647 199901 64\n")
    }
    rmdir_rec(dir)
}
