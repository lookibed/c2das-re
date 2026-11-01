options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require ../../perf/perf_lanes.das

//! The lua harness without the release: `lua/run.das` over a scratch tree holding a stand-in
//! `lua/fetch/lua-5.4.8/src` of small C files, `lua/fetch.sh`'s refusals over a scratch
//! `VERSIONS.md` and tarballs, and `lua/REVIEW.das` over a scratch git index.

// the sources run.das links, each a stand-in here
let CORE <- ["lapi", "lcode", "lctype", "ldebug", "ldo", "ldump", "lfunc", "lgc", "llex", "lmem", "lobject", "lopcodes", "lparser", "lstate", "lstring", "ltable", "ltm", "lundump", "lvm", "lzio", "lauxlib", "lbaselib", "lcorolib", "ldblib", "liolib", "lmathlib", "loadlib", "loslib", "lstrlib", "ltablib", "lutf8lib", "linit"]

// the standard libraries among them, which only the interpreter links
let STANDARD <- ["lbaselib", "lcorolib", "ldblib", "liolib", "lmathlib", "loadlib", "loslib", "lstrlib", "ltablib", "lutf8lib", "linit"]

def private run_in(dir : string; argv : array<string>; var out : string&) : int => run_and_capture(in_folder(dir, argv), out, 600.0)

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

// a stand-in interpreter that recovers from its own error: an argument naming `error` longjmps out
// of the protected part, which prints `caught` instead of the answer and exits 1
let LUA_PROTECTED_C = "#include <stdio.h>\n#include <setjmp.h>\n#include <string.h>\n#include \"lua.h\"\nstatic jmp_buf b;\nstatic void raise_error(void) \{ longjmp(b, 1); \}\nint main(int argc, char **argv) \{\n    int status = 0;\n    if (setjmp(b) == 0) \{\n        if (strstr(argv[argc - 1], \"error\")) raise_error();\n        printf(\"%d %s\\n\", lua_answer() + argc, argv[argc - 1]);\n    \} else \{\n        printf(\"caught\\n\");\n        status = 1;\n    \}\n    return status;\n\}\n"

// a stand-in interpreter whose output differs from run to run: it appends a byte to the file at
// `path`, wherever the run's folder is, and prints the file's size
def private lua_runs_c(path : string) : string =>
    "#include <stdio.h>\nint main(void) \{\n    FILE *f = fopen(\"{path}\", \"ab\");\n    if (f == 0) return 2;\n    fwrite(\"x\", 1, 1, f);\n    printf(\"%ld\\n\", ftell(f));\n    fclose(f);\n    return 0;\n\}\n"

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

// a stand-in `nm` under `root`: `--version` prints `version` as binutils does, any other run prints
// nothing and exits `listing_rc`
def private stand_in_nm(root, version : string; listing_rc : int) : string {
    let nm = path_join(get_full_file_name(root), "nm")
    fwrite(nm, "#!/bin/sh\nif [ \"$1\" = --version ]; then echo \"GNU nm (GNU Binutils for Debian) {version}\"; exit 0; fi\nexit {listing_rc}\n")
    var out : string
    run_and_capture(["chmod", "+x", nm], out, 30.0)
    return nm
}

[test]
def test_profile_refusals(t : T?) {
    t |> run("profile.das refuses an nm of a version VERSIONS.md does not list, a missing one, a failed listing and a binary listing no text symbol, and accepts an object holding data alone under every listed version") @(t : T?) {
        // the versions VERSIONS.md lists, as profile.das's `nm_pins` reads them: the comma-separated
        // words before the line's first parenthesis
        var nm_line = ""
        for (line in split(fread("VERSIONS.md"), "\n")) {
            if (line |> starts_with("nm: ")) {
                nm_line = split(slice(line, 4), " (")[0]
            }
        }
        let pins <- [for (word in split(nm_line, ",")); strip(word)]
        t |> success(!empty(pins), "VERSIONS.md names no nm version")
        let pin = pins[0]
        let listed = join(pins, ", ")
        let root = stand_in_root("c2das_lua_profile", LOBJECT)
        t |> success(!empty(root))
        fwrite(path_join(root, "VERSIONS.md"), "nm: {listed} (stand-in)\n")
        // the test suite and the benchmarks the profiled binary runs: the stand-in ignores its arguments
        mkdir_rec(path_join(root, "lua/fetch/lua-5.4.8-tests"))
        fwrite(path_join(root, "lua/fetch/lua-5.4.8-tests/all.lua"), "")
        mkdir_rec(path_join(root, "ports/lua/bench"))
        for (name in ["fib", "binary_trees", "nbody", "spectral_norm"]) {
            fwrite(path_join(root, "ports/lua/bench/{name}.lua"), "")
        }
        var out : string
        t |> equal(run_in(root, daslang_argv("lua/profile.das", ["--nm", path_join(root, "missing_nm")]), out), 1, out)
        t |> success(out |> contains("missing_nm --version` printed `` (exit ") && out |> contains("VERSIONS.md pins nm `{listed}`"), out)
        t |> equal(run_in(root, daslang_argv("lua/profile.das", ["--nm", stand_in_nm(root, "0.1", 1)]), out), 1, out)
        t |> success(out |> contains("printed `GNU nm (GNU Binutils for Debian) 0.1` (exit 0), VERSIONS.md pins nm `{listed}`"), out)
        // the last listed version passes the version check too: the run gets as far as the listings
        t |> equal(run_in(root, daslang_argv("lua/profile.das", ["--nm", stand_in_nm(root, pins[length(pins) - 1], 0)]), out), 1, out)
        t |> success(out |> contains("lua_profiled lists no text symbol") && !(out |> contains("VERSIONS.md pins nm")), out)
        // the pinned version, every listing failing: refused at the first object, no second one listed
        t |> equal(run_in(root, daslang_argv("lua/profile.das", ["--nm", stand_in_nm(root, pin, 1)]), out), 1, out)
        t |> success(out |> contains("nm -n ") && out |> contains("lapi.o exited 1") && !(out |> contains("lcode.o")), out)
        // every listing empty: each object passes as one holding data alone, the binary is refused
        t |> equal(run_in(root, daslang_argv("lua/profile.das", ["--nm", stand_in_nm(root, pin, 0)]), out), 1, out)
        t |> success(out |> contains("lua_profiled lists no text symbol") && !(out |> contains("lapi.o")), out)
        // the real nm: the stand-in `lapi.c`, a comment alone, passes; `lua_answer` is the one call
        // crossing files, once per run of the suite and each benchmark
        t |> equal(run_in(root, daslang_argv("lua/profile.das", array<string>()), out), 0, out)
        t |> equal(fread(path_join(root, "lua/lua.profile.json")), "\{\n  \"lua_answer\": \{\"lua\": 5\}\n\}\n")
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

// a stand-in interpreter whose stream differs from run to run: it appends a byte to the file at
// `path` and prints its last argument, to stderr on an odd run (the native build's, which runs
// first) and to stdout on an even one: the merged outputs agree, the streams do not
def private lua_stream_c(path : string) : string =>
    "#include <stdio.h>\nint main(int argc, char **argv) \{\n    FILE *f = fopen(\"{path}\", \"ab\");\n    if (f == 0) return 2;\n    fwrite(\"x\", 1, 1, f);\n    long size = ftell(f);\n    fclose(f);\n    fprintf(size % 2 ? stderr : stdout, \"%s\\n\", argv[argc - 1]);\n    return 0;\n\}\n"

[test]
def test_error_check(t : T?) {
    t |> run("--error-check runs each error-recovery check with the converted interpreter of each layout under the interpreter and the JIT, each agreeing with the native build") @(t : T?) {
        let root = stand_in_root("c2das_lua_errors", LOBJECT)
        fwrite(path_join(root, "lua/fetch/lua-5.4.8/src/lua.c"), LUA_PROTECTED_C)
        for (tier in ["interp", "jit"]) {
            var out : string
            t |> equal(run_in(root, daslang_argv("lua/run.das", ["--error-check", "--tier", tier, "--filter", "lua"]), out), 0, out)
            t |> equal(length(split(out, "lua: error checks under {tier}: 8 of 8 agree with the native build\n")) - 1, 3, out)
            // a check naming `error` raises the stand-in's; the VM error's and the memory error's do not
            t |> success(out |> contains("lua: {tier} exited 1: caught\n") && out |> contains("lua: {tier} exited 0: 44 print(pcall(string.rep, 'x', 1 << 40))\n"), out)
        }
        rmdir_rec(root)
    }
    t |> run("--error-check fails, naming each check, when the converted interpreter's output differs from the native one's") @(t : T?) {
        let root = stand_in_root("c2das_lua_errors_differ", LOBJECT)
        fwrite(path_join(root, "lua/fetch/lua-5.4.8/src/lua.c"), lua_runs_c(path_join(root, "runs.bin")))
        var out : string
        t |> equal(run_in(root, daslang_argv("lua/run.das", ["--error-check", "--filter", "lua", "--layout", "single"]), out), 1, out)
        t |> success(out |> contains("lua: error check `-e print(pcall(error, 'boom'))` under interp differs from the native build"), out)
        t |> success(out |> contains("lua: error checks under interp: 0 of 8 agree with the native build"), out)
        rmdir_rec(root)
    }
    t |> run("--error-check compares stdout and stderr apart: the same text on the other stream differs, naming it") @(t : T?) {
        let root = stand_in_root("c2das_lua_errors_stream", LOBJECT)
        fwrite(path_join(root, "lua/fetch/lua-5.4.8/src/lua.c"), lua_stream_c(path_join(root, "stream.bin")))
        var out : string
        t |> equal(run_in(root, daslang_argv("lua/run.das", ["--error-check", "--filter", "lua", "--layout", "single"]), out), 1, out)
        t |> success(out |> contains("lua: error check `-e error('x')` under interp differs from the native build: stdout and stderr differ"), out)
        t |> success(out |> contains("lua: error checks under interp: 0 of 8 agree with the native build"), out)
        t |> success(!fexist(path_join(root, "lua/work/run.stderr")), out)
        rmdir_rec(root)
    }
}

// a stand-in interpreter for the test suite: its last argument names a script whose first word
// says what to do - `spin` counts long enough that only the converted build outlasts a short
// timeout, `grow` allocates until a cap kills it or, under an address-space limit, until `malloc`
// fails, which it reports as `lua.c` does and exits 4, `oracle` prints a traceback to stderr and
// exits 5, `runs` prints an `x` per run so far, `stream`
// prints one line to stderr on an odd run and to stdout on an even one, `port` prints the `-e`
// string before the script and fails unless it is `_port=false`, `seek` seeks its stdin and exits 7
// when that succeeds, `self` writes the name its process runs under (`/proc/self/cmdline`'s first
// word, `lua` natively, `daslang` converted) to `self.txt`, `launch` runs `lua self.lua` through
// `system` and prints `same` when that name is its own, `shape`
// prints a time in `%g`'s other notation and sign on a later run, with all.lua's time warning, any
// other word prints itself with digits that differ from run to run
let LUA_SUITE_C = "#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\n#include <time.h>\n#include \"lua.h\"\nstatic void own_name(char *name, size_t size) \{\n    char line[4096];\n    FILE *f = fopen(\"/proc/self/cmdline\", \"rb\");\n    size_t n = f ? fread(line, 1, sizeof line - 1, f) : 0;\n    if (f) fclose(f);\n    line[n] = 0;\n    char *slash = strrchr(line, '/');\n    snprintf(name, size, \"%s\", slash ? slash + 1 : line);\n\}\nint main(int argc, char **argv) \{\n    char word[64];\n    FILE *f = fopen(argv[argc - 1], \"r\");\n    if (f == 0 || fgets(word, sizeof word, f) == 0) return 3;\n    fclose(f);\n    for (char *c = word; *c; c++) if (*c == '\\n') *c = 0;\n    if (strcmp(word, \"oracle\") == 0) \{\n        fprintf(stderr, \"\\nbroken\\ntraceback\\n\");\n        return 5;\n    \}\n    if (strcmp(word, \"spin\") == 0) \{\n        volatile long n = 0;\n        while (n < 300000000L) n++;\n    \}\n    if (strcmp(word, \"grow\") == 0) \{\n        for (;;) \{\n            char *p = malloc(1 << 24);\n            if (p == 0) \{ fputs(\"not enough memory\\n\", stderr); return 4; \}\n            memset(p, 1, 1 << 24);\n        \}\n    \}\n    if (strcmp(word, \"runs\") == 0) \{\n        FILE *g = fopen(\"runs.bin\", \"ab\");\n        fwrite(\"x\", 1, 1, g);\n        long size = ftell(g);\n        fclose(g);\n        for (long i = 0; i < size; i++) printf(\"x\");\n        printf(\"\\n\");\n        return 0;\n    \}\n    if (strcmp(word, \"stream\") == 0) \{\n        FILE *g = fopen(\"stream.bin\", \"ab\");\n        fwrite(\"x\", 1, 1, g);\n        long size = ftell(g);\n        fclose(g);\n        fprintf(size % 2 ? stderr : stdout, \"streamed\\n\");\n        return 0;\n    \}\n    if (strcmp(word, \"port\") == 0) \{\n        if (strcmp(argv[argc - 2], \"_port=false\") != 0) return 6;\n        printf(\"%s\\n\", argv[argc - 2]);\n        return 0;\n    \}\n    if (strcmp(word, \"self\") == 0) \{\n        char name[256];\n        own_name(name, sizeof name);\n        FILE *g = fopen(\"self.txt\", \"w\");\n        fprintf(g, \"%s\", name);\n        fclose(g);\n        return 0;\n    \}\n    if (strcmp(word, \"launch\") == 0) \{\n        char name[256], nested[256] = \"\";\n        own_name(name, sizeof name);\n        if (system(\"lua self.lua\") != 0) return 8;\n        FILE *g = fopen(\"self.txt\", \"r\");\n        if (g == 0 || fgets(nested, sizeof nested, g) == 0) return 9;\n        fclose(g);\n        printf(strcmp(name, nested) == 0 ? \"same\\n\" : \"other %s %s\\n\", name, nested);\n        return 0;\n    \}\n    if (strcmp(word, \"seek\") == 0) \{\n        if (fseek(stdin, 1000L, SEEK_SET) == 0) return 7;\n        printf(\"unseekable\\n\");\n        return 0;\n    \}\n    if (strcmp(word, \"shape\") == 0) \{\n        FILE *g = fopen(\"shape.bin\", \"ab\");\n        fwrite(\"x\", 1, 1, g);\n        long size = ftell(g);\n        fclose(g);\n        if (size > 1) printf(\"Lua warning: #time difference from previous test: +5.0%%\\n\");\n        printf(size > 1 ? \"time: 0.000643 (-0.000643)\\n\" : \"time: 2.7e-05 (+2.7e-05)\\n\");\n        return 0;\n    \}\n    printf(\"%s %d %ld\\n\", word, lua_answer(), (long)clock() + (long)time(0));\n    return 0;\n\}\n"

// a stand-in root whose interpreter is `LUA_SUITE_C` and whose test folder holds `scripts`, each
// a file name of the suite and the word its script holds
def private suite_root(name : string; scripts : array<tuple<string; string>>) : string {
    let root = stand_in_root(name, LOBJECT)
    fwrite(path_join(root, "lua/fetch/lua-5.4.8/src/lua.c"), LUA_SUITE_C)
    let tests = path_join(root, "lua/fetch/lua-5.4.8-tests")
    mkdir_rec(tests)
    for (script in scripts) {
        fwrite(path_join(tests, script._0), "{script._1}\n")
    }
    return root
}

[test]
def test_suite_check(t : T?) {
    t |> run("--suite-check runs each file of the suite with both builds, capped and timed, and writes a verdict per file: pass, fail with the first difference, timeout, memory, oracle, missing") @(t : T?) {
        let root = suite_root("c2das_lua_suite", [("pm.lua", "hello"), ("db.lua", "shape"), ("math.lua", "runs"), ("sort.lua", "spin"), ("gc.lua", "grow"), ("tpack.lua", "oracle")])
        var out : string
        t |> equal(run_in(root, daslang_argv("lua/run.das", ["--suite-check", "--filter", "lua", "--layout", "single", "--suite-timeout", "5", "--suite-memory", "1G"]), out), 1, out)
        let suite = fread(path_join(root, "lua/work/single/suite.txt"))
        let lines <- split(suite, "\n")
        t |> equal(length(lines), 31, suite)
        t |> equal(lines[0], "main.lua missing 0.0", suite)
        // the digits of `hello`'s line differ from run to run, which the comparison ignores
        t |> success(find_index_if(lines, $(line) => line |> starts_with("pm.lua pass ")) >= 0, suite)
        // a number in another notation and sign, and the time warning of the later run, compare equal
        t |> success(find_index_if(lines, $(line) => line |> starts_with("db.lua pass ")) >= 0, suite)
        t |> success(suite |> contains("math.lua fail ") && suite |> contains(" line 1: native `x`, interp `xx`\n"), suite)
        // the native build counts in time, the converted one past it
        t |> success(suite |> contains("sort.lua timeout ") && suite |> contains(" timeout interp past 5 s\n"), suite)
        // the native build is killed at the cap, and the converted one is not run; the cap is 1G, not
        // less, because under the prlimit tier it bounds the address space, and daslang with the
        // modules loaded aborts under 256M
        t |> success(suite |> contains("gc.lua memory ") && suite |> contains(" memory native over 1G\n"), suite)
        // the native build fails on its own: no pass by agreement, the converted one is not run, and
        // the verdict quotes the first line of the native stderr
        t |> success(suite |> contains("tpack.lua oracle ") && suite |> contains(" native exited 5: broken\n"), suite)
        t |> success(out |> contains("lua: suite under interp (single): 2 pass, 1 fail, 1 timeout, 1 memory, 1 oracle, 24 missing of 30 files in "), out)
        rmdir_rec(root)
    }
    t |> run("--suite-check compares stdout and stderr apart: the same line on the other stream fails, naming the stream") @(t : T?) {
        let root = suite_root("c2das_lua_suite_stream", [("pm.lua", "stream")])
        var out : string
        t |> equal(run_in(root, daslang_argv("lua/run.das", ["--suite-check", "--suite-filter", "pm.lua", "--filter", "lua", "--layout", "single"]), out), 1, out)
        let suite = fread(path_join(root, "lua/work/single/suite.txt"))
        t |> success(suite |> starts_with("pm.lua fail ") && suite |> contains(" stdout line 1: native ``, interp `streamed`\n"), suite)
        rmdir_rec(root)
    }
    t |> run("--suite-port sets the global `_port` each test file gets, true by default") @(t : T?) {
        let root = suite_root("c2das_lua_suite_port", [("pm.lua", "port")])
        var out : string
        t |> equal(run_in(root, daslang_argv("lua/run.das", ["--suite-check", "--suite-filter", "pm.lua", "--suite-port", "false", "--filter", "lua", "--layout", "single"]), out), 0, out)
        t |> success(fread(path_join(root, "lua/work/single/suite.txt")) |> starts_with("pm.lua pass "), out)
        // under the default the stand-in sees `_port=true` and fails natively
        t |> equal(run_in(root, daslang_argv("lua/run.das", ["--suite-check", "--suite-filter", "pm.lua", "--filter", "lua", "--layout", "single"]), out), 1, out)
        let suite = fread(path_join(root, "lua/work/single/suite.txt"))
        t |> success(suite |> starts_with("pm.lua oracle ") && suite |> contains(" native exited 6\n"), suite)
        rmdir_rec(root)
    }
    t |> run("--suite-filter runs one file under the interpreter and the JIT, passing; a file outside the suite and a cap no tier applies are refused") @(t : T?) {
        let root = suite_root("c2das_lua_suite_one", [("pm.lua", "hello")])
        for (tier in ["interp", "jit"]) {
            var out : string
            t |> equal(run_in(root, daslang_argv("lua/run.das", ["--suite-check", "--suite-filter", "pm.lua", "--tier", tier, "--filter", "lua", "--layout", "source"]), out), 0, out)
            t |> success(out |> contains("lua: suite under {tier} (source): 1 pass, 0 fail, 0 timeout, 0 memory, 0 oracle, 0 missing of 1 files in "), out)
            t |> success(fread(path_join(root, "lua/work/source/suite.txt")) |> starts_with("pm.lua pass "))
        }
        var out : string
        t |> equal(run_in(root, daslang_argv("lua/run.das", ["--suite-check", "--suite-filter", "heavy.lua"]), out), 1, out)
        t |> success(out |> contains("--suite-filter names a file of the suite, not `heavy.lua`"), out)
        t |> equal(run_in(root, daslang_argv("lua/run.das", ["--suite-check", "--suite-port", "maybe"]), out), 1, out)
        t |> success(out |> contains("--suite-port is true or false, not `maybe`"), out)
        t |> equal(run_in(root, daslang_argv("lua/run.das", ["--suite-check", "--suite-memory", "lots"]), out), 1, out)
        t |> success(out |> contains("MemoryMax=lots") && out |> contains("which fails") && out |> contains("not `lots`"), out)
        rmdir_rec(root)
    }
}

// `root/shim`, holding a stand-in for each of `commands` that refuses whatever it is asked: the
// folder, to lead the lane's `PATH`
def private refusing_shims(root : string; commands : array<string>) : string {
    let dir = path_join(root, "shim")
    mkdir_rec(dir)
    var out : string
    for (command in commands) {
        let path = path_join(dir, command)
        fwrite(path, "#!/bin/sh\necho \"$0: refused\" >&2\nexit 1\n")
        run_and_capture(["chmod", "+x", path], out, 30.0)
    }
    return dir
}

// `root/shim_user`, holding a `systemd-run` that refuses a system scope and runs a user scope's
// command uncapped, as a manager would for a user with one of its own: the folder
def private user_scope_shim(root : string) : string {
    let dir = path_join(root, "shim_user")
    mkdir_rec(dir)
    let path = path_join(dir, "systemd-run")
    fwrite(path, "#!/bin/sh\n[ \"$1\" = --user ] || \{ echo \"$0: refused\" >&2; exit 1; \}\nwhile [ \"$1\" != --quiet ]; do shift; done\nshift\nexec \"$@\"\n")
    var out : string
    run_and_capture(["chmod", "+x", path], out, 30.0)
    return dir
}

// `argv` run with `dir` leading its `PATH`
def private with_path(dir : string; argv : array<string>) : array<string> {
    var shell <- ["sh", "-c", "PATH=\"$0:$PATH\"; export PATH; exec \"$@\"", dir]
    shell |> push_from(argv)
    return <- shell
}

[test]
def test_suite_cap(t : T?) {
    t |> run("--suite-check caps each run with a system scope, else a user scope, else prlimit's address-space limit, as on a runner without root, under which a run out of memory says so and gets the memory verdict; a cap none of them applies, or past int64, refuses the lane") @(t : T?) {
        let root = suite_root("c2das_lua_suite_cap", [("pm.lua", "hello"), ("gc.lua", "grow")])
        var out : string
        // the manager refuses a system scope and gives a user scope
        t |> equal(run_in(root, with_path(user_scope_shim(root), daslang_argv("lua/run.das", ["--suite-check", "--suite-filter", "pm.lua", "--filter", "lua", "--layout", "single"])), out), 0, out)
        t |> success(out |> contains("caps each run with `systemd-run --user --scope --collect -p MemoryMax=4G"), out)
        // the manager refuses every scope (as it does a user without root): the address-space limit
        t |> equal(run_in(root, with_path(refusing_shims(root, ["systemd-run"]), daslang_argv("lua/run.das", ["--suite-check", "--filter", "lua", "--layout", "single", "--suite-memory", "1G"])), out), 1, out)
        t |> success(out |> contains("caps each run with `prlimit --as=1073741824 --`"), out)
        let suite = fread(path_join(root, "lua/work/single/suite.txt"))
        t |> success(suite |> contains("pm.lua pass ") && suite |> contains("gc.lua memory ") && suite |> contains(" memory native over 1G\n"), suite)
        // prlimit refusing too: no cap, so no run, every attempt named
        t |> equal(run_in(root, with_path(refusing_shims(root, ["systemd-run", "prlimit"]), daslang_argv("lua/run.das", ["--suite-check", "--suite-filter", "pm.lua", "--filter", "lua", "--layout", "source", "--suite-memory", "4096M"])), out), 1, out)
        t |> success(out |> contains("`systemd-run --user --scope --collect -p MemoryMax=4096M -p MemorySwapMax=0 --quiet true`, which fails: ") && out |> contains("`prlimit --as=4294967296 -- true`, which fails: ") && out |> contains("/shim/prlimit: refused"), out)
        t |> success(!fexist(path_join(root, "lua/work/source/suite.txt")), out)
        // a count past int64 is no byte count
        t |> equal(run_in(root, with_path(refusing_shims(root, ["systemd-run"]), daslang_argv("lua/run.das", ["--suite-check", "--suite-memory", "10000000T"])), out), 1, out)
        t |> success(out |> contains("not `10000000T`"), out)
        rmdir_rec(root)
    }
}

[test]
def test_suite_environment(t : T?) {
    t |> run("--suite-check gives each run a stdin that does not seek, as files.lua's invalid-seek check expects of a pipe") @(t : T?) {
        let root = suite_root("c2das_lua_suite_seek", [("files.lua", "seek")])
        var out : string
        t |> equal(run_in(root, daslang_argv("lua/run.das", ["--suite-check", "--suite-filter", "files.lua", "--filter", "lua", "--layout", "single"]), out), 0, out)
        let suite = fread(path_join(root, "lua/work/single/suite.txt"))
        t |> success(suite |> starts_with("files.lua pass "), suite)
        rmdir_rec(root)
    }
    t |> run("--suite-check puts a `lua` on each side's PATH: the native oracle for the native run, the converted interpreter under the tier for the converted one") @(t : T?) {
        let root = suite_root("c2das_lua_suite_launch", [("main.lua", "launch"), ("self.lua", "self")])
        var out : string
        t |> equal(run_in(root, daslang_argv("lua/run.das", ["--suite-check", "--suite-filter", "main.lua", "--filter", "lua", "--layout", "single"]), out), 0, out)
        let suite = fread(path_join(root, "lua/work/single/suite.txt"))
        t |> success(suite |> starts_with("main.lua pass "), suite)
        t |> success(fread(path_join(root, "lua/work/single/bin/lua")) |> contains("/lua/work/single/lua/lua.das' '--' \"$@\""), out)
        // a file where the launcher's folder goes: refused before any run
        mkdir_rec(path_join(root, "lua/work/scc"))
        fwrite(path_join(root, "lua/work/scc/bin"), "")
        t |> equal(run_in(root, daslang_argv("lua/run.das", ["--suite-check", "--suite-filter", "main.lua", "--filter", "lua", "--layout", "scc"]), out), 1, out)
        t |> success(out |> contains("cannot write the suite's `lua` launchers") && !fexist(path_join(root, "lua/work/scc/suite.txt")), out)
        // a file where the native link's folder goes: refused as well
        rmdir_rec(path_join(root, "lua/work/native_bin"))
        fwrite(path_join(root, "lua/work/native_bin"), "")
        t |> equal(run_in(root, daslang_argv("lua/run.das", ["--suite-check", "--suite-filter", "main.lua", "--filter", "lua", "--layout", "single"]), out), 1, out)
        t |> success(out |> contains("cannot write the suite's `lua` launchers"), out)
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
