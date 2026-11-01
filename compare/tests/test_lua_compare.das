options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require daslib/json_boost
require ../suite_compare.das
require ../lua_compare.das
require ../../converter/tiers.das
require _common

//! `compare/lua_compare.das` without the Rust binary: the known names read from stand-in Rust
//! sources, the gap over `nm` text and over C files the test compiles, and the `lua` section over a
//! stand-in program, sidecar and translator the test writes; nothing reads the fetched Lua release.

let LIBC_RS = "pub(crate) fn std_function(name: &str) -> Option<StdFunction> \{\n    match name \{\n        \"strlen\" | \"__builtin_strlen\" => Some(StdFunction::Strlen),\n        let s = \"not_a_name\";\n        // a comment => \"not_a_name\"\n        \"fopen\" => Some(StdFunction::Fopen),\n        _ => None,\n    \}\n\}\n\nfn other() \{\n    \"after\" => 1,\n\}\n\npub(crate) fn std_stream(name: &str) -> Option<&'static str> \{\n    match name \{\n        \"stdout\" => Some(STDOUT),\n        _ => None,\n    \}\n\}\n\nimpl X \{\n    pub(crate) fn jmp_call(&self, func: CExprId) -> Option<JmpCall> \{\n        match self.name() \{\n            \"setjmp\" | \"_setjmp\" => Some(JmpCall::Setjmp),\n            _ => None,\n        \}\n    \}\n    fn later() \{\n        \"later\" => 2,\n    \}\n\}\n\npub(crate) fn libm_function(name: &str) -> Option<LibmFunction> \{\n    fn stem(name: &str) -> Option<(&'static str, usize)> \{\n        Some(match name \{\n            \"sqrt\" => (\"sqrt\", 1),\n            _ => return None,\n        \})\n    \}\n\}\n"

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
        var error : string
        t |> equal(join(match_arm_names(LIBC_RS, "std_function", error), " "), "strlen __builtin_strlen fopen")
        t |> equal(join(match_arm_names(LIBC_RS, "jmp_call", error), " "), "setjmp _setjmp")
        t |> equal(join(match_arm_names(LIBC_RS, "libm_function", error), " "), "sqrt")
        t |> equal(error, "")
        t |> equal(join(match_arm_names("fn f(x: &str) \{  \n    \"a\" => 1,\n\}   \n\"after\" => 2,\n", "f", error), " "), "a")
        t |> equal(error, "")
    }
    t |> run("an absent table, one never closed and one naming nothing are errors") @(t : T?) {
        var error : string
        t |> equal(length(match_arm_names(LIBC_RS, "absent", error)), 0)
        t |> equal(error, "no fn absent( in the source")
        error = ""
        match_arm_names("fn open() \{\n    \"a\" => 1,\n", "open", error)
        t |> equal(error, "fn open has no closing brace")
        error = ""
        match_arm_names("fn bare() \{\n    _ => None,\n\}\n", "bare", error)
        t |> equal(error, "fn bare names nothing")
    }
    t |> run("every table's names, a math stem with its float form; a missing file is an error") @(t : T?) {
        t |> with_sources("cmp_lua_known") $(dir) {
            var error : string
            let known <- known_names(path_join(dir, "c2dascript-transpile/src/translator"), error)
            t |> equal(error, "")
            t |> equal(sorted_names(known), "__builtin_malloc __builtin_strlen _setjmp fopen malloc setjmp sqrt sqrtf stdout strlen")
            known_names(path_join(dir, "absent"), error)
            t |> success(error |> starts_with("no Rust source at"), error)
            error = ""
            fwrite(path_join(dir, "c2dascript-transpile/src/translator/runtime.rs"), "fn other() \{\n\}\n")
            known_names(path_join(dir, "c2dascript-transpile/src/translator"), error)
            t |> success(error |> ends_with("runtime.rs: no fn canonical_runtime_function( in the source"), error)
        }
    }
}

[test]
def test_gap(t : T?) {
    t |> run("nm's undefined and defined symbols, glibc's names mapped back, the known and own ones dropped") @(t : T?) {
        let text = "\na.o:\n                 U fopen64\n0000000000000000 T own\n                 U own\n                 U __isoc99_sscanf\n                 U ldexp\n                 w weak\n                 v weak_object\nnm: c.o: no symbols\n\nb.o:\n                 U ldexp\n                 U __sysv_signal\n"
        let undefined <- nm_symbols(text, true)
        let defined <- nm_symbols(text, false)
        t |> equal(sorted_names(undefined), "__isoc99_sscanf __sysv_signal fopen64 ldexp own weak weak_object")
        t |> equal(sorted_names(defined), "own")
        t |> success(!key_exists(defined, "symbols") && !key_exists(undefined, "symbols"))
        t |> equal(c_name_of("tmpfile64"), "tmpfile")
        t |> equal(c_name_of("strlen"), "strlen")
        let known <- {"fopen", "sscanf"}
        t |> equal(join(libc_gap(undefined, defined, known), " "), "ldexp signal weak weak_object")
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
            t |> equal(length(program_gap([a], array<string>(), path_join(dir, "obj"), path_join(dir, "absent"), error)), 0)
            t |> success(error |> starts_with("no Rust source at"), error)
            let fake_bin = path_join(dir, "fake_bin")
            mkdir_rec(fake_bin)
            fwrite(path_join(fake_bin, "nm"), "#!/bin/sh\nexit 1\n")
            var out : string
            run_and_capture(["chmod", "+x", path_join(fake_bin, "nm")], out, 30.0)
            let saved_path = get_env_variable("PATH")
            set_env_variable("PATH", "{fake_bin}:{saved_path}")
            error = ""
            let none <- program_gap([a, b], array<string>(), path_join(dir, "obj"), translator, error)
            set_env_variable("PATH", saved_path)
            t |> equal(length(none), 0)
            t |> success(error |> starts_with("nm failed over "), error)
            fwrite(path_join(fake_bin, "nm"), "#!/bin/sh\nif [ \"$1\" = \"--defined-only\" ]; then exit 1; fi\nexec /usr/bin/nm \"$@\"\n")
            set_env_variable("PATH", "{fake_bin}:{saved_path}")
            error = ""
            let none_defined <- program_gap([a, b], array<string>(), path_join(dir, "obj"), translator, error)
            set_env_variable("PATH", saved_path)
            t |> equal(length(none_defined), 0)
            t |> success(error |> starts_with("nm failed over "), error)
            let gated = path_join(dir, "gated.c")
            fwrite(gated, "#include <math.h>\nint gated(void) \{\n#ifdef GAP_ON\n    return (int) ldexp(1.0, 2);\n#else\n    return 0;\n#endif\n\}\n")
            error = ""
            t |> equal(join(program_gap([gated], ["GAP_ON"], path_join(dir, "obj"), translator, error), " "), "ldexp")
            t |> equal(length(program_gap([gated], array<string>(), path_join(dir, "obj"), translator, error)), 0)
            t |> equal(error, "")
        }
    }
}

// a stand-in program in `dir/prog`: `lua.c` calls `ldexp`, which no table knows, `strlen`, which the
// stand-in sources know, and `helper`, which `helper.c` defines
def private stand_in_program(dir : string) : array<string> {
    let main_c = path_join(dir, "prog/lua.c")
    let helper_c = path_join(dir, "prog/helper.c")
    mkdir_rec(path_join(dir, "prog"))
    fwrite(main_c, "#include <math.h>\n#include <string.h>\nint helper(void);\nint main(void) \{ return helper() + (int) ldexp(1.0, 2) + (int) strlen(\"ab\"); \}\n")
    fwrite(helper_c, "int helper(void) \{ return HELPER_VALUE; \}\n")
    return <- [main_c, helper_c]
}

[test]
def test_lua_section(t : T?) {
    t |> run("a refused translation of a stand-in program: the error, its gap, the sidecar's define") @(t : T?) {
        t |> with_sources("cmp_lua_section") $(dir) {
            let bin = path_join(dir, "rust")
            fwrite(bin, "#!/bin/sh\necho \"translation failed: unsupported external call: ldexp\" >&2\nexit 2\n")
            var out : string
            run_and_capture(["chmod", "+x", bin], out, 30.0)
            let sidecar = path_join(dir, "prog.c2das")
            fwrite(sidecar, "\{\"defines\": [\"HELPER_VALUE=3\"]\}\n")
            let c_paths <- stand_in_program(dir)
            let work = path_join(dir, "work")
            with_env(bin, dir) {
                var error : string
                let section = lua_section(bin, c_paths, sidecar, work, Stamps(rust_commit = "", rust_commit_error = "no checkout", date = "today"), error)
                t |> equal(error, "")
                t |> equal(section?["status"] ?? "", "refused")
                t |> equal(section?["error"] ?? "", "translation failed: unsupported external call: ldexp")
                t |> equal(section?["units"] ?? 0, 2)
                t |> equal(section?["rust_commit_error"] ?? "", "no checkout")
                t |> equal(section?["gap_error"] ?? "x", "")
                t |> equal(lua_line(section), "lua: refused translation failed: unsupported external call: ldexp; gap: ldexp")
                t |> equal(section?["ours"] ?? "", "see ports")
                t |> equal(section?["speed"] ?? "", "refused on the Rust side")
                t |> success((section?["gap_method"] ?? "") |> contains("gcc -c -O0 -fno-builtin -fno-stack-protector"))
                t |> success(fread(path_join(work, "compile_commands.json")) |> contains("-DHELPER_VALUE=3"))
            }
        }
    }
    t |> run("a translated stand-in program; an unreadable sidecar records nothing") @(t : T?) {
        t |> with_sources("cmp_lua_section_ok") $(dir) {
            let bin = path_join(dir, "rust")
            fwrite(bin, "#!/bin/sh\nprev=\"\"\nfor a in \"$@\"; do\n    if [ \"$prev\" = \"--output-dir\" ]; then out=\"$a\"; fi\n    prev=\"$a\"\ndone\nmkdir -p \"$out\"\nprintf '[export]\\ndef main() : int \{\\n    return 0\\n\}\\n' > \"$out/main.das\"\n")
            var out : string
            run_and_capture(["chmod", "+x", bin], out, 30.0)
            let sidecar = path_join(dir, "prog.c2das")
            fwrite(sidecar, "\{\"defines\": [\"HELPER_VALUE=3\"]\}\n")
            let c_paths <- stand_in_program(dir)
            with_env(bin, dir) {
                var error : string
                let section = lua_section(bin, c_paths, sidecar, path_join(dir, "work"), Stamps(rust_commit = "abc", date = "today"), error)
                t |> equal(section?["status"] ?? "", "translated")
                t |> equal(section?["files"] ?? 0, 1)
                t |> equal(section?["speed"] ?? "", "not measured here")
                let missing = path_join(dir, "absent.c2das")
                t |> success(lua_section(bin, c_paths, missing, path_join(dir, "work2"), Stamps(), error) == null)
                t |> success(error |> starts_with("cannot read the sidecar {missing}"), error)
                t |> success(!fexist(path_join(dir, "work2")))
            }
        }
    }
    t |> run("the inputs a run needs; the log line of a section without a gap; Doom pending") @(t : T?) {
        t |> with_sources("cmp_lua_missing") $(dir) {
            let release = path_join(dir, "release")
            mkdir_rec(release)
            with_env(path_join(dir, "rust"), dir) {
                t |> success(lua_missing(release) |> contains("no Rust translator at"))
            }
            with_env(dir, dir) {
                t |> success(lua_missing(release) |> contains("is a folder"))
            }
            let bin = path_join(dir, "rust")
            fwrite(bin, "#!/bin/sh\nexit 0\n")
            with_env(bin, dir) {
                t |> equal(lua_missing(release), "{release} is missing: run lua/fetch.sh")
                fwrite(path_join(release, "lua.c"), "int main(void) \{ return 0; \}\n")
                t |> equal(lua_missing(release), "")
            }
        }
        t |> equal(lua_line(JV(1)), "lua:  ; gap: ")
        let doom = doom_section()
        t |> equal(doom?["status"] ?? "", "pending")
        t |> equal(doom?["reason"] ?? "", "P6")
    }
}

// `compare/run.das` run from the repository root with `args` after `--`; its exit code
def private run_compare(args : array<string>; var out : string&) : int {
    var argv <- daslang_cmd(CONVERTED_MODULES)
    argv |> push_from(["compare/run.das", "--"], args)
    return run_and_capture(argv, out, 300.0)
}

[test]
def test_lua_run(t : T?) {
    t |> run("--lua over a stand-in program to its end: both sections written, the rest kept") @(t : T?) {
        t |> with_sources("cmp_lua_run") $(dir) {
            let bin = path_join(dir, "rust")
            fwrite(bin, "#!/bin/sh\necho \"translation failed: unsupported external call: ldexp\" >&2\nexit 2\n")
            var out : string
            run_and_capture(["chmod", "+x", bin], out, 30.0)
            stand_in_program(dir)
            let results = path_join(dir, "results.json")
            fwrite(results, "\{\"perf\": \{\"samples\": 5\}\}")
            let committed = fread(CAPTURE)
            with_env(bin, dir) {
                t |> equal(run_compare(["--lua", "--lua-from", path_join(dir, "prog"), "--out", results], out), 0, out)
            }
            var read_error : string
            let js = read_json(fread(results), read_error)
            t |> equal(read_error, "")
            t |> equal(js?["lua"]?["status"] ?? "", "refused")
            t |> equal(js?["lua"]?["units"] ?? 0, 2)
            t |> equal(js?["doom"]?["status"] ?? "", "pending")
            t |> equal(js?["perf"]?["samples"] ?? 0, 5)
            t |> equal(fread(CAPTURE), committed)
            t |> success(fexist(path_join(dir, "prog/work/compile_commands.json")))
        }
    }
}

[test]
def test_lua_command_line(t : T?) {
    t |> run("--lua runs alone; without the Rust translator it exits 2") @(t : T?) {
        var out : string
        t |> equal(run_compare(["--lua", "--suites"], out), 1, out)
        t |> success(out |> contains("--lua runs alone"), out)
        t |> equal(run_compare(["--perf", "--lua"], out), 1, out)
        t |> success(out |> contains("--perf runs alone"), out)
        t |> equal(run_compare(["--lua", "--filter", "lvm"], out), 1, out)
        t |> success(out |> contains("--lua takes no --filter"), out)
        with_env("/nonexistent/c2das-rust", "") {
            t |> equal(run_compare(["--lua"], out), 2, out)
            t |> success(out |> contains("no Rust translator at /nonexistent/c2das-rust"), out)
        }
    }
}
