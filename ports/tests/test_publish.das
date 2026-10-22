options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost

//! `ports/publish.das` without the release: a scratch c2das-re root holding a stand-in
//! `lua/work` (a small C program and a hand-written das module in place of the composed and
//! converted Lua), a stand-in `lua.h` with a license block and a stand-in harness, committed in
//! its own git repository; a bare repository cloned as the ports clone.

let GIT_ID <- ["-c", "user.name=test", "-c", "user.email=test@example.invalid"]
let A_HASH = "1111111111111111111111111111111111111111111111111111111111111111"
let B_HASH = "2222222222222222222222222222222222222222222222222222222222222222"
let VERSIONS = "# pins\nlua: 5.9.1 (the release https://example.invalid/lua-5.9.1.tar.gz (sha256 {A_HASH}) and its test suite https://example.invalid/lua-5.9.1-tests.tar.gz (sha256 {B_HASH}))\n"
let LUA_H = "#ifndef lua_h\n/******\n* Copyright (C) 1994-2025 Stand-in.\n*\n* Permission is hereby granted.\n* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.\n******/\n#endif\n"

// the stand-in interpreter: its last argument, except `spectral_norm.lua` which fails
let LUA_C = "#include <stdio.h>\n#include <string.h>\nint main(int argc, char **argv) \{\n    const char *last = argv[argc - 1];\n    if (strstr(last, \"spectral_norm.lua\")) return 1;\n    printf(\"%s\\n\", last);\n    return 0;\n\}\n"

// the stand-in conversion: what the C prints, except a different line for `nbody.lua`, exit 2
// for `binary_trees.lua`, and a different line for `all.lua`, whose row compares exit codes alone
let LUA_DAS = "options gen2\nrequire strings\nrequire daslib/strings_boost\n[export]\ndef main : int \{\n    let argv <- get_command_line_arguments()\n    let last = argv[length(argv) - 1]\n    if (last |> ends_with(\"binary_trees.lua\")) \{\n        return 2\n    \}\n    let shown = last |> ends_with(\"nbody.lua\") ? \"drift\" : last == \"all.lua\" ? \"ALL\" : last\n    print(\"\{shown\}\\n\")\n    return 0\n\}\n"

def private run_in(dir : string; argv : array<string>; var out : string&) : int {
    var shell <- ["sh", "-c", "cd \"$0\" && exec \"$@\"", dir]
    shell |> push_from(argv)
    return run_and_capture(shell, out, 1200.0)
}

def private git(dir : string; argv : array<string>) : string {
    var full <- ["git", "-C", dir]
    full |> push_from(GIT_ID, argv)
    var out : string
    run_and_capture(full, out, 60.0)
    return strip(out)
}

def private publish_argv(args : array<string>) : array<string> {
    var argv <- [get_das_root() + "/bin/daslang", "-load_module", get_full_file_name("dasCRuntime"), "-load_module", get_full_file_name("c_runtime"), get_full_file_name("ports/publish.das"), "--"]
    argv |> push_from(args)
    return <- argv
}

def private publish(root : string; args : array<string>; var out : string&) : int => run_in(root, publish_argv(args), out)

// `--no-convert` under `env` with `setting`
def private with_env(setting : array<string>) : array<string> {
    var argv <- ["env"]
    argv |> push_from(setting, publish_argv(["--no-convert"]))
    return <- argv
}

// a committed scratch c2das-re root: the module folders linked, the stand-in release, harness
// and work tree, and the benchmark scripts copied
def private stand_in_root(name : string) : string {
    var dir_error : string
    let root = create_temp_directory(name, dir_error)
    if (!empty(dir_error)) {
        return ""
    }
    var out : string
    for (folder in ["c_runtime", "dasCRuntime"]) {
        run_and_capture(["ln", "-s", get_full_file_name(folder), path_join(root, folder)], out, 30.0)
    }
    fwrite(path_join(root, "VERSIONS.md"), VERSIONS)
    mkdir_rec(path_join(root, "lua/fetch/lua-5.9.1/src"))
    mkdir_rec(path_join(root, "lua/fetch/lua-5.9.1-tests"))
    fwrite(path_join(root, "lua/fetch/lua-5.9.1/src/lua.h"), LUA_H)
    fwrite(path_join(root, "lua/fetch/lua-5.9.1-tests/all.lua"), "-- stand-in\n")
    fwrite(path_join(root, "lua/lua.c2das"), "\{\"defines\": [\"STAND_IN=1\"]\}\n")
    fwrite(path_join(root, "lua/fetch.sh"), "echo fetched\n")
    fwrite(path_join(root, "lua/run.das"), "options gen2\n[export]\ndef main : int \{\n    to_log(LOG_WARNING, \"lua: lua_all: dumper 1.0 s, JSON 10 bytes\\n\")\n    return 0\n\}\n")
    for (stem in ["lua_all", "luac_all"]) {
        mkdir_rec(path_join(root, "lua/work/{stem}"))
        fwrite(path_join(root, "lua/work/{stem}/{stem}.das"), stem == "lua_all" ? LUA_DAS : "// {stem}\n")
    }
    fwrite(path_join(root, "lua/work/lua_all.c"), LUA_C)
    mkdir_rec(path_join(root, "ports/lua/bench"))
    for (bench in ["fib", "binary_trees", "nbody", "spectral_norm"]) {
        fwrite(path_join(root, "ports/lua/bench/{bench}.lua"), fread("ports/lua/bench/{bench}.lua"))
    }
    fwrite(path_join(root, ".gitignore"), "/lua/work/bench/\n/lua/work/publish_run.log\n.cache/\n.jitted_scripts/\n/clone/\n/ports.git/\n/plain/\n")
    git(root, ["init", "-q"])
    git(root, ["add", "-A"])
    git(root, ["commit", "-q", "-m", "stand-in"])
    git(root, ["tag", "v9.9.9"])
    return root
}

// a bare repository with the charter README, and its clone: the clone's path
def private ports_clone(root : string) : string {
    let bare = path_join(root, "ports.git")
    let clone = path_join(root, "clone")
    var out : string
    run_and_capture(["git", "init", "-q", "--bare", bare], out, 60.0)
    run_and_capture(["git", "clone", "-q", bare, clone], out, 60.0)
    fwrite(path_join(clone, "README.md"), "# ports\n\nThe charter.\n")
    git(clone, ["add", "README.md"])
    git(clone, ["commit", "-q", "-m", "charter"])
    git(clone, ["push", "-q", "origin", "HEAD"])
    return clone
}

[test]
def test_refusals(t : T?) {
    t |> run("an unknown program, an unknown lane, --push without --commit, and a directory that is no clone") @(t : T?) {
        let root = stand_in_root("c2das_ports_refusals")
        t |> success(!empty(root))
        let clone = ports_clone(root)
        var out : string
        t |> equal(publish(root, ["--repo", clone, "--program", "doom"], out), 1, out)
        t |> success(out |> contains("no program `doom`; the publisher knows lua"), out)
        t |> equal(publish(root, ["--repo", clone, "--lanes", "interp,llvm"], out), 1, out)
        t |> success(out |> contains("no das lane `llvm`"), out)
        t |> equal(publish(root, ["--repo", clone, "--lanes", "native"], out), 1, out)
        t |> success(out |> contains("no das lane `native`"), out)
        t |> equal(publish(root, ["--repo", clone, "--push"], out), 1, out)
        t |> success(out |> contains("--push needs --commit"), out)
        let plain = path_join(root, "plain")
        mkdir_rec(plain)
        t |> equal(publish(root, ["--repo", plain, "--no-convert"], out), 1, out)
        t |> success(out |> contains("is no clone of the ports repository"), out)
        // a folder inside a work tree is not the top of one
        mkdir_rec(path_join(clone, "sub"))
        t |> equal(publish(root, ["--repo", path_join(clone, "sub"), "--no-convert"], out), 1, out)
        t |> success(out |> contains("is no clone of the ports repository"), out)
        rmdir_rec(root)
    }
    t |> run("the clone defaults to $C2DAS_PORTS, else ../c2das-ports") @(t : T?) {
        let root = stand_in_root("c2das_ports_env")
        let clone = ports_clone(root)
        var out : string
        let plain = path_join(root, "plain")
        t |> equal(run_in(root, with_env(["C2DAS_PORTS={plain}"]), out), 1, out)
        t |> success(out |> contains("{plain} is no clone"), out)
        t |> equal(run_in(root, with_env(["C2DAS_PORTS={clone}"]), out), 0, out)
        t |> success(fexist(path_join(clone, "lua/README.md")), out)
        // without the variable, the clone beside the root
        t |> equal(run_in(root, with_env(["-u", "C2DAS_PORTS"]), out), 1, out)
        t |> success(out |> contains("../c2das-ports is no clone"), out)
        rmdir_rec(root)
    }
    t |> run("a dirty c2das-re tree without --allow-dirty, and a root that is no git tree") @(t : T?) {
        let root = stand_in_root("c2das_ports_dirty")
        let clone = ports_clone(root)
        fwrite(path_join(root, "VERSIONS.md"), VERSIONS + "# edited\n")
        var out : string
        t |> equal(publish(root, ["--repo", clone, "--no-convert"], out), 1, out)
        t |> success(out |> contains("uncommitted changes; commit them or pass --allow-dirty"), out)
        t |> equal(publish(root, ["--repo", clone, "--no-convert", "--allow-dirty"], out), 0, out)
        t |> success(fread(path_join(clone, "lua/README.md")) |> contains("-dirty"), out)
        run_and_capture(["mv", path_join(root, ".git"), path_join(root, "git.moved")], out, 30.0)
        t |> equal(publish(root, ["--repo", clone, "--no-convert", "--allow-dirty"], out), 1, out)
        t |> success(out |> contains("run from the c2das-re checkout"), out)
        rmdir_rec(root)
    }
    t |> run("no VERSIONS.md pin, no converted module, no license block") @(t : T?) {
        let root = stand_in_root("c2das_ports_inputs")
        let clone = ports_clone(root)
        let args <- ["--repo", clone, "--no-convert", "--allow-dirty"]
        var out : string
        fwrite(path_join(root, "VERSIONS.md"), "# no pin\n")
        t |> equal(publish(root, args, out), 1, out)
        t |> success(out |> contains("VERSIONS.md names no `lua:` line"), out)
        fwrite(path_join(root, "VERSIONS.md"), VERSIONS)
        fwrite(path_join(root, "lua/fetch/lua-5.9.1/src/lua.h"), "int x;\n")
        t |> equal(publish(root, args, out), 1, out)
        t |> success(out |> contains("lua/fetch/lua-5.9.1/src/lua.h holds no license block"), out)
        remove(path_join(root, "lua/work/luac_all/luac_all.das"))
        t |> equal(publish(root, args, out), 1, out)
        t |> success(out |> contains("no lua/work/luac_all/luac_all.das; run without --no-convert"), out)
        rmdir_rec(root)
    }
}

[test]
def test_publish_commit_push(t : T?) {
    t |> run("--no-convert --commit writes the fixed set and commits it; a second run commits nothing; --push pushes") @(t : T?) {
        let root = stand_in_root("c2das_ports_publish")
        let clone = ports_clone(root)
        var out : string
        t |> equal(publish(root, ["--repo", clone, "--no-convert", "--commit"], out), 0, out)
        let dir = path_join(clone, "lua")
        t |> equal(fread(path_join(dir, "lua.c2das")), fread(path_join(root, "lua/lua.c2das")))
        t |> equal(fread(path_join(dir, "lua_all.das")), LUA_DAS)
        t |> equal(fread(path_join(dir, "luac_all.das")), "// luac_all\n")
        t |> equal(fread(path_join(dir, "bench/nbody.lua")), fread("ports/lua/bench/nbody.lua"))
        // without --perf nothing is measured
        t |> success(!stat(path_join(dir, "perf")).is_dir)
        let license = fread(path_join(dir, "LICENSE"))
        t |> success(license |> starts_with("Copyright (C) 1994-2025 Stand-in.\n\nPermission"), license)
        t |> success(license |> ends_with("DEALINGS IN THE SOFTWARE.\n"), license)
        let sha = git(root, ["rev-parse", "HEAD"])
        let readme = fread(path_join(dir, "README.md"))
        for (fact in ["# lua\n\nLua 5.9.1 converted", A_HASH, B_HASH, "https://example.invalid/lua-5.9.1-tests.tar.gz", "c2das-re `v9.9.9` (`{sha}`", "`scripts/publish_ports.sh --program lua --no-convert`", "luac_all.das -- -o out.luac", "a conversion that left no harness log", "- `bench/` - the benchmark scripts the perf tables will run.\n\n## Source", "## Performance\n\nnot yet: the perf method audit (ledger item C, p-perf-method) comes first; the tables are rendered from captures by this publisher once it lands\n"]) {
            t |> success(readme |> contains(fact), "README lacks {fact}:\n{readme}")
        }
        let top = fread(path_join(clone, "README.md"))
        t |> success(top |> starts_with("# ports\n\nThe charter.\n\n<!-- generated below"), top)
        t |> success(top |> ends_with("## Programs\n\nnot yet: the perf method audit (ledger item C, p-perf-method) comes first; the tables are rendered from captures by this publisher once it lands\n"), top)
        t |> equal(git(clone, ["log", "-1", "--format=%s %an"]), "lua: regenerated from c2das-re v9.9.9 ({sha}) lookibed")
        t |> equal(git(clone, ["status", "--porcelain"]), "")
        let head = git(clone, ["rev-parse", "HEAD"])
        t |> equal(publish(root, ["--repo", clone, "--no-convert", "--commit"], out), 0, out)
        t |> success(out |> contains("lua: nothing to commit"), out)
        t |> equal(git(clone, ["rev-parse", "HEAD"]), head)
        t |> equal(git(path_join(root, "ports.git"), ["rev-parse", "HEAD"]) == head, false)
        t |> equal(publish(root, ["--repo", clone, "--no-convert", "--commit", "--push"], out), 0, out)
        t |> equal(git(path_join(root, "ports.git"), ["rev-parse", "HEAD"]), head)
        rmdir_rec(root)
    }
}

[test]
def test_convert(t : T?) {
    t |> run("without --no-convert: fetch.sh and the harness run, the harness's report in the README") @(t : T?) {
        let root = stand_in_root("c2das_ports_convert")
        let clone = ports_clone(root)
        var out : string
        t |> equal(publish(root, ["--repo", clone], out), 0, out)
        let readme = fread(path_join(clone, "lua/README.md"))
        t |> success(readme |> contains("```\n[W] lua: lua_all: dumper 1.0 s, JSON 10 bytes\n```"), readme)
        t |> success(fread(path_join(root, "lua/work/publish_run.log")) |> contains("lua: lua_all: dumper"), out)
        // the log stays for a later --no-convert publish
        t |> equal(publish(root, ["--repo", clone, "--no-convert"], out), 0, out)
        t |> success(fread(path_join(clone, "lua/README.md")) |> contains("dumper 1.0 s"), out)
        rmdir_rec(root)
    }
    t |> run("a failed fetch and a failed conversion stop the publish") @(t : T?) {
        let root = stand_in_root("c2das_ports_convert_fails")
        let clone = ports_clone(root)
        fwrite(path_join(root, "lua/fetch.sh"), "echo no network\nexit 1\n")
        var out : string
        t |> equal(publish(root, ["--repo", clone, "--allow-dirty"], out), 1, out)
        t |> success(out |> contains("lua: lua/fetch.sh failed: no network"), out)
        fwrite(path_join(root, "lua/fetch.sh"), "exit 0\n")
        fwrite(path_join(root, "lua/run.das"), "options gen2\n[export]\ndef main : int \{\n    return 1\n\}\n")
        t |> equal(publish(root, ["--repo", clone, "--allow-dirty"], out), 1, out)
        t |> success(out |> contains("lua: the conversion exited 1; lua/work/publish_run.log holds its log"), out)
        t |> success(!fexist(path_join(clone, "lua/README.md")), out)
        rmdir_rec(root)
    }
}

// the capture a bench run wrote into the clone, "" for none
def private capture_text(clone : string) : string {
    var text = ""
    dir(path_join(clone, "lua/perf")) $(name) {
        if (name |> ends_with(".json")) {
            text = fread(path_join(clone, "lua/perf/{name}"))
        }
    }
    return text
}

[test]
def test_bench(t : T?) {
    t |> run("a bench run: every workload under every lane, a das cell standing only on the native output and exit code") @(t : T?) {
        let root = stand_in_root("c2das_ports_bench")
        let clone = ports_clone(root)
        var out : string
        t |> equal(publish(root, ["--repo", clone, "--no-convert", "--perf", "--samples", "2", "--lanes", "interp,jit,exe,aot", "--commit"], out), 0, out)
        let written = capture_text(clone)
        t |> success(written |> contains("\"program\" : \"lua\""), written)
        let readme = fread(path_join(clone, "lua/README.md"))
        // a standing cell has a time in every lane but the AOT's, which the tier refuses
        t |> success(readme |> contains("| fib "), readme)
        for (fact in ["- `perf/capture_*.json` - every capture", "Captured ", " runs of the whole program", "- AOT, every workload: not yet: the build exited -1 and left no binary: the aot tier's host passes the program no arguments", "- binary_trees, interpreter: not yet: exited 2 where the native build exits 0\n", "- nbody, JIT: not yet: prints `drift` where the native build prints `", "- spectral_norm, clang -O3: not yet: exited 1\n", "- spectral_norm, exe: not yet: no native run to compare with", "- clang -O3: `"]) {
            t |> success(readme |> contains(fact), "README lacks {fact}:\n{readme}")
        }
        // a sample ends with the program's output, not with popen's 100 ms watchdog tick; the times
        // table comes first
        let startup = [for (ln in split(readme, "\n")); ln; where ln |> starts_with("| startup ")]
        t |> success(!empty(startup) && startup[0] |> contains(" 0.00"), readme)
        // the test-suite row compares the exit code alone, so `ALL` against `all.lua` stands
        t |> success(!(readme |> contains("- test suite, ")), readme)
        let top = fread(path_join(clone, "README.md"))
        t |> success(top |> contains("| [lua](lua/README.md) |"), top)
        t |> success(top |> contains("not yet |\n"), top)
        t |> equal(git(clone, ["status", "--porcelain"]), "")
        rmdir_rec(root)
    }
    t |> run("a missing test-suite folder, a native build that fails, a JIT warm-up that fails, a sample past --timeout") @(t : T?) {
        let root = stand_in_root("c2das_ports_bench_fails")
        let clone = ports_clone(root)
        let args <- ["--repo", clone, "--no-convert", "--perf", "--samples", "1", "--lanes", "interp", "--allow-dirty"]
        var out : string
        rmdir_rec(path_join(root, "lua/fetch/lua-5.9.1-tests"))
        t |> equal(publish(root, args, out), 0, out)
        var readme = fread(path_join(clone, "lua/README.md"))
        t |> success(readme |> contains("- test suite, clang -O3: not yet: no lua/fetch/lua-5.9.1-tests"), readme)
        t |> success(readme |> contains("- test suite, interpreter: not yet: no native run to compare with"), readme)
        fwrite(path_join(root, "lua/work/lua_all.c"), "#include <unistd.h>\nint main(void) \{ sleep(5); return 0; \}\n")
        t |> equal(publish(root, ["--repo", clone, "--no-convert", "--perf", "--samples", "1", "--lanes", "interp", "--allow-dirty", "--timeout", "1"], out), 0, out)
        readme = fread(path_join(clone, "lua/README.md"))
        t |> success(readme |> contains("- startup, clang -O3: not yet: timed out after 1 s"), readme)
        fwrite(path_join(root, "lua/work/lua_all.c"), "int main(void) \{ return not_c; \}\n")
        fwrite(path_join(root, "lua/work/lua_all/lua_all.das"), "options gen2\n[export]\ndef main : int \{\n    return 3\n\}\n")
        t |> equal(publish(root, ["--repo", clone, "--no-convert", "--perf", "--samples", "1", "--lanes", "jit", "--allow-dirty"], out), 0, out)
        readme = fread(path_join(clone, "lua/README.md"))
        t |> success(readme |> contains("- clang -O3, every workload: not yet: the build failed: "), readme)
        t |> success(readme |> contains("- JIT, every workload: not yet: the warm-up run exited 3"), readme)
        rmdir_rec(root)
    }
}
