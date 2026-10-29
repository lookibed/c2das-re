options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost

//! The lua harness without the release: `lua/run.das` over a scratch tree holding a stand-in
//! `lua/fetch/lua-5.4.8/src` of small C files, `lua/fetch.sh`'s refusals over a scratch
//! `VERSIONS.md` and tarballs, and `lua/REVIEW.das` over a scratch git index.

// the sources run.das links, each a stand-in here
let CORE <- ["lapi", "lcode", "lctype", "ldebug", "ldo", "ldump", "lfunc", "lgc", "llex", "lmem", "lobject", "lopcodes", "lparser", "lstate", "lstring", "ltable", "ltm", "lundump", "lvm", "lzio", "lauxlib", "lbaselib", "lcorolib", "ldblib", "liolib", "lmathlib", "loadlib", "loslib", "lstrlib", "ltablib", "lutf8lib", "linit"]

// the standard libraries among them, which only the interpreter links
let STANDARD <- ["lbaselib", "lcorolib", "ldblib", "liolib", "lmathlib", "loadlib", "loslib", "lstrlib", "ltablib", "lutf8lib", "linit"]

def private run_in(dir : string; argv : array<string>; var out : string&) : int {
    var shell <- ["sh", "-c", "cd \"$0\" && exec \"$@\"", dir]
    shell |> push_from(argv)
    return run_and_capture(shell, out, 600.0)
}

def private daslang_argv(script : string; args : array<string>) : array<string> {
    var argv <- [get_das_root() + "/bin/daslang", "-load_module", get_full_file_name("dasCRuntime"), "-load_module", get_full_file_name("c_runtime"), get_full_file_name(script), "--"]
    argv |> push_from(args)
    return <- argv
}

// a scratch root for run.das: the module folders its tiers load by relative path linked, the
// stand-in sources, `lobject.c` holding `lobject`, and an empty sidecar
def private stand_in_root(name, lobject : string) : string {
    var dir_error : string
    let root = create_temp_directory(name, dir_error)
    if (!empty(dir_error)) {
        return ""
    }
    var out : string
    for (folder in ["c_runtime", "dasCRuntime"]) {
        run_and_capture(["ln", "-s", get_full_file_name(folder), path_join(root, folder)], out, 30.0)
    }
    let src = path_join(root, "lua/fetch/lua-5.4.8/src")
    mkdir_rec(src)
    fwrite(path_join(root, "lua/lua.c2das"), "\{\}\n")
    fwrite(path_join(src, "lua.h"), "int lua_answer(void);\n")
    for (source in CORE) {
        fwrite(path_join(src, "{source}.c"), source == "lobject" ? lobject : "/* {source} */\n")
    }
    fwrite(path_join(src, "lua.c"), "#include <stdio.h>\n#include \"lua.h\"\nint main(int argc, char **argv) \{ printf(\"%d %s\\n\", lua_answer() + argc, argv[argc - 1]); return 0; \}\n")
    fwrite(path_join(src, "luac.c"), LUAC_C)
    return root
}

// a stand-in compiler: `luac -o <out> <in>` writes the input's bytes, each xored, to the output
let LUAC_C = "#include <stdio.h>\nint main(int argc, char **argv) \{\n    char buf[256];\n    FILE *in, *out;\n    size_t n;\n    if (argc != 4) return 2;\n    in = fopen(argv[3], \"rb\");\n    out = fopen(argv[2], \"wb\");\n    if (in == 0 || out == 0) return 1;\n    n = fread(buf, 1, sizeof buf, in);\n    for (size_t i = 0; i < n; i++) buf[i] = (char)(buf[i] ^ 0x5a);\n    fwrite(buf, 1, n, out);\n    fclose(in);\n    fclose(out);\n    return 0;\n\}\n"

// a stand-in compiler whose output differs from build to build: `luac -o <out> <in>` writes its own
// `argv[0]`, the native binary's path or the converted program's name, to the output
let LUAC_ARGV0_C = "#include <stdio.h>\n#include <string.h>\nint main(int argc, char **argv) \{\n    FILE *out;\n    if (argc != 4) return 2;\n    out = fopen(argv[2], \"wb\");\n    if (out == 0) return 1;\n    fwrite(argv[0], 1, strlen(argv[0]), out);\n    fclose(out);\n    return 0;\n\}\n"

let LOBJECT = "#include \"lua.h\"\nint lua_answer(void) \{ return 41; \}\n"

[test]
def test_run_refusals(t : T?) {
    t |> run("run.das refuses a tier other than interp or jit, a layout other than source, scc, single or all, and a tree with no fetched sources") @(t : T?) {
        var dir_error : string
        let empty_root = create_temp_directory("c2das_lua_empty", dir_error)
        t |> equal(dir_error, "")
        var out : string
        t |> equal(run_in(empty_root, daslang_argv("lua/run.das", ["--tier", "aot"]), out), 1, out)
        t |> success(out |> contains("--tier is interp or jit, not `aot`"), out)
        t |> equal(run_in(empty_root, daslang_argv("lua/run.das", ["--layout", "flat"]), out), 1, out)
        t |> success(out |> contains("--layout is source, scc, single or all, not `flat`"), out)
        t |> equal(run_in(empty_root, daslang_argv("lua/run.das", array<string>()), out), 1, out)
        t |> success(out |> contains("no lua/fetch/lua-5.4.8/src; run lua/fetch.sh first"), out)
        rmdir_rec(empty_root)
    }
}

// a stand-in `nm` under `root`: `--version` prints `version` as binutils does, any other run exits 1
def private stand_in_nm(root, version : string) : string {
    let nm = path_join(get_full_file_name(root), "nm")
    fwrite(nm, "#!/bin/sh\nif [ \"$1\" = --version ]; then echo \"GNU nm (GNU Binutils for Debian) {version}\"; exit 0; fi\nexit 1\n")
    var out : string
    run_and_capture(["chmod", "+x", nm], out, 30.0)
    return nm
}

[test]
def test_profile_refusals(t : T?) {
    t |> run("profile.das refuses an nm other than the one VERSIONS.md pins, a missing one, a failed run and an object listing no text symbol") @(t : T?) {
        var pin = ""
        for (line in split(fread("VERSIONS.md"), "\n")) {
            if (line |> starts_with("nm: ")) {
                pin = split(slice(line, 4), " ")[0]
            }
        }
        t |> success(!empty(pin))
        let root = stand_in_root("c2das_lua_profile", LOBJECT)
        t |> success(!empty(root))
        fwrite(path_join(root, "VERSIONS.md"), "nm: {pin} (stand-in)\n")
        var out : string
        t |> equal(run_in(root, daslang_argv("lua/profile.das", ["--nm", path_join(root, "missing_nm")]), out), 1, out)
        t |> success(out |> contains("missing_nm --version` printed `` (exit ") && out |> contains("VERSIONS.md pins nm `{pin}`"), out)
        t |> equal(run_in(root, daslang_argv("lua/profile.das", ["--nm", stand_in_nm(root, "0.1")]), out), 1, out)
        t |> success(out |> contains("printed `GNU nm (GNU Binutils for Debian) 0.1` (exit 0), VERSIONS.md pins nm `{pin}`"), out)
        // the pinned version, every listing failing: refused at the first object
        t |> equal(run_in(root, daslang_argv("lua/profile.das", ["--nm", stand_in_nm(root, pin)]), out), 1, out)
        t |> success(out |> contains("nm -n ") && out |> contains("lapi.o exited 1"), out)
        // the real nm over the stand-in `lapi.c`, a comment alone
        t |> equal(run_in(root, daslang_argv("lua/profile.das", array<string>()), out), 1, out)
        t |> success(out |> contains("lapi.o lists no text symbol"), out)
        rmdir_rec(root)
    }
}

// the full paths of the stand-in sources of `root`, each a JSON string, in link order
def private manifest_tus(root : string; sources : array<string>) : string {
    let src = get_full_file_name(path_join(root, "lua/fetch/lua-5.4.8/src"))
    return join([for (source in sources); "\"{src}/{source}.c\""], ", ")
}

[test]
def test_run_stand_in(t : T?) {
    t |> run("run.das converts each program from its separate sources through a manifest in all three layouts, and each agrees with the native build under the interpreter and the JIT") @(t : T?) {
        let root = stand_in_root("c2das_lua_stand_in", LOBJECT)
        t |> success(!empty(root))
        for (tier in ["interp", "jit"]) {
            var out : string
            t |> equal(run_in(root, daslang_argv("lua/run.das", ["--run", "--tier", tier, "--filter", "lua", "--arg", "word"]), out), 0, out)
            // the JIT's `[I]` lines are no part of the program's output; one run per layout
            t |> equal(length(split(out, "lua: {tier} exited 0: 43 word\n")) - 1, 3, out)
            t |> success(out |> contains("lua: lua (source): ") && out |> contains("lua: lua (scc): ") && out |> contains("lua: lua (single): "), out)
        }
        // the source layout's tree: the entry module and the module of the file defining
        // `lua_answer`, which it requires; the single layout's one module under `single/`
        t |> success(fexist(path_join(root, "lua/work/lua/lua.das")) && fexist(path_join(root, "lua/work/lua/lobject.das")), root)
        t |> success(fread(path_join(root, "lua/work/lua/lua.das")) |> contains("require lobject\n"))
        t |> success(fexist(path_join(root, "lua/work/single/lua/lua.das")) && !fexist(path_join(root, "lua/work/single/lua/lobject.das")), root)
        t |> success(fexist(path_join(root, "lua/work/scc/lua/lua.das")) && fexist(path_join(root, "lua/work/scc/lua/lobject.das")), root)
        var interpreter <- clone_to_move(CORE)
        interpreter |> push("lua")
        t |> equal(fread(path_join(root, "lua/work/lua.program.json")), "\{\n \"tus\": [{manifest_tus(root, interpreter)}],\n \"entry\": \"main\"\n\}\n")
        // `--filter` names one program's stem: `lua` is not `luac`
        t |> success(!fexist(path_join(root, "lua/work/luac.program.json")))
        // the converted module is the entry unit's, and no header is copied out of the release
        t |> success(fexist(path_join(root, "lua/work/lua/lua.das")) && !fexist(path_join(root, "lua/work/lua.h")))
        // the compiler links no standard library
        var out : string
        t |> equal(run_in(root, daslang_argv("lua/run.das", ["--filter", "luac", "--layout", "source"]), out), 0, out)
        t |> success(!fexist(path_join(root, "lua/work/single/luac/luac.das")), out)
        var compiler <- [for (source in CORE); source; where !has_value(STANDARD, source)]
        compiler |> push("luac")
        t |> equal(fread(path_join(root, "lua/work/luac.program.json")), "\{\n \"tus\": [{manifest_tus(root, compiler)}],\n \"entry\": \"main\"\n\}\n")
        t |> success(fexist(path_join(root, "lua/work/luac/luac.das")))
        rmdir_rec(root)
    }
    t |> run("--luac-check compiles every script of a folder with the converted compiler's -o in each layout, byte for byte the native compiler's, and refuses a folder with none") @(t : T?) {
        let root = stand_in_root("c2das_lua_luac", LOBJECT)
        let scripts = path_join(root, "scripts")
        mkdir_rec(scripts)
        // `Z` xors to a zero byte, past which a das string would compare nothing
        fwrite(path_join(scripts, "a.lua"), "print(\"Zebra\")\n")
        fwrite(path_join(scripts, "b.lua"), "return \"two\"\n")
        var out : string
        t |> equal(run_in(root, daslang_argv("lua/run.das", ["--filter", "luac", "--luac-check", "scripts"]), out), 0, out)
        t |> equal(length(split(out, "lua: luac -o under interp: 2 of 2 files byte for byte the native compiler's\n")) - 1, 3, out)
        t |> success(fexist(path_join(root, "lua/work/luac/luac_check/a.interp.luac")) && fexist(path_join(root, "lua/work/single/luac/luac_check/a.native.luac")), out)
        mkdir_rec(path_join(root, "none"))
        t |> equal(run_in(root, daslang_argv("lua/run.das", ["--filter", "luac", "--layout", "single", "--luac-check", "none"]), out), 1, out)
        t |> success(out |> contains("lua: luac -o: no .lua file in none"), out)
        rmdir_rec(root)
    }
    t |> run("--luac-check fails when the converted compiler writes other bytes than the native one, its exit code the same") @(t : T?) {
        let root = stand_in_root("c2das_lua_luac_differ", LOBJECT)
        fwrite(path_join(root, "lua/fetch/lua-5.4.8/src/luac.c"), LUAC_ARGV0_C)
        let scripts = path_join(root, "scripts")
        mkdir_rec(scripts)
        fwrite(path_join(scripts, "a.lua"), "return 1\n")
        var out : string
        t |> equal(run_in(root, daslang_argv("lua/run.das", ["--filter", "luac", "--layout", "source", "--luac-check", "scripts"]), out), 1, out)
        t |> success(out |> contains("lua: luac -o a.lua: native exited 0, interp 0; the bytes differ"), out)
        t |> success(out |> contains("lua: luac -o under interp: 0 of 1 files byte for byte the native compiler's"), out)
        rmdir_rec(root)
    }
    t |> run("a conversion error names the Lua source and line") @(t : T?) {
        let root = stand_in_root("c2das_lua_located", "#include \"lua.h\"\nint lua_answer(void) \{ return L\"x\"[0]; \}\n")
        var out : string
        t |> equal(run_in(root, daslang_argv("lua/run.das", ["--filter", "lua"]), out), 1, out)
        t |> success(out |> contains("lobject.c:2:"), out)
        rmdir_rec(root)
    }
}

// a scratch copy of fetch.sh under `root/lua`, with `versions` as the root's VERSIONS.md: its exit
// code and output
def private fetch_in(root, versions : string; var out : string&) : int {
    mkdir_rec(path_join(root, "lua"))
    fwrite(path_join(root, "lua/fetch.sh"), fread("lua/fetch.sh"))
    fwrite(path_join(root, "VERSIONS.md"), versions)
    return run_and_capture(["bash", path_join(root, "lua/fetch.sh")], out, 60.0)
}

[test]
def test_fetch_refusals(t : T?) {
    t |> run("fetch.sh refuses a missing pin, a pin naming other than two tarballs, and a tarball whose sha256 differs") @(t : T?) {
        var dir_error : string
        let root = create_temp_directory("c2das_lua_fetch", dir_error)
        t |> equal(dir_error, "")
        var out : string
        t |> equal(fetch_in(root, "# no pin\n", out), 1, out)
        t |> success(out |> contains("VERSIONS.md names no lua pin"), out)
        let hash = repeat("0", 64)
        t |> equal(fetch_in(root, "lua: https://example.invalid/a.tar.gz (sha256 {hash})\n", out), 1, out)
        t |> success(out |> contains("names two tarballs"), out)
        // both tarballs present, so nothing is downloaded
        mkdir_rec(path_join(root, "lua/fetch"))
        fwrite(path_join(root, "lua/fetch/a.tar.gz"), "not the pinned bytes")
        fwrite(path_join(root, "lua/fetch/b.tar.gz"), "not the pinned bytes")
        t |> equal(fetch_in(root, "lua: https://example.invalid/a.tar.gz (sha256 {hash}), https://example.invalid/b.tar.gz (sha256 {hash})\n", out), 1, out)
        t |> success(out |> contains("a.tar.gz has sha256 ") && out |> contains("VERSIONS.md pins {hash}"), out)
        rmdir_rec(root)
    }
}

// a scratch `VERSIONS.md` pinning `pinned` on its `lua:` line and a `lua/sources.das` whose
// `SOURCES` names the folder of `fetched`
def private stage_release_pair(root : string; pinned : string; fetched : string) {
    mkdir_rec(path_join(root, "lua"))
    fwrite(path_join(root, "VERSIONS.md"), "lua: {pinned} (the lua.org release)\n")
    fwrite(path_join(root, "lua/sources.das"), "let SOURCES = \"lua/fetch/lua-{fetched}/src\"\n")
}

[test]
def test_review_gate(t : T?) {
    t |> run("lua/REVIEW.das finds a tracked file under lua/fetch or lua/work, and passes a tree with none") @(t : T?) {
        var dir_error : string
        let root = create_temp_directory("c2das_lua_gate", dir_error)
        t |> equal(dir_error, "")
        var out : string
        t |> equal(run_in(root, ["git", "init", "-q"], out), 0, out)
        mkdir_rec(path_join(root, "lua/work"))
        stage_release_pair(root, "5.4.8", "5.4.8")
        fwrite(path_join(root, "lua/run.das"), "// tracked\n")
        fwrite(path_join(root, "lua/work/lua.program.json"), "\{\}\n")
        t |> equal(run_in(root, ["git", "add", "lua/run.das"], out), 0, out)
        let gate <- daslang_argv("lua/REVIEW.das", array<string>())
        t |> equal(run_in(root, gate, out), 0, out)
        t |> equal(run_in(root, ["git", "add", "-f", "lua/work/lua.program.json"], out), 0, out)
        t |> equal(run_in(root, gate, out), 1, out)
        t |> success(out |> contains("lua/work/lua.program.json") && out |> contains("never committed"), out)
        rmdir_rec(root)
    }
    t |> run("lua/REVIEW.das finds a SOURCES folder of another release than the lua: line pins") @(t : T?) {
        var dir_error : string
        let root = create_temp_directory("c2das_lua_gate", dir_error)
        t |> equal(dir_error, "")
        var out : string
        t |> equal(run_in(root, ["git", "init", "-q"], out), 0, out)
        stage_release_pair(root, "5.4.8", "5.4.8")
        let gate <- daslang_argv("lua/REVIEW.das", array<string>())
        t |> equal(run_in(root, gate, out), 0, out)
        stage_release_pair(root, "5.4.9", "5.4.8")
        t |> equal(run_in(root, gate, out), 1, out)
        t |> success(out |> contains("lua/sources.das") && out |> contains("lua/fetch/lua-5.4.9/src"), out)
        rmdir_rec(root)
    }
}
