options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require daslib/json_boost
require ../rust_translator.das
require _common

//! `compare/rust_translator.das` over a stand-in translator: a shell script that records its
//! argv, prints the real banner, and writes, refuses, stays silent or sleeps by the name of its
//! input. The real Rust binary never runs here.

// the stand-in: it prints a progress line first on stdout as the translator does, then
// `refused.c` fails with a clang warning and the diagnostic, `silent.c` exits 3 saying nothing more, `usage.c` fails
// with a line that is no `translation failed:`, `twomain.c` writes two modules defining `main`,
// `slow.c` sleeps, `nomain.c` writes a module without `main`, a `.json` database writes the source
// layout's entry cluster, its fragment, the runtime module and a log, any other file its module and a
// helper module defining only `main_0`
let STAND_IN = "#!/bin/sh\nprintf '%s\\n' \"$@\" > \"$(dirname \"$0\")/argv.txt\"\necho \"c2dascript-transpile v0.1.0\" >&2\nout=\"\"\nprev=\"\"\nfor a in \"$@\"; do\n    if [ \"$prev\" = \"--output-dir\" ]; then out=\"$a\"; fi\n    prev=\"$a\"\ndone\nstem=$(basename \"$2\" .c)\necho \"Transpiling $stem\"\ncase \"$*\" in\n    *refused.c*) echo \"refused.c:1:1: warning: a clang warning\" >&2; echo \"translation failed: unsupported construct at refused.c:3\" >&2; exit 2 ;;\n    *silent.c*) exit 3 ;;\n    *usage.c*) echo \"--libc requires a value\" >&2; exit 1 ;;\n    *twomain.c*) mkdir -p \"$out\"; for m in one two; do printf '[export]\\ndef main() : int \{\\n    return 0\\n\}\\n' > \"$out/$m.das\"; done; exit 0 ;;\n    *slow.c*) exec sleep 10 ;;\n    *nomain.c*) mkdir -p \"$out\"; echo 'def helper() : int \{ return 0; \}' > \"$out/nomain.das\"; exit 0 ;;\n    *.json*) mkdir -p \"$out\"; echo 'include prog.das.inc' > \"$out/prog.das\"; printf '[export]\\ndef main() : int \{\\n    return 0\\n\}\\n' > \"$out/prog.das.inc\"; echo 'def c2da_rt() : int \{ return 0; \}' > \"$out/c2da_runtime.das\"; echo log > \"$out/translate.log\"; exit 0 ;;\nesac\nmkdir -p \"$out\"\nprintf '[export]\\ndef main() : int \{\\n    return main_0()\\n\}\\n' > \"$out/$stem.das\"\nprintf 'def main_0() : int \{\\n    return 0\\n\}\\n' > \"$out/aaa_helper.das\"\n"

// a das program standing in for a translation's entry: its command line after the script, one
// argument a line, and exit 3
let ENTRY_DAS = "options gen2\nrequire strings\n[export]\ndef main() : int \{\n    let argv <- get_command_line_arguments()\n    var seen = false\n    for (a in argv) \{\n        if (seen) \{\n            print(\"arg \{a\}\\n\")\n        \}\n        seen = seen || a |> ends_with(\".das\")\n    \}\n    return 3\n\}\n"

let NO_ARGS : array<string>

// a scratch folder holding the executable stand-in `rust`, passed to `body` with the stand-in's
// path and removed after it; a failure when no folder can be made
def private with_stand_in(t : T?; name : string; body : block<(dir, bin : string) : void>) {
    var dir_error : string
    let dir = create_temp_directory(name, dir_error)
    if (!empty(dir_error)) {
        t |> failure("no scratch folder: {dir_error}")
        return
    }
    let bin = path_join(dir, "rust")
    fwrite(bin, STAND_IN)
    var out : string
    run_and_capture(["chmod", "+x", bin], out, 30.0)
    invoke(body, dir, bin)
    rmdir_rec(dir)
}

// the argv the stand-in last recorded, one argument an element
def private recorded_argv(dir : string) : array<string> => <- [for (ln in split(fread(path_join(dir, "argv.txt")), "\n")); ln; where !empty(ln)]

def private git(dir : string; argv : array<string>) {
    var full <- ["git", "-C", dir, "-c", "user.name=test", "-c", "user.email=test@example.invalid"]
    full |> push_from(argv)
    var out : string
    run_and_capture(full, out, 60.0)
}

[test]
def test_binary_lookup(t : T?) {
    t |> run("$C2DAS_RUST_BIN wins, then $C2DAS_RUST's release build, then /root/c2das's") @(t : T?) {
        with_env("/opt/rust/bin/c2das", "/opt/checkout") {
            t |> equal(rust_binary(), "/opt/rust/bin/c2das")
            t |> equal(rust_checkout(), "/opt/checkout")
        }
        with_env("", "/opt/checkout") {
            t |> equal(rust_binary(), "/opt/checkout/target/release/c2dascript-transpile")
        }
        with_env("", "") {
            t |> equal(rust_binary(), "/root/c2das/target/release/c2dascript-transpile")
            t |> equal(rust_checkout(), "/root/c2das")
        }
    }
}

[test]
def test_rust_available(t : T?) {
    t |> run("a missing binary, a folder in its place, and a file") @(t : T?) {
        t |> with_stand_in("c2das_available") $(dir, bin) {
            var reason : string
            with_env(path_join(dir, "absent"), "") {
                t |> success(!rust_available(reason))
                t |> success(reason |> contains("run scripts/build_c2das_rust.sh"), reason)
            }
            with_env(dir, "") {
                t |> success(!rust_available(reason))
                t |> success(reason |> contains("is a folder"), reason)
            }
            with_env(bin, "") {
                t |> success(rust_available(reason), reason)
                t |> equal(reason, "")
            }
        }
    }
}

[test]
def test_rust_version(t : T?) {
    t |> run("the HEAD of a c2das checkout, a checkout of something else, and no checkout") @(t : T?) {
        t |> with_stand_in("c2das_version") $(dir, bin) {
            var reason : string
            t |> equal(rust_version(bin, reason), "")
            t |> success(reason |> contains("is in no git checkout"), reason)
            git(dir, ["init", "-q"])
            git(dir, ["add", "rust"])
            git(dir, ["commit", "-q", "-m", "other"])
            t |> equal(rust_version(bin, reason), "")
            t |> success(reason |> contains("is not a lookibed/c2das checkout"), reason)
            mkdir_rec(path_join(dir, "c2dascript-transpile"))
            fwrite(path_join(dir, "c2dascript-transpile/Cargo.toml"), "[package]\n")
            git(dir, ["add", "c2dascript-transpile"])
            git(dir, ["commit", "-q", "-m", "c2das"])
            mkdir_rec(path_join(dir, "target/release"))
            let release_bin = path_join(dir, "target/release/c2dascript-transpile")
            fwrite(release_bin, "")
            var head : string
            run_and_capture(["git", "-C", dir, "rev-parse", "HEAD"], head, 60.0)
            t |> equal(rust_version(release_bin, reason), strip(head))
            t |> equal(reason, "")
        }
    }
}

[test]
def test_translate_file(t : T?) {
    t |> run("a translated file: the argv, the files and the module defining main") @(t : T?) {
        t |> with_stand_in("c2das_translate") $(dir, bin) {
            let out = path_join(dir, "ok")
            let res = translate_file(bin, "/src/prog.c", out, ["--no-inline"], ["-DX=1", "-I/inc"], 60.0)
            t |> success(res.ok, res.error)
            t |> equal(res.exit_code, 0)
            t |> equal(res.error, "")
            t |> equal(res.out_dir, out)
            t |> equal(join(recorded_argv(dir), " "), "--file /src/prog.c --libc std --strict --output-dir {out} --no-inline -DX=1 -I/inc")
            t |> equal(join(res.files, " "), "{out}/aaa_helper.das {out}/prog.das")
            t |> equal(res.entry, path_join(out, "prog.das"))
            t |> success(res.seconds >= 0.0)
        }
    }
    t |> run("a refused file: the diagnostic line after the banner") @(t : T?) {
        t |> with_stand_in("c2das_refused") $(dir, bin) {
            let res = translate_file(bin, "/src/refused.c", path_join(dir, "refused"), NO_ARGS, NO_ARGS, 60.0)
            t |> success(!res.ok)
            t |> equal(res.exit_code, 2)
            t |> equal(res.error, "translation failed: unsupported construct at refused.c:3")
            t |> equal(length(res.files), 0)
            t |> equal(res.entry, "")
        }
    }
    t |> run("a failure with no diagnostic names the exit code") @(t : T?) {
        t |> with_stand_in("c2das_silent") $(dir, bin) {
            let res = translate_file(bin, "/src/silent.c", path_join(dir, "silent"), NO_ARGS, NO_ARGS, 60.0)
            t |> success(!res.ok)
            t |> equal(res.error, "exit 3")
        }
    }
    t |> run("a translator past the timeout") @(t : T?) {
        t |> with_stand_in("c2das_slow") $(dir, bin) {
            let res = translate_file(bin, "/src/slow.c", path_join(dir, "slow"), NO_ARGS, NO_ARGS, 0.3)
            t |> success(!res.ok)
            t |> equal(res.exit_code, popen_timed_out)
            t |> success(res.error |> starts_with("timed out after"), res.error)
        }
    }
    t |> run("a translation without main has no entry") @(t : T?) {
        t |> with_stand_in("c2das_nomain") $(dir, bin) {
            let res = translate_file(bin, "/src/nomain.c", path_join(dir, "nomain"), NO_ARGS, NO_ARGS, 60.0)
            t |> success(res.ok, res.error)
            t |> equal(length(res.files), 1)
            t |> equal(res.entry, "")
        }
    }
}

[test]
def test_translate_file_edges(t : T?) {
    t |> run("a failure without a `translation failed:` line reports its first other line") @(t : T?) {
        t |> with_stand_in("c2das_usage") $(dir, bin) {
            let res = translate_file(bin, "/src/usage.c", path_join(dir, "usage"), NO_ARGS, NO_ARGS, 60.0)
            t |> equal(res.exit_code, 1)
            t |> equal(res.error, "--libc requires a value")
        }
    }
    t |> run("an output folder that is not empty is refused before the translator runs") @(t : T?) {
        t |> with_stand_in("c2das_reuse") $(dir, bin) {
            let out = path_join(dir, "reused")
            let first = translate_file(bin, "/src/prog.c", out, NO_ARGS, NO_ARGS, 60.0)
            t |> success(first.ok, first.error)
            remove(path_join(dir, "argv.txt"))
            let again = translate_file(bin, "/src/nomain.c", out, NO_ARGS, NO_ARGS, 60.0)
            t |> success(!again.ok)
            t |> equal(again.exit_code, -1)
            t |> equal(again.error, "the output folder {out} is not empty: translate into a fresh folder")
            t |> equal(again.entry, "")
            t |> success(!fexist(path_join(dir, "argv.txt")), "the translator ran")
            t |> success(fexist(path_join(out, "prog.das")), "the folder was touched")
        }
    }
    t |> run("the entry keeps every dot of the file name but the extension") @(t : T?) {
        t |> with_stand_in("c2das_dotted") $(dir, bin) {
            let out = path_join(dir, "dotted")
            let res = translate_file(bin, "/src/a.b.c", out, NO_ARGS, NO_ARGS, 60.0)
            t |> success(res.ok, res.error)
            t |> equal(res.entry, path_join(out, "a.b.das"))
        }
    }
    t |> run("two modules defining main fail the translation") @(t : T?) {
        t |> with_stand_in("c2das_twomain") $(dir, bin) {
            let out = path_join(dir, "twomain")
            let res = translate_file(bin, "/src/twomain.c", out, NO_ARGS, NO_ARGS, 60.0)
            t |> success(!res.ok)
            t |> equal(res.exit_code, 0)
            t |> equal(res.error, "more than one module defines main: {out}/one.das, {out}/two.das")
            t |> equal(res.entry, "")
        }
    }
}

[test]
def test_translate_db(t : T?) {
    t |> run("the database argv, and the cluster named after the fragment defining main") @(t : T?) {
        t |> with_stand_in("c2das_db") $(dir, bin) {
            let out = path_join(dir, "db")
            let res = translate_db(bin, "/src/compile_commands.json", out, "c2da_runtime", ["--no-inline"], 60.0)
            t |> success(res.ok, res.error)
            t |> equal(join(recorded_argv(dir), " "), "/src/compile_commands.json --libc std --strict --module-layout source --runtime-module c2da_runtime --output-dir {out} --no-inline")
            t |> equal(join(res.files, " "), "{out}/c2da_runtime.das {out}/prog.das {out}/prog.das.inc")
            t |> equal(res.entry, path_join(out, "prog.das"))
        }
    }
}

struct ParsedCommand {
    directory : string
    file : string
    arguments : array<string>
}

[test]
def test_write_compile_commands(t : T?) {
    t |> run("one clang command per file, the defines and the object named by the stem") @(t : T?) {
        t |> with_stand_in("c2das_db_write") $(dir, _bin) {
            let path = path_join(dir, "compile_commands.json")
            write_compile_commands(path, ["/src/lvm.c", "/src/lua.c"], ["LUA_USE_C89", "N=2"], "/build")
            var error : string
            let js = read_json(fread(path), error)
            t |> equal(error, "")
            let commands <- from_JV(js, type<array<ParsedCommand>>)
            t |> equal(length(commands), 2)
            t |> equal(commands[0].directory, "/build")
            t |> equal(commands[1].file, "/src/lua.c")
            t |> equal(join(commands[0].arguments, " "), "clang -c /src/lvm.c -DLUA_USE_C89 -DN=2 -o lvm.o")
            t |> equal(join(commands[1].arguments, " "), "clang -c /src/lua.c -DLUA_USE_C89 -DN=2 -o lua.o")
        }
    }
}

[test]
def test_run_translation(t : T?) {
    t |> run("the entry runs under the interpreter as `main`, its arguments after `--`") @(t : T?) {
        t |> with_stand_in("c2das_run") $(dir, _bin) {
            let entry = path_join(dir, "prog.das")
            fwrite(entry, ENTRY_DAS)
            let res = RustTranslation(ok = true, entry = entry, out_dir = dir)
            var output : string
            t |> equal(run_translation(res, "interp", path_join(dir, "work"), output, 60.0, ["in.txt"]), 3, output)
            t |> equal(strip(output), "arg --\narg in.txt")
            t |> equal(run_translation(res, "interp", path_join(dir, "work"), output, 60.0, NO_ARGS), 3, output)
            t |> equal(strip(output), "")
            t |> equal(run_translation(res, "interp", path_join(dir, "work"), output, 60.0, ["-no-module-cache"], ["x"]), 3, output)
            t |> equal(strip(output), "arg --\narg x")
        }
    }
    t |> run("a failed translation and one without main do not run") @(t : T?) {
        var output : string
        let failed = RustTranslation(ok = false, error = "exit 2", entry = "/nowhere/prog.das")
        t |> equal(run_translation(failed, "interp", "/nowhere/work", output, 60.0, NO_ARGS), -1)
        t |> equal(output, "the translation failed: exit 2\n")
        let no_main = RustTranslation(ok = true, out_dir = "/nowhere")
        t |> equal(run_translation(no_main, "interp", "/nowhere/work", output, 60.0, NO_ARGS), -1)
        t |> equal(output, "the translation defines no main in /nowhere\n")
    }
}
