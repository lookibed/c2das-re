options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require daslib/json_boost
require ../suite_compare.das
require ../lua_compare.das
require _common

//! `compare/lua_compare.das` without the Rust binary: the known names read from stand-in Rust
//! sources, the gap over `nm` text and over two C files the test compiles, and the `lua` section
//! of a stand-in that refuses.

let LIBC_RS = "pub(crate) fn std_function(name: &str) -> Option<StdFunction> \{\n    match name \{\n        \"strlen\" | \"__builtin_strlen\" => Some(StdFunction::Strlen),\n        // a comment => \"not_a_name\"\n        \"fopen\" => Some(StdFunction::Fopen),\n        _ => None,\n    \}\n\}\n\nfn other() \{\n    \"after\" => 1,\n\}\n\npub(crate) fn std_stream(name: &str) -> Option<&'static str> \{\n    match name \{\n        \"stdout\" => Some(STDOUT),\n        _ => None,\n    \}\n\}\n\nimpl X \{\n    pub(crate) fn jmp_call(&self, func: CExprId) -> Option<JmpCall> \{\n        match self.name() \{\n            \"setjmp\" | \"_setjmp\" => Some(JmpCall::Setjmp),\n            _ => None,\n        \}\n    \}\n    fn later() \{\n        \"later\" => 2,\n    \}\n\}\n\npub(crate) fn libm_function(name: &str) -> Option<LibmFunction> \{\n    fn stem(name: &str) -> Option<(&'static str, usize)> \{\n        Some(match name \{\n            \"sqrt\" => (\"sqrt\", 1),\n            _ => return None,\n        \})\n    \}\n\}\n"

let RUNTIME_RS = "pub(crate) fn canonical_runtime_function(name: &str) -> Option<C> \{\n    match name \{\n        \"malloc\" | \"__builtin_malloc\" => Some(C::Malloc),\n    \}\n\}\n"

// the names of `names`, sorted, space-separated
def private sorted_names(names : table<string>) : string {
    var list <- [for (n in keys(names)); n]
    sort(list)
    return join(list, " ")
}

// a folder standing in for the translator's sources, passed to `body`
def private with_sources(t : T?; name : string; body : block<(dir : string) : void>) {
    var dir_error : string
    let dir = create_temp_directory(name, dir_error)
    if (!empty(dir_error)) {
        t |> failure("no scratch folder: {dir_error}")
        return
    }
    let translator = path_join(dir, "c2dascript-transpile/src/translator")
    mkdir_rec(translator)
    fwrite(path_join(translator, "libc.rs"), LIBC_RS)
    fwrite(path_join(translator, "runtime.rs"), RUNTIME_RS)
    invoke(body, dir)
    rmdir_rec(dir)
}

[test]
def test_known_names(t : T?) {
    t |> run("the literals left of each arrow of one function, nested functions inside it included") @(t : T?) {
        t |> equal(join(match_arm_names(LIBC_RS, "std_function"), " "), "strlen __builtin_strlen fopen")
        t |> equal(join(match_arm_names(LIBC_RS, "jmp_call"), " "), "setjmp _setjmp")
        t |> equal(join(match_arm_names(LIBC_RS, "libm_function"), " "), "sqrt")
        t |> equal(length(match_arm_names(LIBC_RS, "absent")), 0)
    }
    t |> run("every table's names, a math stem with its float form; a missing file is an error") @(t : T?) {
        t |> with_sources("cmp_lua_known") $(dir) {
            var error : string
            let known <- known_names(path_join(dir, "c2dascript-transpile/src/translator"), error)
            t |> equal(error, "")
            t |> equal(sorted_names(known), "__builtin_malloc __builtin_strlen _setjmp fopen malloc setjmp sqrt sqrtf stdout strlen")
            known_names(path_join(dir, "absent"), error)
            t |> success(error |> starts_with("no Rust source at"), error)
        }
    }
}

[test]
def test_gap(t : T?) {
    t |> run("nm's undefined and defined symbols, glibc's names mapped back, the known and own ones dropped") @(t : T?) {
        let text = "\na.o:\n                 U fopen64\n0000000000000000 T own\n                 U own\n                 U __isoc99_sscanf\n                 U ldexp\n                 w weak\n\nb.o:\n                 U ldexp\n                 U __sysv_signal\n"
        let undefined <- nm_symbols(text, true)
        let defined <- nm_symbols(text, false)
        t |> equal(sorted_names(undefined), "__isoc99_sscanf __sysv_signal fopen64 ldexp own")
        t |> equal(sorted_names(defined), "own weak")
        t |> equal(c_name_of("tmpfile64"), "tmpfile")
        t |> equal(c_name_of("strlen"), "strlen")
        let known <- {"fopen", "sscanf"}
        t |> equal(join(libc_gap(undefined, defined, known), " "), "ldexp signal")
    }
    t |> run("two C files compiled and listed; a file gcc refuses, and no Rust sources, are errors") @(t : T?) {
        t |> with_sources("cmp_lua_gap") $(dir) {
            let a = path_join(dir, "a.c")
            let b = path_join(dir, "b.c")
            fwrite(a, "#include <stdio.h>\n#include <math.h>\nint b_fn(void);\nint main(void) \{ FILE *f = fopen(\"x\", \"r\"); return b_fn() + (int) ldexp(1.0, 2) + (f != 0); \}\n")
            fwrite(b, "#include <string.h>\nint b_fn(void) \{ return (int) strlen(\"ab\"); \}\n")
            let translator = path_join(dir, "c2dascript-transpile/src/translator")
            var error : string
            t |> equal(join(program_gap([a, b], ["_FILE_OFFSET_BITS=64"], path_join(dir, "obj"), translator, error), " "), "ldexp")
            t |> equal(error, "")
            let bad = path_join(dir, "bad.c")
            fwrite(bad, "this is not C\n")
            t |> equal(length(program_gap([bad], array<string>(), path_join(dir, "obj"), translator, error)), 0)
            t |> success(error |> starts_with("gcc refused {bad}"), error)
            error = ""
            program_gap([a], array<string>(), path_join(dir, "obj"), path_join(dir, "absent"), error)
            t |> success(error |> starts_with("no Rust source at"), error)
        }
    }
}

[test]
def test_lua_section(t : T?) {
    t |> run("a refused translation: the error, the gap, our side in the ports, Doom pending") @(t : T?) {
        t |> with_sources("cmp_lua_section") $(dir) {
            let bin = path_join(dir, "rust")
            fwrite(bin, "#!/bin/sh\necho \"translation failed: unsupported external call: ldexp\" >&2\nexit 2\n")
            var out : string
            run_and_capture(["chmod", "+x", bin], out, 30.0)
            with_env(bin, dir) {
                t |> equal(lua_missing(), "")
                let section = lua_section(bin, Stamps(rust_commit = "abc", date = "today"))
                t |> equal(section?["status"] ?? "", "refused")
                t |> equal(section?["error"] ?? "", "translation failed: unsupported external call: ldexp")
                t |> equal(section?["units"] ?? 0, 33)
                t |> equal(section?["gap_error"] ?? "x", "")
                t |> equal(section?["ours"] ?? "", "see ports")
                t |> equal(section?["speed"] ?? "", "refused on the Rust side")
                let line = lua_line(section)
                t |> success(line |> starts_with("lua: refused translation failed:") && line |> contains(" ldexp ") && line |> contains("tmpnam"), line)
            }
            fwrite(bin, "#!/bin/sh\nprev=\"\"\nfor a in \"$@\"; do\n    if [ \"$prev\" = \"--output-dir\" ]; then out=\"$a\"; fi\n    prev=\"$a\"\ndone\nmkdir -p \"$out\"\nprintf '[export]\\ndef main() : int \{\\n    return 0\\n\}\\n' > \"$out/lua.das\"\n")
            with_env(bin, dir) {
                let section = lua_section(bin, Stamps(rust_commit = "abc", date = "today"))
                t |> equal(section?["status"] ?? "", "translated")
                t |> equal(section?["files"] ?? 0, 1)
                t |> equal(section?["speed"] ?? "", "not measured here")
            }
            with_env(path_join(dir, "absent"), dir) {
                t |> success(lua_missing() |> contains("no Rust translator at"))
            }
        }
        t |> equal(lua_line(JV(1)), "lua:  ; gap: ")
        let doom = doom_section()
        t |> equal(doom?["status"] ?? "", "pending")
        t |> equal(doom?["reason"] ?? "", "P6")
    }
}
