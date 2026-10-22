options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost

//! The lua harness without the release: `lua/run.das` over a scratch tree holding a stand-in
//! `lua/fetch/lua-5.4.8/src` of small C files, `lua/fetch.sh`'s refusals over a scratch
//! `VERSIONS.md` and tarballs, and `lua/REVIEW.das` over a scratch git index.

// the sources run.das composes, each a stand-in here
let CORE <- ["lapi", "lcode", "lctype", "ldebug", "ldo", "ldump", "lfunc", "lgc", "llex", "lmem", "lobject", "lopcodes", "lparser", "lstate", "lstring", "ltable", "ltm", "lundump", "lvm", "lzio", "lauxlib", "lbaselib", "lcorolib", "ldblib", "liolib", "lmathlib", "loadlib", "loslib", "lstrlib", "ltablib", "lutf8lib", "linit"]

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
    fwrite(path_join(src, "luac.c"), "int main(void) \{ return 0; \}\n")
    return root
}

let LOBJECT = "#include \"lua.h\"\nint lua_answer(void) \{ return 41; \}\n"

[test]
def test_run_refusals(t : T?) {
    t |> run("run.das refuses a tier other than interp or jit, and a tree with no fetched sources") @(t : T?) {
        var dir_error : string
        let empty_root = create_temp_directory("c2das_lua_empty", dir_error)
        t |> equal(dir_error, "")
        var out : string
        t |> equal(run_in(empty_root, daslang_argv("lua/run.das", ["--tier", "aot"]), out), 1, out)
        t |> success(out |> contains("--tier is interp or jit, not `aot`"), out)
        t |> equal(run_in(empty_root, daslang_argv("lua/run.das", array<string>()), out), 1, out)
        t |> success(out |> contains("no lua/fetch/lua-5.4.8/src; run lua/fetch.sh first"), out)
        rmdir_rec(empty_root)
    }
}

[test]
def test_run_stand_in(t : T?) {
    t |> run("run.das composes the sources under a banner each, converts, and agrees with the native build under the interpreter and the JIT") @(t : T?) {
        let root = stand_in_root("c2das_lua_stand_in", LOBJECT)
        t |> success(!empty(root))
        for (tier in ["interp", "jit"]) {
            var out : string
            t |> equal(run_in(root, daslang_argv("lua/run.das", ["--run", "--tier", tier, "--filter", "lua_all", "--arg", "word"]), out), 0, out)
            // the JIT's `[I]` lines are no part of the program's output
            t |> success(out |> contains("lua: {tier} exited 0: 43 word\n"), out)
        }
        let composed = fread(path_join(root, "lua/work/lua_all.c"))
        t |> success(composed |> starts_with("/* lua_all: lua 5.4.8 as one translation unit, composed by lua/run.das */\n#define LUA_CORE\n#define LUA_LIB\n#define lua_c\n/* ==== lapi.c ==== */\n"), composed)
        t |> success(composed |> contains("/* ==== linit.c ==== */\n/* linit */\n/* ==== lua.c ==== */\n"), composed)
        // the compiler links no standard library
        var out : string
        t |> equal(run_in(root, daslang_argv("lua/run.das", ["--filter", "luac_all"]), out), 0, out)
        let compiler = fread(path_join(root, "lua/work/luac_all.c"))
        t |> success(compiler |> contains("/* ==== lauxlib.c ==== */\n/* lauxlib */\n/* ==== luac.c ==== */\n"), compiler)
        t |> success(!(compiler |> contains("lbaselib")), compiler)
        rmdir_rec(root)
    }
    t |> run("a conversion error names the Lua source and line beside the composed file's location") @(t : T?) {
        let root = stand_in_root("c2das_lua_located", "#include \"lua.h\"\nint lua_answer(void) \{ return L\"x\"[0]; \}\n")
        var out : string
        t |> equal(run_in(root, daslang_argv("lua/run.das", ["--filter", "lua_all"]), out), 1, out)
        t |> success(out |> contains("(lua lobject.c:2)"), out)
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

[test]
def test_review_gate(t : T?) {
    t |> run("lua/REVIEW.das finds a tracked file under lua/fetch or lua/work, and passes a tree with none") @(t : T?) {
        var dir_error : string
        let root = create_temp_directory("c2das_lua_gate", dir_error)
        t |> equal(dir_error, "")
        var out : string
        t |> equal(run_in(root, ["git", "init", "-q"], out), 0, out)
        mkdir_rec(path_join(root, "lua/work"))
        fwrite(path_join(root, "lua/run.das"), "// tracked\n")
        fwrite(path_join(root, "lua/work/lua_all.c"), "/* generated */\n")
        t |> equal(run_in(root, ["git", "add", "lua/run.das"], out), 0, out)
        let gate <- daslang_argv("lua/REVIEW.das", array<string>())
        t |> equal(run_in(root, gate, out), 0, out)
        t |> equal(run_in(root, ["git", "add", "-f", "lua/work/lua_all.c"], out), 0, out)
        t |> equal(run_in(root, gate, out), 1, out)
        t |> success(out |> contains("lua/work/lua_all.c") && out |> contains("never committed"), out)
        rmdir_rec(root)
    }
}
