options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require daslib/json_boost
require ../ports_render.das

//! `ports/publish.das` without the release: a scratch c2das-re root holding a stand-in
//! `lua/work` (a small C program and a hand-written das module in place of the composed and
//! converted Lua, with the conversion's stamp), a stand-in `lua.h` with a license block and a
//! stand-in harness, committed in its own git repository; a bare repository cloned as the ports
//! clone.

let GIT_ID <- ["-c", "user.name=test", "-c", "user.email=test@example.invalid"]
let A_HASH = "1111111111111111111111111111111111111111111111111111111111111111"
let B_HASH = "2222222222222222222222222222222222222222222222222222222222222222"
let OTHER_SHA = "0123456789012345678901234567890123456789"
let VERSIONS = "# pins\nlua: 5.9.1 (the release https://example.invalid/lua-5.9.1.tar.gz (sha256 {A_HASH}) and its test suite https://example.invalid/lua-5.9.1-tests.tar.gz (sha256 {B_HASH}))\n"
let LUA_H = "#ifndef lua_h\n/******\n* Copyright (C) 1994-2025 Stand-in.\n*\n* Permission is hereby granted.\n* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.\n******/\n#endif\n"

// the stand-in interpreter: its last argument, except `spectral_norm.lua` which fails and
// `all.lua`, which must be in the working folder
let LUA_C = "#include <stdio.h>\n#include <string.h>\nint main(int argc, char **argv) \{\n    const char *last = argv[argc - 1];\n    if (strstr(last, \"spectral_norm.lua\")) return 1;\n    if (strcmp(last, \"all.lua\") == 0) \{\n        FILE *f = fopen(\"all.lua\", \"r\");\n        if (!f) return 1;\n        fclose(f);\n    \}\n    printf(\"%s\\n\", last);\n    return 0;\n\}\n"

// the stand-in conversion: an `info` line, then what the C prints, except an exception line and a
// trailer with exit 2 for `binary_trees.lua`, another first line for `nbody.lua`, and `ALL` for
// `all.lua`, whose row compares exit codes alone; every run counts itself in `runs_<lane>.log` of
// its working folder
let LUA_DAS = "options gen2\nrequire strings\nrequire daslib/strings_boost\nrequire daslib/fio\ndef count_run(argv : array<string>) \{\n    let lane = has_value(argv, \"-jit\") ? \"jit\" : argv[0] |> ends_with(\"_exe.exe\") || argv[0] |> ends_with(\"_exe\") ? \"exe\" : \"interp\"\n    fopen(\"runs_\{lane\}.log\", \"ab\") $(f) \{\n        if (f != null) \{\n            fwrite(f, \"run\\n\")\n        \}\n    \}\n\}\n[export]\ndef main : int \{\n    let argv <- get_command_line_arguments()\n    count_run(argv)\n    let last = argv[length(argv) - 1]\n    print(\"[I] stand-in\\n\")\n    if (last |> ends_with(\"binary_trees.lua\")) \{\n        print(\"EXCEPTION: boom\\ntrailer\\n\")\n        return 2\n    \}\n    if (last == \"all.lua\" && !fexist(\"all.lua\")) \{\n        return 1\n    \}\n    if (last |> ends_with(\"nbody.lua\")) \{\n        print(\"drift\\n\{last\}\\n\")\n        return 0\n    \}\n    print(\"\{last == \"all.lua\" ? \"ALL\" : last\}\\n\")\n    return 0\n\}\n"

// the stand-in harness: its report with seconds that differ on every run, a line of seconds
// alone, and clauses ending in ` s` that are no seconds
let RUN_DAS = "options gen2\n[export]\ndef main : int \{\n    to_log(LOG_WARNING, \"lua: lua_all: dumper \{ref_time_ticks()\} s, JSON 10 bytes\\n\")\n    to_log(LOG_WARNING, \"lua: lua_all: emitter 0.\{ref_time_ticks() % 10l\} s, compile check 2.5 s, 3 lines of das\\n\")\n    to_log(LOG_WARNING, \"lua: total 7 s\\n\")\n    to_log(LOG_WARNING, \"lua: lua_all: units of s, dots . s\\n\")\n    return 0\n\}\n"

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

def private stamp_path(root : string) : string => path_join(root, "lua/work/publish.generation")

// a committed scratch c2das-re root: the module folders linked, the stand-in release, harness
// and work tree, and the benchmark scripts copied; the conversion's stamp names its HEAD; ""
// when no temporary directory could be made
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
    fwrite(path_join(root, "lua/run.das"), RUN_DAS)
    for (stem in ["lua_all", "luac_all"]) {
        mkdir_rec(path_join(root, "lua/work/{stem}"))
        fwrite(path_join(root, "lua/work/{stem}/{stem}.das"), stem == "lua_all" ? LUA_DAS : "// {stem}\n")
    }
    fwrite(path_join(root, "lua/work/lua_all.c"), LUA_C)
    mkdir_rec(path_join(root, "ports/lua/bench"))
    for (bench in ["fib", "binary_trees", "nbody", "spectral_norm"]) {
        fwrite(path_join(root, "ports/lua/bench/{bench}.lua"), fread("ports/lua/bench/{bench}.lua"))
    }
    fwrite(path_join(root, ".gitignore"), "/lua/work/bench/\n/lua/work/publish_run.log\n/lua/work/publish.generation\nruns_*.log\n.cache/\n.jitted_scripts/\n/clone/\n/ports.git/\n/plain/\n")
    git(root, ["init", "-q"])
    git(root, ["add", "-A"])
    git(root, ["commit", "-q", "-m", "stand-in"])
    git(root, ["tag", "v9.9.9"])
    fwrite(stamp_path(root), "{git(root, ["rev-parse", "HEAD"])}\nv9.9.9\n{git(root, ["log", "-1", "--format=%cs"])}\n")
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

// the clone as the publish that made `head` left it
def private untouched(t : T?; clone, head, why : string) {
    t |> equal(git(clone, ["status", "--porcelain"]), "", why)
    t |> equal(git(clone, ["rev-parse", "HEAD"]), head, why)
}

// the lines of `path`, 0 for a missing file
def private line_count(path : string) : int => length([for (ln in split(fread(path), "\n")); ln; where !empty(ln)])

[test]
def test_refusals(t : T?) {
    t |> run("-? prints the help and publishes nothing") @(t : T?) {
        var out : string
        t |> equal(run_in(".", publish_argv(["-?"]), out), 0, out)
        t |> success(out |> contains("show this help and exit"), out)
        t |> success(out |> contains("--allow-stale"), out)
    }
    t |> run("an unknown program or lane, --push without --commit, --samples below 1, --timeout of 0, and a directory that is no clone") @(t : T?) {
        let root = stand_in_root("c2das_ports_refusals")
        if (empty(root)) {
            t |> failure("no stand-in root")
            return
        }
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
        t |> equal(publish(root, ["--repo", clone, "--no-convert", "--perf", "--samples", "0"], out), 1, out)
        t |> success(out |> contains("--samples takes a count of 1 or more, not 0"), out)
        t |> equal(publish(root, ["--repo", clone, "--no-convert", "--perf", "--timeout", "0"], out), 1, out)
        t |> success(out |> contains("--timeout takes seconds above 0, not 0"), out)
        let plain = path_join(root, "plain")
        mkdir_rec(plain)
        t |> equal(publish(root, ["--repo", plain, "--no-convert"], out), 1, out)
        t |> success(out |> contains("is no clone of the ports repository"), out)
        // a folder inside a work tree is not the top of one
        mkdir_rec(path_join(clone, "sub"))
        t |> equal(publish(root, ["--repo", path_join(clone, "sub"), "--no-convert"], out), 1, out)
        t |> success(out |> contains("is no clone of the ports repository"), out)
        t |> success(!fexist(path_join(clone, "lua")), "a refused publish wrote into the clone")
        rmdir_rec(root)
    }
    t |> run("the clone defaults to $C2DAS_PORTS, else ../c2das-ports") @(t : T?) {
        let root = stand_in_root("c2das_ports_env")
        if (empty(root)) {
            t |> failure("no stand-in root")
            return
        }
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
}

[test]
def test_tree_refusals(t : T?) {
    t |> run("a dirty c2das-re tree without --allow-dirty; with it the conversion's stamp names -dirty; a root that is no git tree") @(t : T?) {
        let root = stand_in_root("c2das_ports_dirty")
        if (empty(root)) {
            t |> failure("no stand-in root")
            return
        }
        let clone = ports_clone(root)
        fwrite(path_join(root, "VERSIONS.md"), VERSIONS + "# edited\n")
        var out : string
        t |> equal(publish(root, ["--repo", clone], out), 1, out)
        t |> success(out |> contains("uncommitted changes; commit them or pass --allow-dirty"), out)
        t |> equal(publish(root, ["--repo", clone, "--allow-dirty"], out), 0, out)
        t |> success(fread(stamp_path(root)) |> contains("v9.9.9-dirty\n"), out)
        t |> success(fread(path_join(clone, "lua/README.md")) |> contains("Generated by c2das-re `v9.9.9-dirty`"), out)
        run_and_capture(["mv", path_join(root, ".git"), path_join(root, "git.moved")], out, 30.0)
        t |> equal(publish(root, ["--repo", clone, "--no-convert", "--allow-dirty"], out), 1, out)
        t |> success(out |> contains("run from the c2das-re checkout"), out)
        rmdir_rec(root)
    }
}

[test]
def test_input_refusals(t : T?) {
    t |> run("a refused input leaves the clone as the last publish left it: the pin, the stamp, a module, the license block, the sidecar") @(t : T?) {
        let root = stand_in_root("c2das_ports_inputs")
        if (empty(root)) {
            t |> failure("no stand-in root")
            return
        }
        let clone = ports_clone(root)
        var out : string
        t |> equal(publish(root, ["--repo", clone, "--no-convert", "--commit"], out), 0, out)
        let head = git(clone, ["rev-parse", "HEAD"])
        // a changed module, so a refusal that wrote it first would show in the clone
        let lua_all = path_join(root, "lua/work/lua_all/lua_all.das")
        fwrite(lua_all, LUA_DAS + "// changed\n")
        let args <- ["--repo", clone, "--no-convert", "--allow-dirty"]
        let no_pin = "VERSIONS.md names no `lua:` line with the release and the test-suite tarballs"
        fwrite(path_join(root, "VERSIONS.md"), "# no pin\n")
        t |> equal(publish(root, args, out), 1, out)
        t |> success(out |> contains(no_pin), out)
        untouched(t, clone, head, "no pin")
        // one tarball, and three
        fwrite(path_join(root, "VERSIONS.md"), "lua: 5.9.1 (https://example.invalid/lua-5.9.1.tar.gz (sha256 {A_HASH}))\n")
        t |> equal(publish(root, args, out), 1, out)
        t |> success(out |> contains(no_pin), out)
        untouched(t, clone, head, "one tarball")
        fwrite(path_join(root, "VERSIONS.md"), "lua: 5.9.1 (https://a.invalid/a.tar.gz (sha256 {A_HASH}) https://b.invalid/b.tar.gz (sha256 {B_HASH}) https://c.invalid/c.tar.gz (sha256 {A_HASH}))\n")
        t |> equal(publish(root, args, out), 1, out)
        t |> success(out |> contains(no_pin), out)
        untouched(t, clone, head, "three tarballs")
        fwrite(path_join(root, "VERSIONS.md"), VERSIONS)
        let stamp = fread(stamp_path(root))
        fwrite(stamp_path(root), "{OTHER_SHA}\nv0.0.1\n2020-01-01\n")
        t |> equal(publish(root, args, out), 1, out)
        t |> success(out |> contains("lua/work/publish.generation names the conversion at {OTHER_SHA}, the tree is at "), out)
        untouched(t, clone, head, "a stamp of another commit")
        remove(stamp_path(root))
        t |> equal(publish(root, args, out), 1, out)
        t |> success(out |> contains("no lua/work/publish.generation, so no conversion of this tree is recorded; run without --no-convert, or pass --allow-stale"), out)
        untouched(t, clone, head, "no stamp")
        fwrite(stamp_path(root), stamp)
        fwrite(path_join(root, "lua/fetch/lua-5.9.1/src/lua.h"), "int x;\n")
        t |> equal(publish(root, args, out), 1, out)
        t |> success(out |> contains("lua/fetch/lua-5.9.1/src/lua.h holds no license block"), out)
        untouched(t, clone, head, "no license block")
        fwrite(path_join(root, "lua/fetch/lua-5.9.1/src/lua.h"), LUA_H)
        let luac_all = path_join(root, "lua/work/luac_all/luac_all.das")
        remove(luac_all)
        t |> equal(publish(root, args, out), 1, out)
        t |> success(out |> contains("no lua/work/luac_all/luac_all.das; run without --no-convert"), out)
        untouched(t, clone, head, "no luac module")
        fwrite(luac_all, "// luac_all\n")
        remove(path_join(root, "lua/lua.c2das"))
        t |> equal(publish(root, args, out), 1, out)
        t |> success(out |> contains("no lua/lua.c2das"), out)
        untouched(t, clone, head, "no sidecar")
        rmdir_rec(root)
    }
}

[test]
def test_stale(t : T?) {
    t |> run("--allow-stale publishes a stamp of another commit under that commit, and a missing stamp as unrecorded") @(t : T?) {
        let root = stand_in_root("c2das_ports_stale")
        if (empty(root)) {
            t |> failure("no stand-in root")
            return
        }
        let clone = ports_clone(root)
        let sha = git(root, ["rev-parse", "HEAD"])
        var out : string
        fwrite(stamp_path(root), "{OTHER_SHA}\nv0.0.1\n2020-01-01\n")
        t |> equal(publish(root, ["--repo", clone, "--no-convert", "--allow-stale", "--commit"], out), 0, out)
        let readme = fread(path_join(clone, "lua/README.md"))
        t |> success(readme |> contains("- Generated by c2das-re `v0.0.1` (`{OTHER_SHA}`, committed 2020-01-01)\n"), readme)
        t |> success(readme |> contains("`scripts/publish_ports.sh --program lua --no-convert --allow-stale`"), readme)
        t |> equal(git(clone, ["log", "-1", "--format=%s"]), "lua: regenerated from c2das-re v0.0.1 ({OTHER_SHA})")
        remove(stamp_path(root))
        t |> equal(publish(root, ["--repo", clone, "--no-convert", "--allow-stale", "--commit"], out), 0, out)
        let unrecorded = fread(path_join(clone, "lua/README.md"))
        t |> success(unrecorded |> contains("- Generated by c2das-re at an unrecorded commit: published with `--allow-stale` from `v9.9.9` (`{sha}`, committed "), unrecorded)
        t |> equal(git(clone, ["log", "-1", "--format=%s"]), "lua: republished from c2das-re v9.9.9 ({sha}), the conversion's commit unrecorded")
        rmdir_rec(root)
    }
}

[test]
def test_publish_commit_push(t : T?) {
    t |> run("--no-convert --commit writes the fixed set and commits it; a second run commits nothing; --push pushes") @(t : T?) {
        let root = stand_in_root("c2das_ports_publish")
        if (empty(root)) {
            t |> failure("no stand-in root")
            return
        }
        let clone = ports_clone(root)
        var out : string
        t |> equal(publish(root, ["--repo", clone, "--no-convert", "--commit"], out), 0, out)
        let dir = path_join(clone, "lua")
        var names : array<string>
        dir(dir) $(name) {
            if (name != "." && name != "..") {
                names |> push(name)
            }
        }
        names |> sort()
        t |> equal(join(names, " "), "LICENSE README.md bench lua.c2das lua_all.das luac_all.das")
        var benches : array<string>
        dir(path_join(dir, "bench")) $(name) {
            if (name != "." && name != "..") {
                benches |> push(name)
            }
        }
        benches |> sort()
        t |> equal(join(benches, " "), "binary_trees.lua fib.lua nbody.lua spectral_norm.lua")
        t |> equal(fread(path_join(dir, "lua.c2das")), fread(path_join(root, "lua/lua.c2das")))
        t |> equal(fread(path_join(dir, "lua_all.das")), LUA_DAS)
        t |> equal(fread(path_join(dir, "luac_all.das")), "// luac_all\n")
        t |> equal(fread(path_join(dir, "bench/nbody.lua")), fread("ports/lua/bench/nbody.lua"))
        let license = fread(path_join(dir, "LICENSE"))
        t |> success(license |> starts_with("Copyright (C) 1994-2025 Stand-in.\n\nPermission"), license)
        t |> success(license |> ends_with("DEALINGS IN THE SOFTWARE.\n"), license)
        let sha = git(root, ["rev-parse", "HEAD"])
        let readme = fread(path_join(dir, "README.md"))
        for (fact in ["# lua\n\nLua 5.9.1 converted", A_HASH, B_HASH, "https://example.invalid/lua-5.9.1-tests.tar.gz", "- Generated by c2das-re `v9.9.9` (`{sha}`, committed ", "`scripts/publish_ports.sh --program lua --no-convert`", "luac_all.das -- -o out.luac", "The results c2das-re's P5.1 recorded for this program, not results of this publish's run", "a conversion that left no harness log", "- `bench/` - the benchmark scripts the perf tables will run.\n\n## Source", "## Performance\n\nnot yet: the perf method audit (ledger item C, p-perf-method) comes first; the tables are rendered from captures by this publisher once it lands\n"]) {
            t |> success(readme |> contains(fact), "README lacks {fact}:\n{readme}")
        }
        let top = fread(path_join(clone, "README.md"))
        t |> success(top |> starts_with("# ports\n\nThe charter.\n\n<!-- generated below"), top)
        t |> success(top |> ends_with("## Programs\n\nnot yet: the perf method audit (ledger item C, p-perf-method) comes first; the tables are rendered from captures by this publisher once it lands\n"), top)
        t |> equal(git(clone, ["log", "-1", "--format=%s %an"]), "lua: regenerated from c2das-re v9.9.9 ({sha}) lookibed")
        t |> equal(git(clone, ["status", "--porcelain"]), "")
        let head = git(clone, ["rev-parse", "HEAD"])
        t |> equal(publish(root, ["--repo", clone, "--no-convert", "--commit"], out), 0, out)
        t |> equal(git(clone, ["rev-parse", "HEAD"]), head)
        t |> equal(git(path_join(root, "ports.git"), ["rev-parse", "HEAD"]) == head, false)
        t |> equal(publish(root, ["--repo", clone, "--no-convert", "--commit", "--push"], out), 0, out)
        t |> equal(git(path_join(root, "ports.git"), ["rev-parse", "HEAD"]), head)
        rmdir_rec(root)
    }
    t |> run("a failed git add, git commit or git push fails the publish") @(t : T?) {
        let root = stand_in_root("c2das_ports_git_fails")
        if (empty(root)) {
            t |> failure("no stand-in root")
            return
        }
        let clone = ports_clone(root)
        var out : string
        let lock = path_join(clone, ".git/index.lock")
        fwrite(lock, "")
        t |> equal(publish(root, ["--repo", clone, "--no-convert", "--commit"], out), 1, out)
        t |> success(out |> contains("lua: git add failed: "), out)
        remove(lock)
        let hook = path_join(clone, ".git/hooks/pre-commit")
        fwrite(hook, "#!/bin/sh\necho refused by the hook\nexit 1\n")
        run_and_capture(["chmod", "+x", hook], out, 10.0)
        t |> equal(publish(root, ["--repo", clone, "--no-convert", "--commit"], out), 1, out)
        t |> success(out |> contains("lua: git commit failed: refused by the hook"), out)
        remove(hook)
        git(clone, ["remote", "set-url", "origin", path_join(root, "no-such-origin.git")])
        t |> equal(publish(root, ["--repo", clone, "--no-convert", "--commit", "--push"], out), 1, out)
        t |> success(out |> contains("ports: git push failed: "), out)
        rmdir_rec(root)
    }
}

[test]
def test_convert(t : T?) {
    t |> run("without --no-convert: fetch.sh and the harness run, the stamp names HEAD, the harness's clock-free report in the README; an unchanged tree commits once") @(t : T?) {
        let root = stand_in_root("c2das_ports_convert")
        if (empty(root)) {
            t |> failure("no stand-in root")
            return
        }
        let clone = ports_clone(root)
        remove(stamp_path(root))
        var out : string
        t |> equal(publish(root, ["--repo", clone, "--commit"], out), 0, out)
        let sha = git(root, ["rev-parse", "HEAD"])
        t |> success(fread(stamp_path(root)) |> starts_with("{sha}\nv9.9.9\n"), out)
        let readme = fread(path_join(clone, "lua/README.md"))
        t |> success(readme |> contains("```\n[W] lua: lua_all: JSON 10 bytes\n[W] lua: lua_all: 3 lines of das\n[W] lua: lua_all: units of s, dots . s\n```"), readme)
        t |> success(readme |> contains("`scripts/publish_ports.sh --program lua`"), readme)
        t |> success(fread(path_join(root, "lua/work/publish_run.log")) |> contains("lua: lua_all: dumper"), out)
        let head = git(clone, ["rev-parse", "HEAD"])
        t |> equal(publish(root, ["--repo", clone, "--commit"], out), 0, out)
        t |> equal(git(clone, ["rev-parse", "HEAD"]), head, out)
        // the log stays for a later --no-convert publish
        t |> equal(publish(root, ["--repo", clone, "--no-convert"], out), 0, out)
        t |> success(fread(path_join(clone, "lua/README.md")) |> contains("[W] lua: lua_all: JSON 10 bytes"), out)
        rmdir_rec(root)
    }
    t |> run("a failed fetch and a failed conversion stop the publish before the clone is touched") @(t : T?) {
        let root = stand_in_root("c2das_ports_convert_fails")
        if (empty(root)) {
            t |> failure("no stand-in root")
            return
        }
        let clone = ports_clone(root)
        fwrite(path_join(root, "lua/fetch.sh"), "echo no network\nexit 1\n")
        var out : string
        t |> equal(publish(root, ["--repo", clone, "--allow-dirty"], out), 1, out)
        t |> success(out |> contains("lua: lua/fetch.sh failed: no network"), out)
        fwrite(path_join(root, "lua/fetch.sh"), "exit 0\n")
        fwrite(path_join(root, "lua/run.das"), "options gen2\n[export]\ndef main : int \{\n    return 1\n\}\n")
        t |> equal(publish(root, ["--repo", clone, "--allow-dirty"], out), 1, out)
        t |> success(out |> contains("lua: the conversion exited 1; lua/work/publish_run.log holds its log"), out)
        t |> equal(git(clone, ["status", "--porcelain"]), "")
        rmdir_rec(root)
    }
}

// the latest capture a bench run wrote into the clone, and its file name
def private capture_of(clone : string; var name : string&) : Capture {
    dir(path_join(clone, "lua/perf")) $(file) {
        if (file |> ends_with(".json") && file > name) {
            name = file
        }
    }
    var error : string
    let js = read_json(fread(path_join(clone, "lua/perf/{name}")), error)
    var c : Capture
    if (js != null) {
        c <- from_JV(js, type<Capture>)
    }
    return <- c
}

def private cell_of(c : Capture; workload, lane : string) : LaneCell {
    for (cell in c.cells) {
        if (cell.workload == workload && cell.lane == lane) {
            return <- clone_to_move(cell)
        }
    }
    return LaneCell(error = "no cell")
}

[test]
def test_bench(t : T?) {
    t |> run("a bench run: every workload under every lane, a das cell standing only on the native output and exit code") @(t : T?) {
        let root = stand_in_root("c2das_ports_bench")
        if (empty(root)) {
            t |> failure("no stand-in root")
            return
        }
        let clone = ports_clone(root)
        var out : string
        t |> equal(publish(root, ["--repo", clone, "--no-convert", "--perf", "--samples", "2", "--lanes", "interp,jit,exe,aot", "--commit"], out), 0, out)
        var name : string
        let c <- capture_of(clone, name)
        t |> equal(c.program, "lua", name)
        t |> equal(c.commit, git(root, ["rev-parse", "HEAD"]))
        t |> equal(c.command, "scripts/publish_ports.sh --program lua --no-convert --perf --samples 2 --lanes interp,jit,exe,aot --timeout 1800")
        t |> equal(c.timeout, 1800)
        t |> success(c.machine.clang |> contains("clang version"), c.machine.clang)
        t |> success(!empty(c.machine.clang_path))
        // the file name and the timestamp name the same moment, the end of the run
        let minute = "{slice(c.timestamp, 0, 10)}T{slice(c.timestamp, 11, 13)}{slice(c.timestamp, 14, 16)}"
        t |> equal(slice(name, length("capture_"), length("capture_YYYY-MM-DDTHHMM")), minute, "{name} {c.timestamp}")
        // a sample ends with the program's output, not with popen's 100 ms watchdog tick
        let startup = cell_of(c, "startup", "native")
        t |> success(empty(startup.error) && startup.time < 0.09lf, "{startup}")
        t |> success(startup.spread == startup.spread && startup.spread < 100.0lf, "{startup}")
        // a standing cell is the median of all its samples; the stand-in's `info` line is no output
        let fib = cell_of(c, "fib", "interp")
        t |> success(empty(fib.error) && length(fib.samples) == 2, "{fib}")
        t |> success(length(fib.samples) == 2 && fib.time == (fib.samples[0] + fib.samples[1]) * 0.5lf, "{fib}")
        // a failed cell keeps the sample that failed it
        let trees = cell_of(c, "binary_trees", "interp")
        t |> success(!empty(trees.error) && length(trees.samples) == 1, "{trees}")
        let readme = fread(path_join(clone, "lua/README.md"))
        for (fact in ["- `perf/capture_*.json` - every capture", "`scripts/publish_ports.sh --program lua --no-convert --perf --samples 2 --lanes interp,jit,exe,aot --timeout 1800`", "Captured ", " runs of the whole program", "- JIT: `daslang -load_module <c2das-re>/dasCRuntime -load_module <c2das-re>/c_runtime -jit lua_all.das --`", "- AOT, every workload: not yet: the aot tier's host passes the program no arguments\n", "- binary_trees, interpreter: not yet: exited 2 where the native build exits 0: EXCEPTION: boom\n", "- nbody, JIT: not yet: line 1 prints `drift` where the native build prints `", "- spectral_norm, clang -O3: not yet: exited 1\n", "- spectral_norm, exe: not yet: no native run to compare with", "- clang -O3: `"]) {
            t |> success(readme |> contains(fact), "README lacks {fact}:\n{readme}")
        }
        // the test-suite row runs in the test folder and compares the exit code alone, so `ALL`
        // against `all.lua` stands
        t |> success(!(readme |> contains("- test suite, ")), readme)
        // each folder: one warm-up run, then the samples (a failing cell stops at its first)
        let tests = path_join(root, "lua/fetch/lua-5.9.1-tests")
        for (lane in ["interp", "jit"]) {
            t |> equal(line_count(path_join(root, "runs_{lane}.log")), 7, "{lane}: warm-up 1, startup 2, fib 2, binary_trees 1, nbody 1")
            t |> equal(line_count(path_join(tests, "runs_{lane}.log")), 3, "{lane}: warm-up 1, test suite 2")
        }
        let top = fread(path_join(clone, "README.md"))
        t |> success(top |> contains("| [lua](lua/README.md) |"), top)
        t |> success(top |> contains("not yet |\n"), top)
        t |> equal(git(clone, ["status", "--porcelain"]), "")
        rmdir_rec(root)
    }
}

[test]
def test_bench_failures(t : T?) {
    t |> run("a missing test-suite folder, a native timeout, a native build that fails beside an earlier binary, failing warm-ups, a capture that is not JSON") @(t : T?) {
        let root = stand_in_root("c2das_ports_bench_fails")
        if (empty(root)) {
            t |> failure("no stand-in root")
            return
        }
        let clone = ports_clone(root)
        var args <- ["--repo", clone, "--no-convert", "--perf", "--samples", "1", "--lanes", "interp", "--allow-dirty"]
        var out : string
        rmdir_rec(path_join(root, "lua/fetch/lua-5.9.1-tests"))
        t |> equal(publish(root, args, out), 0, out)
        var readme = fread(path_join(clone, "lua/README.md"))
        t |> success(readme |> contains("- test suite, clang -O3: not yet: no lua/fetch/lua-5.9.1-tests"), readme)
        t |> success(readme |> contains("- test suite, interpreter: not yet: no native run to compare with"), readme)
        mkdir_rec(path_join(root, "lua/fetch/lua-5.9.1-tests"))
        fwrite(path_join(root, "lua/fetch/lua-5.9.1-tests/all.lua"), "-- stand-in\n")
        // the warm-up in the test folder fails: the module fails wherever all.lua is beside it
        fwrite(path_join(root, "lua/work/lua_all/lua_all.das"), "options gen2\nrequire daslib/fio\n[export]\ndef main : int \{\n    if (fexist(\"all.lua\")) \{\n        print(\"no test folder here\\n\")\n        return 4\n    \}\n    let argv <- get_command_line_arguments()\n    print(\"\{argv[length(argv) - 1]\}\\n\")\n    return 0\n\}\n")
        t |> equal(publish(root, args, out), 0, out)
        readme = fread(path_join(clone, "lua/README.md"))
        t |> success(readme |> contains("- test suite, interpreter: not yet: the warm-up run exited 4: no test folder here\n"), readme)
        t |> success(readme |> contains("| fib "), readme)
        fwrite(path_join(root, "lua/work/lua_all.c"), "#include <unistd.h>\nint main(void) \{ sleep(5); return 0; \}\n")
        var timed <- clone_to_move(args)
        timed |> push_from(["--timeout", "1"])
        t |> equal(publish(root, timed, out), 0, out)
        readme = fread(path_join(clone, "lua/README.md"))
        t |> success(readme |> contains("- startup, clang -O3: not yet: timed out after 1 s"), readme)
        // an earlier native binary that would print the right output stays unused
        fwrite(path_join(root, "lua/work/lua_all.c"), "int main(void) \{ return not_c; \}\n")
        fwrite(path_join(root, "lua/work/bench/lua_all_native"), "#!/bin/sh\nfor a; do last=$a; done\necho \"$last\"\n")
        run_and_capture(["chmod", "+x", path_join(root, "lua/work/bench/lua_all_native")], out, 10.0)
        let long_line = repeat("x", 200)
        fwrite(path_join(root, "lua/work/lua_all/lua_all.das"), "options gen2\n[export]\ndef main : int \{\n    print(\"{long_line}\\n\")\n    return 3\n\}\n")
        t |> equal(publish(root, ["--repo", clone, "--no-convert", "--perf", "--samples", "1", "--lanes", "jit", "--allow-dirty"], out), 0, out)
        readme = fread(path_join(clone, "lua/README.md"))
        t |> success(readme |> contains("- clang -O3, every workload: not yet: the build failed: "), readme)
        var name : string
        let c <- capture_of(clone, name)
        t |> success(!empty(c.cells), name)
        for (cell in c.cells) {
            t |> success(!empty(cell.error) && cell.time == 0.0lf, "{cell}")
        }
        // a lane's error is clipped to 160 characters
        let jit = "- JIT, every workload: not yet: "
        let lines <- [for (ln in split(readme, "\n")); ln; where ln |> starts_with(jit)]
        t |> success(length(lines) == 1 && lines[0] |> starts_with("{jit}the warm-up run exited 3: xxx") && lines[0] |> ends_with("x...") && length(lines[0]) == length(jit) + 160, readme)
        // the latest capture by name is not JSON: the publish names it and fails
        fwrite(path_join(clone, "lua/perf/capture_9999-99-99T999999Z.json"), "not json\n")
        t |> equal(publish(root, args, out), 1, out)
        t |> success(out |> contains("lua/perf/capture_9999-99-99T999999Z.json is not JSON"), out)
        rmdir_rec(root)
    }
}
