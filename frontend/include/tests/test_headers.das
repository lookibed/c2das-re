options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require daslib/rtti
require crt
require _header_scan
require ../../tests/_own_header_names.das
require ../../c_defines.das
require ../../../converter/emit.das

//! The own libc headers against what a converted program can call
//! (`frontend/include/ARCHITECTURE.md` section 2): the prototypes are the C names `crt` binds and
//! the libc names the emitter lowers, the `extern` objects the emitter's libc objects, and every
//! `crt` constant a macro. The `crt` side is read from the loaded module, the headers as text.

// what glibc's `sigsetjmp` macro calls: the emitter maps it, and no header declares it, there
// being no `siglongjmp` to pair it with
let private GLIBC_ALIASES <- ["__sigsetjmp"]

// the crt functions the printf lowering writes through, named after the C function they forward to
let private STDOUT_HELPERS <- ["fwrite_stdout", "fflush_stdout"]

// the c_runtime pieces whose functions crt serves one directive at a time, as `<function>_<kind>`
let private DIRECTIVE_PIECES <- {"c_runtime/printf", "c_runtime/scanf"}

// the crt constant that is no C name: the width of the host's `long`
let private HOST_ONLY_CONSTANT = "LONG_BITS"

//! The macros the headers read that the compiler predefines (`ARCHITECTURE.md`, the predefined
//! names): the list a compiler run without its own predefined macros has to be given.
let PREDEFINED <- [
    "__CHAR_BIT__", "__CHAR_UNSIGNED__", "__DBL_DIG__", "__DBL_EPSILON__", "__DBL_MANT_DIG__", "__DBL_MAX_10_EXP__", "__DBL_MAX_EXP__",
    "__DBL_MAX__", "__DBL_MIN_10_EXP__", "__DBL_MIN_EXP__", "__DBL_MIN__", "__FLT_DIG__", "__FLT_EPSILON__",
    "__FLT_MANT_DIG__", "__FLT_MAX_10_EXP__", "__FLT_MAX_EXP__", "__FLT_MAX__", "__FLT_MIN_10_EXP__", "__FLT_MIN_EXP__",
    "__FLT_MIN__", "__FLT_RADIX__", "__INT64_TYPE__", "__INT_MAX__", "__LONG_LONG_MAX__", "__LONG_MAX__",
    "__PTRDIFF_TYPE__", "__SCHAR_MAX__", "__SHRT_MAX__", "__SIZE_TYPE__", "__WCHAR_TYPE__"]

// the language's own names of that shape, which `<assert.h>` reads
let private LANGUAGE_NAMES <- {"__FILE__", "__LINE__"}

def private scan_headers : HeaderScan {
    var scan : HeaderScan
    var inscope names <- header_names()
    for (name in names) {
        scan_header(scan, name, fread(path_join(own_include_dir(), name)))
    }
    finish_scan(scan)
    return <- scan
}

// the names of the predefined shape in `text`: two underscores, capitals, digits and underscores,
// two underscores, a whole identifier
def private predefined_shaped(text : string; var names : table<string>) {
    var inscope words <- identifier_words(text)
    for (word in words) {
        if (length(word) > 4 && word |> starts_with("__") && word |> ends_with("__") && word == to_upper(word)) {
            names |> insert(word)
        }
    }
}

def private scan_text(text : string) : HeaderScan {
    var scan : HeaderScan
    scan_header(scan, "t.h", text)
    finish_scan(scan)
    return <- scan
}

// the libc names the emitter lowers itself: its c_runtime table less the compiler builtins, and `setjmp`
def private lowered_names : table<string> {
    var names : table<string>
    for (name in keys(C_RUNTIME_CALLS)) {
        if (!(name |> starts_with("__builtin_"))) {
            names |> insert(name)
        }
    }
    for (name in keys(SETJMP_NAMES)) {
        names |> insert(name)
    }
    return <- names
}

// whether the crt function `name` is a helper with no C prototype: a `c_` name, a per-directive
// form of a function the printf or scanf piece lowers, or a stdout helper
def private is_crt_helper(name : string) : bool {
    let split_at = rfind(name, "_")
    let family = split_at > 0 ? slice(name, 0, split_at) : ""
    return (name |> starts_with("c_") || key_exists(DIRECTIVE_PIECES, C_RUNTIME_CALLS?[family]?.piece ?? "")
        || has_value(STDOUT_HELPERS, name))
}

def private bound_spelling(info) : string {
    if (info.basicType != Type.tPointer) {
        return to_lower(slice("{info.basicType}", 1))
    }
    if (info.firstType == null || info.firstType.basicType == Type.tVoid) {
        return "void?"
    }
    return "{bound_spelling(*info.firstType)}{info.firstType.isConst ? " const" : ""}?"
}

// every crt function that is a C name with its das signature, `result(parameter, ...)`
def private crt_signatures : table<string; string> {
    var signatures : table<string; string>
    module_for_each_function(get_module("crt")) $(info) {
        let name = clone_string(info.name)
        if (!is_crt_helper(name)) {
            var inscope params : array<string>
            for (param in info) {
                params |> push(bound_spelling(param))
            }
            signatures |> insert(name, "{bound_spelling(*info.result)}({join(params, ", ")})")
        }
    }
    return <- signatures
}

def private header_signature(typedefs : table<string; string>; proto : Prototype) : string =>
    "{das_spelling(typedefs, proto.result)}({join([for (param in proto.params); das_spelling(typedefs, param)], ", ")})"

def private only_in(names : array<string>; other : table<string>) : string {
    var inscope left <- [for (name in names); name; where !key_exists(other, name)]
    sort(left)
    return join(left, " ")
}

[test(description = "the headers declare exactly what crt binds under a C name and the emitter lowers, in crt's shapes")]
def test_headers_declare_the_runtime(t : T?) {
    t |> run("every line of every header has a form the scanner knows") @(t : T?) {
        let scan <- scan_headers()
        t |> equal(join(scan.errors, "\n"), "")
        t |> success(!empty(scan.prototypes), "no header under {own_include_dir()}")
    }
    t |> run("an #include names a header of the set") @(t : T?) {
        let scan <- scan_headers()
        for (name in scan.includes) {
            t |> success(fexist(path_join(own_include_dir(), name)), "<{name}> is no header of the set")
        }
    }
    t |> run("a function is declared once") @(t : T?) {
        let scan <- scan_headers()
        var seen : table<string; string>
        for (proto in scan.prototypes) {
            t |> success(!key_exists(seen, proto.name), "`{proto.name}` is declared in {seen?[proto.name] ?? ""} and {proto.header}")
            seen |> insert(proto.name, proto.header)
        }
    }
    t |> run("the prototypes are the C names crt binds and the libc names the emitter lowers") @(t : T?) {
        let scan <- scan_headers()
        let signatures <- crt_signatures()
        let lowered <- lowered_names()
        var expected : table<string>
        for (name in keys(signatures)) {
            expected |> insert(name)
        }
        for (name in keys(lowered)) {
            expected |> insert(name)
        }
        for (alias in GLIBC_ALIASES) {
            t |> success(key_exists(lowered, alias), "`{alias}` is an alias the emitter no longer maps")
            expected |> erase(alias)
        }
        var declared : table<string>
        for (proto in scan.prototypes) {
            declared |> insert(proto.name)
        }
        t |> equal(only_in([for (name in keys(expected)); name], declared), "", "bound or lowered, declared by no header")
        t |> equal(only_in([for (proto in scan.prototypes); proto.name], expected), "", "declared, neither bound by crt nor lowered")
    }
}

[test(description = "a crt function's prototype has the bind's shape, and crt's objects, constants and the predefined names are the headers'")]
def test_headers_match_crt(t : T?) {
    t |> run("a prototype of a crt function has the bind's parameters and result") @(t : T?) {
        let scan <- scan_headers()
        let signatures <- crt_signatures()
        for (proto in scan.prototypes) {
            if (key_exists(signatures, proto.name)) {
                t |> equal(header_signature(scan.typedefs, proto), signatures?[proto.name] ?? "", "{proto.header}: `{proto.name}`")
            }
        }
    }
    t |> run("the predefined macros the headers read are the listed ones") @(t : T?) {
        var read : table<string>
        let names <- header_names()
        for (name in names) {
            predefined_shaped(fread(path_join(own_include_dir(), name)), read)
        }
        for (name in keys(LANGUAGE_NAMES)) {
            read |> erase(name)
        }
        var found <- [for (name in keys(read)); name]
        sort(found)
        t |> equal(join(found, " "), join(PREDEFINED, " "))
    }
    t |> run("an include guard is its header's own, defined by its header alone") @(t : T?) {
        let scan <- scan_headers()
        var seen : table<string>
        for (guard in scan.guards) {
            t |> success(!key_exists(seen, guard) && !has_value(scan.defined, guard), "`{guard}` is defined beside its guard")
            seen |> insert(guard)
        }
        t |> success(!empty(scan.guards), "no header has a guard")
    }
    t |> run("a predefined type macro a prototype may bottom out in is a listed predefined name") @(t : T?) {
        for (base in keys(BASE_TYPES)) {
            for (word in split(base, " ")) {
                t |> success(!(word |> starts_with("__") && word |> ends_with("__")) || has_value(PREDEFINED, word), "`{word}` is pinned and not listed")
            }
        }
    }
    t |> run("a named crt helper is a function crt exports") @(t : T?) {
        var exported : table<string>
        module_for_each_function(get_module("crt")) $(info) {
            exported |> insert(clone_string(info.name))
        }
        for (helper in STDOUT_HELPERS) {
            t |> success(key_exists(exported, helper), "`{helper}` is no crt function")
        }
    }
    t |> run("the extern objects are the emitter's libc objects") @(t : T?) {
        let scan <- scan_headers()
        var objects <- clone_to_move(scan.objects)
        var mapped <- [for (name in keys(CRT_OBJECTS)); name]
        sort(objects)
        sort(mapped)
        t |> equal(join(objects, " "), join(mapped, " "))
    }
    t |> run("every crt constant that is a C name is a macro of a header") @(t : T?) {
        let scan <- scan_headers()
        var macros : table<string>
        for (name in scan.macros) {
            macros |> insert(name)
        }
        var constants : array<string>
        module_for_each_global(get_module("crt")) $(info) {
            constants |> push(clone_string(info.name))
        }
        t |> success(has_value(constants, HOST_ONLY_CONSTANT), "crt has no `{HOST_ONLY_CONSTANT}`")
        for (name in constants) {
            t |> success(name == HOST_ONLY_CONSTANT || key_exists(macros, name), "crt's `{name}` is a macro of no header")
        }
    }
}

// every line that defines the macro `name`, `|` between them
def private defined_as(scan : HeaderScan; name : string) : string =>
    join([for (define in scan.defines); define.text; where define.name == name], " | ")

[test(description = "the macro of an integer crt constant has the value the loaded crt holds")]
def test_headers_constant_values(t : T?) {
    t |> run("an integer crt constant's macro is defined once, as the value crt holds") @(t : T?) {
        let scan <- scan_headers()
        let values <- [
            "CLOCKS_PER_SEC ((clock_t) {crt::CLOCKS_PER_SEC})", "RAND_MAX {crt::RAND_MAX}", "EDOM {crt::EDOM}",
            "ERANGE {crt::ERANGE}", "EINVAL {crt::EINVAL}"]
        for (value in values) {
            t |> equal(defined_as(scan, split(value, " ")[0]), value)
        }
        var integers : array<string>
        module_for_each_global(get_module("crt")) $(info) {
            if (info.basicType != Type.tDouble) {
                integers |> push(clone_string(info.name))
            }
        }
        t |> equal(length(integers), length(values) + 1, "the integer constants of crt, {HOST_ONLY_CONSTANT} among them: {join(integers, " ")}")
    }
}

// a header `t.h` of the lines `body` inside its include guard
def private guarded(body : string) : string => "#ifndef _T_H\n#define _T_H\n{body}#endif\n"

[test(description = "every predefined macro the headers read is an entry of each dialect's predefined-macro table")]
def test_headers_read_the_tables(t : T?) {
    for (dialect in DIALECTS) {
        var error : string
        var inscope entries <- read_predefined(predefined_path(dialect), error)
        t |> equal(error, "")
        var parsed : c_defines::Define
        var inscope defined : table<string>
        for (entry in entries) {
            parse_define(entry, parsed)
            defined |> insert(parsed.name)
        }
        for (name in PREDEFINED) {
            t |> success(key_exists(defined, name), "the {dialect} table defines no `{name}`")
        }
    }
}

[test(description = "the scanner reads each line form and refuses every other line")]
def test_header_scanner(t : T?) {
    t |> run("a prototype is its name, result and unnamed parameters") @(t : T?) {
        let scan <- scan_text("char *strtok2(char *, const char *);\nint rand(void);\nint printf(const char *, ...);\n")
        t |> equal(join(scan.errors, "\n"), "")
        t |> equal(length(scan.prototypes), 3)
        t |> equal(scan.prototypes[0].name, "strtok2")
        t |> equal(scan.prototypes[0].result, "char *")
        t |> equal(join(scan.prototypes[0].params, "|"), "char *|const char *")
        t |> equal(length(scan.prototypes[1].params), 0)
        t |> equal(join(scan.prototypes[2].params, "|"), "const char *|...")
    }
    t |> run("objects, macros of both kinds, includes, typedefs and a record are read") @(t : T?) {
        let scan <- scan_text("/* c */\n" + guarded("#include <stddef.h>\n\n#define EOF (-1)\n#define va_end(ap) __builtin_va_end(ap)\ntypedef int sig_atomic_t;\ntypedef unsigned __INT64_TYPE__ u64;\ntypedef struct _IO_FILE FILE;\ntypedef struct tag buf[1];\ntypedef void (*handler)(int);\nextern FILE *stdin;\nstruct tm \{\n    int tm_sec;\n\};\n"))
        t |> equal(join(scan.errors, "\n"), "")
        t |> equal(join(scan.objects, " "), "stdin")
        t |> equal(join(scan.macros, " "), "EOF va_end")
        t |> equal(join(scan.guards, " "), "_T_H")
        t |> equal(join(scan.includes, " "), "stddef.h")
        t |> equal(length(scan.prototypes), 0)
        t |> equal(scan.typedefs?["sig_atomic_t"] ?? "", "int")
        t |> equal(scan.typedefs?["u64"] ?? "", "unsigned __INT64_TYPE__")
        t |> equal(scan.typedefs?["FILE"] ?? "", "struct _IO_FILE")
        t |> equal(scan.typedefs?["buf"] ?? "", UNBOUND)
        t |> equal(scan.typedefs?["handler"] ?? "", UNBOUND)
        t |> equal(length(scan.typedefs), 5)
    }
    t |> run("a line of no form is one error naming the header and the line") @(t : T?) {
        let malformed = fixed_array(
            "size_t strlen(const char *s);", "int f();", "int f(..., int);", "int f(...);", "int  f(void);",
            " int f(void);", "int f(void) ;", "int f(int (*)(int));",
            "int f(void);\t", "int f(void); ", "#pragma once", "#include_next <stdio.h>", "#include stdio.h", "#include <>", "#define", "#define 1X 2",
            "int 1f(void);", "int *(void);", "/* open", "/* a */ int x;", "// c", "struct tm;", "static int x;", "int x;", "\};", "#endif",
            "#else", "#define _T_H", "typedef int a_t;", "struct s \{")
        for (line in malformed) {
            let scan <- scan_text("int ok(void);\n{line}\n")
            t |> equal(length(scan.errors), 1, line)
            t |> success(length(scan.errors) == 1 && (scan.errors[0] |> starts_with("t.h:2: ")), line)
            t |> equal(length(scan.prototypes), 1, line)
        }
    }
}

[test(description = "the scanner reads a typedef as its declared type and a type through its typedefs")]
def test_header_types(t : T?) {
    t |> run("a prototype over a type that is none is one error at its line") @(t : T?) {
        for (line in fixed_array("int f(int x);", "int f(const int);", "int f(struct tm);", "wint_t f(void);", "int f(size_t);", "extern int f(void);")) {
            let scan <- scan_text("int ok(void);\n{line}\n")
            t |> equal(length(scan.errors), 1, line)
            t |> success(length(scan.errors) == 1 && scan.errors[0] |> starts_with("t.h:2: `f`: ") && scan.errors[0] |> ends_with(" is no type the headers declare"), line)
            t |> equal(length(scan.objects), 0, line)
        }
    }
    t |> run("a typedef is one declaration of a rigid form, declared once") @(t : T?) {
        let malformed = fixed_array(
            "typedef __SIZE_TYPE__ size_t; int unsupported(void);", "typedef int a_t, b_t;", "typedef int *p_t;", "typedef int;",
            "typedef a_t;", "typedef int a_t[2", "typedef 1 a_t[2];", "typedef struct \{\} (*f_t)(int);",
            "typedef int x_t; typedef void (*f_t)(int);", "typedef int (*f_t)(int)(int;", "typedef int ok_t;", "struct a b \{")
        for (line in malformed) {
            let scan <- scan_text(guarded("typedef int ok_t;\n{line}\n"))
            t |> equal(length(scan.errors), 1, line)
            t |> success(length(scan.errors) == 1 && scan.errors[0] |> starts_with("t.h:4: "), line)
            t |> equal(length(scan.typedefs), 1, line)
        }
    }
    t |> run("a prototype's typedef name stands for what a header declares it as, and for nothing when none does") @(t : T?) {
        let narrow <- scan_text(guarded("typedef int time_t;\ntypedef time_t stamp_t;\ntime_t time(stamp_t *);\n"))
        t |> equal(join(narrow.errors, "\n"), "")
        t |> equal(das_spelling(narrow.typedefs, "time_t"), "int")
        t |> equal(das_spelling(narrow.typedefs, "stamp_t *"), "int?")
        let undeclared <- scan_text("time_t time(time_t *);\n")
        t |> equal(length(undeclared.errors), 2)
        t |> success(!empty(undeclared.errors) && undeclared.errors[0] == "t.h:1: `time`: `time_t *` is no type the headers declare", join(undeclared.errors, "\n"))
        let cyclic <- scan_text(guarded("typedef b_t a_t;\ntypedef a_t b_t;\nint f(a_t);\n"))
        t |> equal(join(cyclic.errors, "\n"), "t.h:5: `f`: `a_t` is no type the headers declare")
    }
}

[test(description = "the scanner counts nothing a conditional can compile out, and holds the include guard to its form")]
def test_header_conditionals(t : T?) {
    t |> run("a declaration inside a conditional is an error, and is not counted") @(t : T?) {
        let hidden = fixed_array("void *malloc(int);", "extern int errno;", "typedef int size_t;", "struct s \{", "#include <stddef.h>", "#undef EOF", "#if 1")
        for (line in hidden) {
            let closing = line == "struct s \{" ? "\};\n" : line == "#if 1" ? "#else\n#endif\n" : ""
            let scan <- scan_text(guarded("#if 0\n{line}\n{closing}#else\n#endif\n"))
            t |> success(!empty(scan.errors) && scan.errors[0] |> starts_with("t.h:4: "), "{line}: {join(scan.errors, " | ")}")
            t |> equal(length(scan.prototypes) + length(scan.objects) + length(scan.typedefs) + length(scan.includes), 0, line)
        }
    }
    t |> run("a macro of a conditional counts when both arms define it, and a macro undefined later does not") @(t : T?) {
        let both <- scan_text("#ifdef NDEBUG\n#define assert(e) 0\n#define A 1\n#else\n#define A 2\n#define assert(e) 1\n#endif\n#define B 1\n#define C 1\n#undef B\n")
        t |> equal(join(both.errors, "\n"), "")
        t |> equal(join(both.macros, " "), "assert A C")
        t |> equal(join(both.defined, " "), "assert A A assert B C")
        for (line in fixed_array("#else B", "#else\n#else")) {
            let scan <- scan_text("#ifdef A\n#define X 1\n{line}\n#define X 1\n#endif\n")
            t |> equal(length(scan.errors), 1, "{line}: {join(scan.errors, " | ")}")
            t |> success(!empty(scan.errors) && find(scan.errors[0], ": an #else is the one of a conditional") > 0, line)
        }
        for (dead in fixed_array("#if 0\n#define EDOM 33\n#endif\n", "#if 0\n#define EDOM 33\n#else\n#endif\n", "#if 0\n#else\n#define EDOM 33\n#endif\n", "#if 0\n#define EDOM 33\n#else\n#define ERANGE 34\n#endif\n")) {
            let scan <- scan_text(dead)
            t |> equal(length(scan.errors), 1, dead)
            t |> equal(length(scan.macros), 0, dead)
        }
    }
    t |> run("the include guard is the header's own name, its #define next, its #endif last") @(t : T?) {
        t |> equal(guard_of("sys/stat.h"), "_SYS_STAT_H")
        let whole <- scan_text(guarded("typedef int a_t;\n"))
        t |> equal(join(whole.errors, "\n"), "")
        let broken = fixed_array(
            "#ifndef _T_H\n\n#define _T_H\ntypedef int a_t;\n#endif\n", "#ifndef _T_H\ntypedef int a_t;\n#endif\n",
            "#ifndef _OTHER_H\n#define _OTHER_H\ntypedef int a_t;\n#endif\n", "#ifndef _T_H\n#define _T_H\n#endif\ntypedef int a_t;\n",
            "#ifndef _T_H\n#define _T_H\ntypedef int a_t;\n", "#ifndef _T_H\n#define _T_H\n#define _T_H\n#endif\n",
            "#define X 1\n#ifndef _T_H\n#define _T_H\ntypedef int a_t;\n#endif\n", "#ifndef _T_H\n#define _T_H\n#else\n#endif\n")
        for (text in broken) {
            let scan <- scan_text(text)
            t |> success(!empty(scan.errors), text)
        }
    }
    t |> run("a record member is indented and plain, and a record left open is an error") @(t : T?) {
        for (member in fixed_array("int a;", "    int a", "    int (*f)(void);", "    struct \{", "    \} x;")) {
            let scan <- scan_text(guarded("struct s \{\n{member}\n\};\n"))
            t |> equal(length(scan.errors), 1, member)
        }
        let unclosed <- scan_text("#ifdef A\n#define X 1\n")
        t |> equal(join(unclosed.errors, "\n"), "t.h: a conditional is open at the end of the file")
        let open <- scan_text("#ifndef _T_H\n#define _T_H\nstruct s \{\n    int a;\n")
        t |> equal(join(open.errors, "\n"), "t.h: a record is open at the end of the file\nt.h: a conditional is open at the end of the file")
    }
    t |> run("a C type is spelled as crt binds it") @(t : T?) {
        let typedefs <- {"size_t" => "__SIZE_TYPE__", "time_t" => "__INT64_TYPE__", "FILE" => "struct _IO_FILE", "jmp_buf" => UNBOUND}
        let spelled = fixed_array(
            ("int", "int"), ("unsigned int", "uint"), ("long", "int64"), ("unsigned long long", "uint64"), ("size_t", "uint64"),
            ("time_t", "int64"), ("float", "float"), ("void", "void"), ("char *", "uint8?"), ("const char *", "uint8 const?"),
            ("char **", "uint8??"), ("int *", "int?"), ("const time_t *", "int64 const?"), ("void *", "void?"),
            ("const void *", "void?"), ("FILE *", "void?"), ("const struct tm *", "void?"), ("jmp_buf", "unbound"),
            ("signed char", "int8"), ("unsigned short", "uint16"), ("clock_t", ""), ("int x", ""),
            ("FILE", ""), ("struct tm", ""), ("const int", ""), ("char*", ""), ("char * *", ""), ("unsigned", ""), ("", ""), ("*", ""))
        for (pair in spelled) {
            t |> equal(das_spelling(typedefs, pair._0), pair._1, pair._0)
        }
    }
}

// the errors of the headers `a.h` and `t.h`, scanned in that order and judged together
def private errors_of(first, second : string) : string {
    var inscope scan : HeaderScan
    scan_header(scan, "a.h", first)
    scan_header(scan, "t.h", second)
    finish_scan(scan)
    return join(scan.errors, "\n")
}

// a guarded header `header` that declares two typedefs, a record, an object and two prototypes
def private declarations(header : string) : string =>
    "#ifndef {guard_of(header)}\n#define {guard_of(header)}\ntypedef __SIZE_TYPE__ size_t;\ntypedef int time_t;\nstruct tm \{\n    int tm_sec;\n\};\nextern int *stdin;\nvoid *malloc(size_t);\ntime_t time(const time_t *);\n#endif\n"

[test(description = "no macro rewrites a declaration, and no line hides one from C behind a comment, a literal or a splice")]
def test_header_macros(t : T?) {
    t |> run("a macro named as anything a header declares, or as a C keyword, is an error, before or after the declaration") @(t : T?) {
        t |> equal(errors_of("", declarations("t.h")), "")
        let names = fixed_array("time_t int", "size_t", "malloc(n) 0", "malloc free", "tm other", "tm_sec x", "__SIZE_TYPE__ int", "const", "unsigned signed", "void int", "extern", "typedef", "struct union", "stdin stdout", "stdin", "setjmp(env) other (env)", "__FAST16_TYPE char")
        for (name in names) {
            t |> equal(errors_of("#define {name}\n", declarations("t.h")) |> starts_with("a.h:1: `#define {name}`: "), true, name)
            t |> equal(find(errors_of("#define {name}\n", declarations("t.h")), "\n"), -1, name)
            t |> equal(errors_of(declarations("a.h"), "#define {name}\n") |> starts_with("t.h:1: `#define {name}`: "), true, name)
        }
    }
    t |> run("a mirror is its listed line, and a macro of a free name is no error") @(t : T?) {
        for (line in fixed_array("stdin stdin", "setjmp(env) _setjmp (env)", "__FAST16_TYPE long", "__FAST16_TYPE short", "EOF (-1)", "time_tt int", "PRId64 \"l\" \"d\"")) {
            t |> equal(errors_of(declarations("a.h"), "#define {line}\n"), "", line)
        }
    }
    t |> run("a line that could open a comment, a literal or a splice is one error, and hides nothing") @(t : T?) {
        let hiding = fixed_array(
            "#define HIDE /*", "#define END */", "#define A 1 // x", "#include <a//b.h>", "#if 0 /* x", "#undef A /* x", "int f(void); /* x",
            "int f(void); // x", "/*/", "/* a */ */", "#define S \"abc", "#define S \"a\" \"", "#include \"a.h\"", "extern char *s = \"a\";",
            "#define C 'a'", "#define C '", "int f(void);\\", "/* c */\\", "#define M(a) \\", "#define A 1 ??/", "#define A `", "#define A @", "#define A $")
        for (line in hiding) {
            var inscope scan <- scan_text("int ok(void);\n{line}\nint also(void);\n")
            t |> equal(length(scan.errors), 1, "{line}: {join(scan.errors, " | ")}")
            t |> success(length(scan.errors) == 1 && scan.errors[0] |> starts_with("t.h:2: "), line)
            t |> equal(length(scan.prototypes), 2, line)
        }
    }
}
