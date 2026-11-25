options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require daslib/rtti
require _header_scan
require ../../../converter/emit.das

//! The own libc headers against what a converted program can call
//! (`frontend/include/ARCHITECTURE.md` section 2): the prototypes are the C names `crt` binds and
//! the libc names the emitter lowers, the `extern` objects the emitter's libc objects, and every
//! `crt` constant a macro. The `crt` side is read from the loaded module, the headers as text.

let private INCLUDE_DIR = "frontend/include"

// glibc's other spellings of `setjmp` and `longjmp`, which the emitter maps and no header declares
let private GLIBC_ALIASES <- ["_longjmp", "_setjmp", "__sigsetjmp"]

// the crt functions the printf lowering writes through, named after the C function they forward to
let private STDOUT_HELPERS <- ["fwrite_stdout", "fflush_stdout"]

// the c_runtime pieces whose functions crt serves one directive at a time, as `<function>_<kind>`
let private DIRECTIVE_PIECES <- {"c_runtime/printf", "c_runtime/scanf"}

// the crt constant that is no C name: the width of the host's `long`
let private HOST_ONLY_CONSTANT = "LONG_BITS"

//! The macros the headers read that the compiler predefines (`ARCHITECTURE.md`, the predefined
//! names): the list a compiler run without its own predefined macros has to be given.
let PREDEFINED <- [
    "__CHAR_BIT__", "__DBL_DIG__", "__DBL_EPSILON__", "__DBL_MANT_DIG__", "__DBL_MAX_10_EXP__", "__DBL_MAX_EXP__",
    "__DBL_MAX__", "__DBL_MIN_10_EXP__", "__DBL_MIN_EXP__", "__DBL_MIN__", "__FLT_DIG__", "__FLT_EPSILON__",
    "__FLT_MANT_DIG__", "__FLT_MAX_10_EXP__", "__FLT_MAX_EXP__", "__FLT_MAX__", "__FLT_MIN_10_EXP__", "__FLT_MIN_EXP__",
    "__FLT_MIN__", "__FLT_RADIX__", "__INT64_TYPE__", "__INT_MAX__", "__LONG_LONG_MAX__", "__LONG_MAX__",
    "__PTRDIFF_TYPE__", "__SCHAR_MAX__", "__SHRT_MAX__", "__SIZE_TYPE__", "__WCHAR_TYPE__"]

// the language's own names of that shape, which `<assert.h>` reads
let private LANGUAGE_NAMES <- {"__FILE__", "__LINE__"}

def private header_names(folder, prefix : string; var names : array<string>) {
    var inscope entries : array<string>
    dir(folder) $(entry) {
        entries |> push(clone_string(entry))
    }
    sort(entries)
    for (entry in entries) {
        if (entry |> ends_with(".h")) {
            names |> push(prefix + entry)
        } elif (entry != "." && entry != ".." && entry != "tests" && stat(path_join(folder, entry)).is_dir) {
            header_names(path_join(folder, entry), "{prefix}{entry}/", names)
        }
    }
}

def private scan_headers : HeaderScan {
    var scan : HeaderScan
    var inscope names : array<string>
    header_names(INCLUDE_DIR, "", names)
    for (name in names) {
        scan_header(scan, name, fread(path_join(INCLUDE_DIR, name)))
    }
    return <- scan
}

// every character of a header that is no part of an identifier
let private PUNCTUATION = " \n\t!\"#%&'()*+,-./:;<=>?[\\]^\{|\}~"

// the names of the predefined shape in `text`: two underscores, capitals, digits and underscores,
// two underscores, a whole identifier
def private predefined_shaped(text : string; var names : table<string>) {
    var inscope words <- split_by_chars(text, PUNCTUATION)
    for (word in words) {
        if (length(word) > 4 && word |> starts_with("__") && word |> ends_with("__") && word == to_upper(word)) {
            names |> insert(word)
        }
    }
}

def private scan_text(text : string) : HeaderScan {
    var scan : HeaderScan
    scan_header(scan, "t.h", text)
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

def private header_signature(proto : Prototype) : string =>
    "{das_spelling(proto.result)}({join([for (param in proto.params); das_spelling(param)], ", ")})"

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
        t |> success(!empty(scan.prototypes), "no header under {INCLUDE_DIR}: the test runs from the repository root")
    }
    t |> run("an #include names a header of the set") @(t : T?) {
        let scan <- scan_headers()
        for (name in scan.includes) {
            t |> success(fexist(path_join(INCLUDE_DIR, name)), "<{name}> is no header of the set")
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
                t |> equal(header_signature(proto), signatures?[proto.name] ?? "", "{proto.header}: `{proto.name}`")
            }
        }
    }
    t |> run("the predefined macros the headers read are the listed ones") @(t : T?) {
        var read : table<string>
        var names : array<string>
        header_names(INCLUDE_DIR, "", names)
        for (name in names) {
            predefined_shaped(fread(path_join(INCLUDE_DIR, name)), read)
        }
        for (name in keys(LANGUAGE_NAMES)) {
            read |> erase(name)
        }
        var found <- [for (name in keys(read)); name]
        sort(found)
        t |> equal(join(found, " "), join(PREDEFINED, " "))
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
    t |> run("objects, macros of both kinds, includes and a record are read") @(t : T?) {
        let scan <- scan_text("/* c */\n#ifndef G\n#define G\n#include <stddef.h>\n\n#define EOF (-1)\n#define va_end(ap) __builtin_va_end(ap)\ntypedef int sig_atomic_t;\nextern FILE *stdin;\nstruct tm \{\n    int tm_sec;\n\};\n#endif\n")
        t |> equal(join(scan.errors, "\n"), "")
        t |> equal(join(scan.objects, " "), "stdin")
        t |> equal(join(scan.macros, " "), "G EOF va_end")
        t |> equal(join(scan.includes, " "), "stddef.h")
        t |> equal(length(scan.prototypes), 0)
    }
    t |> run("a line of no form is one error naming the header and the line") @(t : T?) {
        let malformed = fixed_array(
            "size_t strlen(const char *s);", "int f(int x);", "int f();", "int f(..., int);", "int f(...);", "int  f(void);",
            " int f(void);", "int f(void) ;", "int f(int (*)(int));", "int f(const int);", "int f(struct tm);", "wint_t f(void);",
            "int f(void);\t", "int f(void); ", "#pragma once", "#include_next <stdio.h>", "#include \"stdio.h\"", "#define",
            "#define M(a) \\", "/* open", "/* a */ int x;", "// c", "struct tm;", "static int x;", "int x;", "\};")
        for (line in malformed) {
            let scan <- scan_text("int ok(void);\n{line}\n")
            t |> equal(length(scan.errors), 1, line)
            t |> success(length(scan.errors) == 1 && scan.errors[0] |> starts_with("t.h:2: "), line)
            t |> equal(length(scan.prototypes), 1, line)
        }
    }
    t |> run("a record member is indented and plain, and a record left open is an error") @(t : T?) {
        for (member in fixed_array("int a;", "    int a", "    int (*f)(void);", "    struct \{")) {
            let scan <- scan_text("struct s \{\n{member}\n\};\n")
            t |> equal(length(scan.errors), 1, member)
        }
        let open <- scan_text("struct s \{\n    int a;\n")
        t |> equal(join(open.errors, "\n"), "t.h: a record is open at the end of the file")
    }
    t |> run("a C type is spelled as crt binds it") @(t : T?) {
        let spelled = fixed_array(
            ("int", "int"), ("unsigned int", "uint"), ("long", "int64"), ("unsigned long long", "uint64"), ("size_t", "uint64"),
            ("time_t", "int64"), ("float", "float"), ("void", "void"), ("char *", "uint8?"), ("const char *", "uint8 const?"),
            ("char **", "uint8??"), ("int *", "int?"), ("const time_t *", "int64 const?"), ("void *", "void?"),
            ("const void *", "void?"), ("FILE *", "void?"), ("const struct tm *", "void?"), ("jmp_buf", "unbound"),
            ("FILE", ""), ("struct tm", ""), ("const int", ""), ("char*", ""), ("char * *", ""), ("unsigned", ""), ("", ""), ("*", ""))
        for (pair in spelled) {
            t |> equal(das_spelling(pair._0), pair._1, pair._0)
        }
    }
}
