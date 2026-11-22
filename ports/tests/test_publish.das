options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require daslib/json_boost
require ../ports_render.das
require ../../perf/perf_lanes.das
require ../../perf/boxes.das
require ../../metrics/criteria_file.das

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

// the stand-in interpreter: under the wrapper `timed.lua` first its work line on stderr, then its
// last argument, except `spectral_norm.lua` which fails and `all.lua`, which must be in the
// working folder and ends with the suite's closing line
let LUA_C = "#include <stdio.h>\n#include <string.h>\nint main(int argc, char **argv) \{\n    for (int i = 1; i < argc; i++) if (strstr(argv[i], \"timed.lua\")) fprintf(stderr, \"c2das_work_s=0.001000\\n\");\n    const char *last = argv[argc - 1];\n    if (strstr(last, \"spectral_norm.lua\")) return 1;\n    if (strcmp(last, \"all.lua\") == 0) \{\n        FILE *f = fopen(\"all.lua\", \"r\");\n        if (!f) return 1;\n        fclose(f);\n        printf(\"all.lua\\nfinal OK !!!\\n\");\n        return 0;\n    \}\n    printf(\"%s\\n\", last);\n    return 0;\n\}\n"

// the work line a stand-in module prints among its output under the wrapper `timed.lua`, another
// number than the native stand-in's, so a cell stands only when the line is taken out before the
// comparison
let WORK_LINE_DAS = "def work_line \{\n    for (a in get_command_line_arguments()) \{\n        if (a |> ends_with(\"timed.lua\")) \{\n            print(\"c2das_work_s=0.002000\\n\")\n            return\n        \}\n    \}\n\}\n"

// the stand-in conversion: an `info` line, its work line, then what the C prints, except an exception line and a
// trailer with exit 2 for `binary_trees.lua`, another first line for `nbody.lua`, and `ALL` with
// the suite's closing line for `all.lua`, whose row compares the exit code and that line alone;
// every run counts itself in `runs_<lane>.log` of its working folder (a run of the fast variant's
// tree or binary as `<tier>-fast`), a run of `fib.lua` also names its lane in `runs_order_fib.log`, and reads its arguments as a
// converted program does (get_user_args: after `--` under daslang and the AOT host, all of them
// under an exe), so a lane that hands them on wrongly fails its cells
let LUA_DAS = "options gen2\nrequire strings\nrequire daslib/strings_boost\nrequire daslib/fio\nrequire daslib/clargs\ndef count_run(argv : array<string>) \{\n    let tier = has_value(argv, \"-jit\") ? \"jit\" : argv[0] |> ends_with(\"_exe.exe\") || argv[0] |> ends_with(\"_exe\") ? \"exe\" : argv[0] |> ends_with(\"_aot.exe\") || argv[0] |> ends_with(\"_aot\") ? \"aot\" : \"interp\"\n    let lane = join(argv, \" \") |> contains(\"/fast/\") ? \"\{tier\}-fast\" : tier\n    fopen(\"runs_\{lane\}.log\", \"ab\") $(f) \{\n        if (f != null) \{\n            fwrite(f, \"run\\n\")\n        \}\n    \}\n    if (argv[length(argv) - 1] |> ends_with(\"fib.lua\")) \{\n        fopen(\"runs_order_fib.log\", \"ab\") $(f) \{\n            if (f != null) \{\n                fwrite(f, \"\{lane\}\\n\")\n            \}\n        \}\n    \}\n\}\n{WORK_LINE_DAS}[export]\ndef main : int \{\n    let argv <- get_command_line_arguments()\n    count_run(argv)\n    let args <- get_user_args()\n    if (empty(args)) \{\n        print(\"no arguments\\n\")\n        return 3\n    \}\n    let last = args[length(args) - 1]\n    print(\"[I] stand-in\\n\")\n    work_line()\n    if (last |> ends_with(\"binary_trees.lua\")) \{\n        print(\"EXCEPTION: boom\\ntrailer\\n\")\n        return 2\n    \}\n    if (last == \"all.lua\" && !fexist(\"all.lua\")) \{\n        return 1\n    \}\n    if (last |> ends_with(\"nbody.lua\")) \{\n        print(\"drift\\n\{last\}\\n\")\n        return 0\n    \}\n    print(\"\{last == \"all.lua\" ? \"ALL\\nfinal OK !!!\" : last\}\\n\")\n    return 0\n\}\n"

// the stand-in harness: each run's arguments a line of `lua/work/harness_runs.log`, then its report
// with seconds that differ on every run, a line of seconds alone, and clauses ending in ` s` that
// are no seconds
let RUN_DAS = "options gen2\nrequire daslib/strings_boost\nrequire daslib/fio\nrequire daslib/clargs\n[export]\ndef main : int \{\n    fopen(\"lua/work/harness_runs.log\", \"ab\") $(f) \{\n        if (f != null) \{\n            fwrite(f, join(get_user_args(), \" \") + \"\\n\")\n        \}\n    \}\n    to_log(LOG_WARNING, \"lua: lua_all: dumper \{ref_time_ticks()\} s, JSON 10 bytes\\n\")\n    to_log(LOG_WARNING, \"lua: lua_all: emitter 0.\{ref_time_ticks() % 10l\} s, compile check 2.5 s, 3 lines of das\\n\")\n    to_log(LOG_WARNING, \"lua: total 7 s\\n\")\n    to_log(LOG_WARNING, \"lua: lua_all: units of s, dots . s\\n\")\n    return 0\n\}\n"

// a variant file's `layout` knob line with its value set to `source`
def private source_layout(line : string) : string => replace(replace(line, "\"value\": \"source-cut\"", "\"value\": \"source\""), "\"value\": \"single\"", "\"value\": \"source\"")

def private run_in(dir : string; argv : array<string>; var out : string&) : int => run_and_capture(in_folder(dir, argv), out, 1200.0)

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

// the publisher run in `root` with the Rust checkout `<root>/rust`, which holds no project unless
// a test writes one, so a publish of every program converts the stand-in projects alone
def private publish(root : string; args : array<string>; var out : string&) : int {
    var argv <- ["env", "C2DAS_RUST={path_join(root, "rust")}"]
    argv |> push_from(publish_argv(args))
    return run_in(root, argv, out)
}

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
    // each variant's conversion in the source layout: the source tree holds fragments and folders
    // beside the entry module, and the conversion's C-IR and checks, which stay out of the publish
    // every committed variant file, the compare projects' and PureDOOM's among them
    mkdir_rec(path_join(root, "ports/variants"))
    dir("ports/variants") $(file) {
        if (file |> ends_with(".json")) {
            // the results a search recorded left out, so the tables take the fallbacks under test,
            // and the layout set to source, the layout the stand-in conversions are staged in
            let lines <- [for (ln in split(fread("ports/variants/{file}"), "\n")); ln |> starts_with("    \"results\":") ? "    \"results\": \{\}" : ln |> starts_with("        \"layout\":") ? source_layout(ln) : ln]
            fwrite(path_join(root, "ports/variants/{file}"), join(lines, "\n"))
        }
    }
    for (v in ["readable", "fast"]) {
        let work = path_join(root, "lua/work/variants/{v}")
        mkdir_rec(path_join(work, "lua"))
        mkdir_rec(path_join(work, "luac/sub"))
        fwrite(path_join(work, "lua/lua.das"), LUA_DAS)
        fwrite(path_join(work, "luac/luac.das"), "// luac {v}\n")
        fwrite(path_join(work, "luac/lcode_cluster.das"), "// cluster\n")
        fwrite(path_join(work, "luac/lcode.das.inc"), "// fragment\n")
        fwrite(path_join(work, "luac/sub/deep.das"), "// deep\n")
        fwrite(path_join(work, "luac/lcode.cir.json"), "\{\}\n")
        fwrite(path_join(work, "luac/sub/lcode.native.luac"), "bytes\n")
        fwrite(path_join(work, "luac/program.layout.txt"), "luac\nlcode_cluster\n")
        // the module lists of the conversions; a module an earlier conversion left is in none
        fwrite(path_join(work, "lua/program.modules.txt"), "lua.das\n")
        fwrite(path_join(work, "luac/program.modules.txt"), "lcode.das.inc\nlcode_cluster.das\nluac.das\nsub/deep.das\n")
        fwrite(path_join(work, "luac/stale_cluster.das"), "// stale\n")
    }
    fwrite(path_join(root, "lua/work/lua.c"), LUA_C)
    fwrite(path_join(root, "lua/work/lua.program.json"), "\{\"tus\": [\"lua.c\"]\}\n")
    mkdir_rec(path_join(root, "ports/lua/bench"))
    for (bench in ["fib", "binary_trees", "nbody", "spectral_norm", "timed"]) {
        fwrite(path_join(root, "ports/lua/bench/{bench}.lua"), fread("ports/lua/bench/{bench}.lua"))
    }
    fwrite(path_join(root, ".gitignore"), "/lua/work/bench/\n/lua/work/publish_run.log\n/lua/work/variants/*/publish_run.log\n/lua/work/harness_runs.log\n/lua/work/publish.generation\nruns_*.log\n.cache/\n/clone/\n/ports.git/\n/plain/\n/compare/work/\n")
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

// `body` run as a named arm over a fresh stand-in root named after `name` and its ports clone,
// the root removed after it; a failure when no root can be made
def private run_stand_in(t : T?; title, name : string; body : lambda<(t : T?; root, clone : string) : void>) {
    t |> run(title) @(t : T?) {
        let root = stand_in_root(name)
        if (empty(root)) {
            t |> failure("no stand-in root")
            return
        }
        body |> invoke(t, root, ports_clone(root))
        rmdir_rec(root)
    }
}

// the clone as the publish that made `head` left it
def private untouched(t : T?; clone, head, why : string) {
    t |> equal(git(clone, ["status", "--porcelain"]), "", why)
    t |> equal(git(clone, ["rev-parse", "HEAD"]), head, why)
}

// the lines of `path`, 0 for a missing file
def private line_count(path : string) : int => length([for (ln in split(fread(path), "\n")); ln; where !empty(ln)])

// the cell of `workload` under `lane`, or a failing one when the capture lacks it, so a missing
// cell fails the test instead of dereferencing `find_cell`'s null
def private cell_of(t : T?; c : Capture; workload, lane : string) : LaneCell {
    let cell = find_cell(c, workload, lane)
    if (cell == null) {
        t |> failure("no {workload}/{lane} cell")
        return <- LaneCell(error = "no cell")
    }
    return <- clone_to_move(*cell)
}

[test]
def test_refusals(t : T?) {
    t |> run("-? prints the help and publishes nothing") @(t : T?) {
        var out : string
        t |> equal(run_in(".", publish_argv(["-?"]), out), 0, out)
        t |> success(out |> contains("show this help and exit"), out)
        t |> success(out |> contains("--allow-stale"), out)
    }
    t |> run_stand_in("an unknown program or lane, --push without --commit, --samples below 0, --timeout of 0, and a directory that is no clone", "c2das_ports_refusals") @(t : T?; root, clone : string) {
        var out : string
        t |> equal(publish(root, ["--repo", clone, "--program", "doom"], out), 1, out)
        t |> success(out |> contains("no program `doom`; the publisher knows lua"), out)
        t |> equal(publish(root, ["--repo", clone, "--lanes", "interp,llvm"], out), 1, out)
        t |> success(out |> contains("no das lane `llvm`; --lanes takes interp, jit, exe, aot, interp-fast, jit-fast, exe-fast and aot-fast"), out)
        t |> equal(publish(root, ["--repo", clone, "--lanes", "jit-goto"], out), 1, out)
        t |> success(out |> contains("no das lane `jit-goto`"), out)
        t |> equal(publish(root, ["--repo", clone, "--lanes", "native"], out), 1, out)
        t |> success(out |> contains("no das lane `native`"), out)
        t |> equal(publish(root, ["--repo", clone, "--push"], out), 1, out)
        t |> success(out |> contains("--push needs --commit"), out)
        t |> equal(publish(root, ["--repo", clone, "--no-convert", "--perf", "--samples", "-1"], out), 1, out)
        t |> success(out |> contains("--samples takes a count of 1 or more, or 0 for samples_for's, not -1"), out)
        t |> equal(publish(root, ["--repo", clone, "--no-convert", "--perf", "--timeout", "0"], out), 1, out)
        t |> success(out |> contains("--timeout takes seconds above 0, not 0"), out)
        t |> equal(publish(root, ["--repo", clone, "--box", "laptop"], out), 1, out)
        t |> success(out |> contains("ports: --box takes bench, PC, fx, not `laptop`"), out)
        let own = box_of(cpu_name())
        if (!empty(own)) {
            let other = own == "bench" ? "fx" : "bench"
            t |> equal(publish(root, ["--repo", clone, "--box", other], out), 1, out)
            t |> success(out |> contains("ports: --box {other} names another box than this CPU's"), out)
        }
        let plain = path_join(root, "plain")
        mkdir_rec(plain)
        t |> equal(publish(root, ["--repo", plain, "--no-convert"], out), 1, out)
        t |> success(out |> contains("is no clone of the ports repository"), out)
        // a folder inside a work tree is not the top of one
        mkdir_rec(path_join(clone, "sub"))
        t |> equal(publish(root, ["--repo", path_join(clone, "sub"), "--no-convert"], out), 1, out)
        t |> success(out |> contains("is no clone of the ports repository"), out)
        t |> success(!fexist(path_join(clone, "lua")), "a refused publish wrote into the clone")
    }
    t |> run_stand_in("the clone defaults to $C2DAS_PORTS, else ../c2das-ports", "c2das_ports_env") @(t : T?; root, clone : string) {
        var out : string
        let plain = path_join(root, "plain")
        t |> equal(run_in(root, with_env(["C2DAS_PORTS={plain}"]), out), 1, out)
        t |> success(out |> contains("{plain} is no clone"), out)
        t |> equal(run_in(root, with_env(["C2DAS_PORTS={clone}"]), out), 0, out)
        t |> success(fexist(path_join(clone, "lua/README.md")), out)
        // without the variable, the clone beside the root
        t |> equal(run_in(root, with_env(["-u", "C2DAS_PORTS"]), out), 1, out)
        t |> success(out |> contains("../c2das-ports is no clone"), out)
    }
}

[test]
def test_tree_refusals(t : T?) {
    t |> run_stand_in("a dirty c2das-re tree without --allow-dirty; with it the conversion's stamp names -dirty; a root that is no git tree", "c2das_ports_dirty") @(t : T?; root, clone : string) {
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
    }
}

[test]
def test_input_refusals(t : T?) {
    t |> run_stand_in("a refused input leaves the clone as the last publish left it: the pin, the stamp, a module, the license block, the sidecar", "c2das_ports_inputs") @(t : T?; root, clone : string) {
        var out : string
        t |> equal(publish(root, ["--repo", clone, "--no-convert", "--commit"], out), 0, out)
        let head = git(clone, ["rev-parse", "HEAD"])
        // a changed module, so a refusal that wrote it first would show in the clone
        let lua_module = path_join(root, "lua/work/variants/readable/lua/lua.das")
        fwrite(lua_module, LUA_DAS + "// changed\n")
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
        let luac_module = path_join(root, "lua/work/variants/fast/luac/luac.das")
        remove(luac_module)
        t |> equal(publish(root, args, out), 1, out)
        t |> success(out |> contains("no lua/work/variants/fast/luac/luac.das; run without --no-convert"), out)
        untouched(t, clone, head, "no luac module")
        fwrite(luac_module, "// luac fast\n")
        let luac_list = path_join(root, "lua/work/variants/readable/luac/program.modules.txt")
        let list = fread(luac_list)
        remove(luac_list)
        t |> equal(publish(root, args, out), 1, out)
        t |> success(out |> contains("no lua/work/variants/readable/luac/program.modules.txt; run without --no-convert"), out)
        untouched(t, clone, head, "no module list")
        fwrite(luac_list, list)
        // a variant file that does not read, and one whose knob the converter refuses
        let fast_file = path_join(root, "ports/variants/lua.fast.json")
        let fast_text = fread(fast_file)
        fwrite(fast_file, "[]\n")
        t |> equal(publish(root, args, out), 1, out)
        t |> success(out |> contains("lua: ports/variants/lua.fast.json: a variant file is a JSON object"), out)
        untouched(t, clone, head, "a variant file that does not read")
        fwrite(fast_file, fast_text)
        remove(path_join(root, "lua/lua.c2das"))
        t |> equal(publish(root, args, out), 1, out)
        t |> success(out |> contains("no lua/lua.c2das"), out)
        untouched(t, clone, head, "no sidecar")
    }
}

[test]
def test_stale(t : T?) {
    t |> run_stand_in("--allow-stale publishes a stamp of another commit under that commit, and a missing stamp as unrecorded", "c2das_ports_stale") @(t : T?; root, clone : string) {
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
    }
}

// the program's folder `dir` in the clone holds each variant's trees, every module and fragment in
// its folders with the layout report and nothing else of the work tree
def private published_modules(t : T?; dir : string) {
    for (v in ["readable", "fast"]) {
        t |> equal(fread(path_join(dir, "{v}/lua/lua.das")), LUA_DAS)
        t |> equal(fread(path_join(dir, "{v}/luac/luac.das")), "// luac {v}\n")
        t |> equal(fread(path_join(dir, "{v}/luac/lcode_cluster.das")), "// cluster\n")
        t |> equal(fread(path_join(dir, "{v}/luac/lcode.das.inc")), "// fragment\n")
        t |> equal(fread(path_join(dir, "{v}/luac/sub/deep.das")), "// deep\n")
        t |> success(!fexist(path_join(dir, "{v}/luac/lcode.cir.json")) && !fexist(path_join(dir, "{v}/luac/sub/lcode.native.luac")))
        t |> equal(fread(path_join(dir, "{v}/luac/program.layout.txt")), "luac\nlcode_cluster\n")
        t |> success(!fexist(path_join(dir, "{v}/luac/stale_cluster.das")))
    }
}

[test]
def test_publish_commit_push(t : T?) {
    t |> run_stand_in("--no-convert --commit writes the fixed set and commits it; a second run commits nothing; --push pushes", "c2das_ports_publish") @(t : T?; root, clone : string) {
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
        t |> equal(join(names, " "), "LICENSE README.md bench fast readable")
        var benches : array<string>
        dir(path_join(dir, "bench")) $(name) {
            if (name != "." && name != "..") {
                benches |> push(name)
            }
        }
        benches |> sort()
        t |> equal(join(benches, " "), "binary_trees.lua fib.lua nbody.lua spectral_norm.lua timed.lua")
        // each variant's sidecar is the program's with the variant's knobs set, beside its file
        for (v in ["readable", "fast"]) {
            let sidecar = fread(path_join(dir, "{v}/lua.c2das"))
            var error : string
            let knobs = read_json(fread(path_join(root, "ports/variants/lua.{v}.json")), error)
            let fn_macros = knobs?["knobs"]?["fn_macros"]?["value"] ?? ""
            t |> success(!empty(fn_macros) && sidecar |> contains("\"defines\" : [") && sidecar |> contains("\"STAND_IN=1\"") && sidecar |> contains("\"fn_macros\" : \"{fn_macros}\""), sidecar)
            t |> equal(fread(path_join(dir, "{v}/variant.json")), fread(path_join(root, "ports/variants/lua.{v}.json")))
        }
        published_modules(t, dir)
        t |> equal(fread(path_join(dir, "bench/nbody.lua")), fread("ports/lua/bench/nbody.lua"))
        t |> equal(fread(path_join(dir, "bench/timed.lua")), fread("ports/lua/bench/timed.lua"))
        let license = fread(path_join(dir, "LICENSE"))
        t |> success(license |> starts_with("Copyright (C) 1994-2025 Stand-in.\n\nPermission"), license)
        t |> success(license |> ends_with("DEALINGS IN THE SOFTWARE.\n"), license)
        let sha = git(root, ["rev-parse", "HEAD"])
        let readme = fread(path_join(dir, "README.md"))
        for (fact in ["# lua\n\nLua 5.9.1 converted", A_HASH, B_HASH, "https://example.invalid/lua-5.9.1-tests.tar.gz", "- Generated by c2das-re `v9.9.9` (`{sha}`, committed ", "`scripts/publish_ports.sh --program lua --no-convert`", "readable/luac/luac.das -- -o out.luac", "readable/lua/lua.das -- -e", "-jit fast/lua/lua.das -- bench/fib.lua", "- `readable/lua/` - the interpreter `lua`: the core, the standard libraries and `lua.c`, the readable variant, a module per C file", "- `fast/luac/` - the compiler `luac`", "- `fast/lua.c2das` - the sidecar the fast variant was converted under, `fast/variant.json` - its knobs", "## Variants\n\n- `readable/` - for reading and changing the code: Boris, and the weak-model add-a-feature check.\n- `fast/` - for running.\n", "| `fn_macros` ", "| Criteria total, % ", "| x native, JIT ", "| das lines ", "| `luaV_execute` lines ", "The results c2das-re's P5.1 recorded for this program, not results of this publish's run", "a conversion that left no harness log", "- `bench/` - the benchmark scripts the perf tables will run, and `timed.lua`, which runs each and reports its work seconds measured inside the process.\n\n## Source", "## Performance\n\nnot yet: the publisher measures only under `--perf`, off by default because a capture takes hours and runs only on an idle machine\n"]) {
            t |> success(readme |> contains(fact), "README lacks {fact}:\n{readme}")
        }
        let top = fread(path_join(clone, "README.md"))
        t |> success(top |> starts_with("# ports\n\nThe charter.\n\n<!-- generated below"), top)
        t |> success(top |> ends_with("## Programs\n\nnot yet: the publisher measures only under `--perf`, off by default because a capture takes hours and runs only on an idle machine\n\n## Directories\n\n- [lua](lua/)\n"), top)
        t |> equal(git(clone, ["log", "-1", "--format=%s %an"]), "lua: regenerated from c2das-re v9.9.9 ({sha}) lookibed")
        t |> equal(git(clone, ["status", "--porcelain"]), "")
        let head = git(clone, ["rev-parse", "HEAD"])
        t |> equal(publish(root, ["--repo", clone, "--no-convert", "--commit"], out), 0, out)
        t |> equal(git(clone, ["rev-parse", "HEAD"]), head)
        t |> equal(git(path_join(root, "ports.git"), ["rev-parse", "HEAD"]) == head, false)
        t |> equal(publish(root, ["--repo", clone, "--no-convert", "--commit", "--push"], out), 0, out)
        t |> equal(git(path_join(root, "ports.git"), ["rev-parse", "HEAD"]), head)
    }
    t |> run_stand_in("a failed git add, git commit or git push fails the publish", "c2das_ports_git_fails") @(t : T?; root, clone : string) {
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
    }
}

[test]
def test_source_cut_variant(t : T?) {
    t |> run_stand_in("a variant in the source-cut layout publishes the trees of that layout's folder", "c2das_ports_cut") @(t : T?; root, clone : string) {
        let fast = path_join(root, "ports/variants/lua.fast.json")
        fwrite(fast, replace(fread(fast), "\"layout\": \{\"value\": \"source\"", "\"layout\": \{\"value\": \"source-cut\""))
        t |> success(fread(fast) |> contains("\"layout\": \{\"value\": \"source-cut\""))
        let work = path_join(root, "lua/work/variants/fast")
        mkdir_rec(path_join(work, "source-cut"))
        var out : string
        for (stem in ["lua", "luac"]) {
            t |> equal(run_and_capture(["mv", path_join(work, stem), path_join(work, "source-cut/{stem}")], out, 60.0), 0, out)
        }
        git(root, ["add", "-A"])
        git(root, ["commit", "-q", "-m", "fast in source-cut"])
        fwrite(stamp_path(root), "{git(root, ["rev-parse", "HEAD"])}\nv9.9.9\n{git(root, ["log", "-1", "--format=%cs"])}\n")
        t |> equal(publish(root, ["--repo", clone, "--no-convert"], out), 0, out)
        published_modules(t, path_join(clone, "lua"))
        t |> success(fread(path_join(clone, "lua/README.md")) |> contains("the fast variant, a module per C file, the cycles among files cut by late binding"), out)
    }
}

[test]
def test_convert(t : T?) {
    t |> run_stand_in("without --no-convert: fetch.sh and the harness run, the stamp names HEAD, the harness's clock-free report in the README; an unchanged tree commits once", "c2das_ports_convert") @(t : T?; root, clone : string) {
        remove(stamp_path(root))
        var out : string
        t |> equal(publish(root, ["--repo", clone, "--commit"], out), 0, out)
        let sha = git(root, ["rev-parse", "HEAD"])
        t |> success(fread(stamp_path(root)) |> starts_with("{sha}\nv9.9.9\n"), out)
        let readme = fread(path_join(clone, "lua/README.md"))
        t |> success(readme |> contains("```\nreadable:\n[W] lua: lua_all: JSON 10 bytes\n[W] lua: lua_all: 3 lines of das\n[W] lua: lua_all: units of s, dots . s\nfast:\n[W] lua: lua_all: JSON 10 bytes\n[W] lua: lua_all: 3 lines of das\n[W] lua: lua_all: units of s, dots . s\n```"), readme)
        t |> success(readme |> contains("`scripts/publish_ports.sh --program lua`"), readme)
        // the harness runs once per variant, the conversion in the variant's layout with its oracle,
        // each log apart
        t |> equal(fread(path_join(root, "lua/work/harness_runs.log")), "--native --run --variant ports/variants/lua.readable.json --layout source\n--native --run --variant ports/variants/lua.fast.json --layout source\n", out)
        for (v in ["readable", "fast"]) {
            t |> success(fread(path_join(root, "lua/work/variants/{v}/publish_run.log")) |> contains("lua: lua_all: dumper"), out)
            t |> success(readme |> contains("{v}:\n[W] lua: lua_all: JSON 10 bytes\n"), readme)
        }
        let head = git(clone, ["rev-parse", "HEAD"])
        t |> equal(publish(root, ["--repo", clone, "--commit"], out), 0, out)
        t |> equal(git(clone, ["rev-parse", "HEAD"]), head, out)
        // the log stays for a later --no-convert publish
        t |> equal(publish(root, ["--repo", clone, "--no-convert"], out), 0, out)
        t |> success(fread(path_join(clone, "lua/README.md")) |> contains("[W] lua: lua_all: JSON 10 bytes"), out)
    }
    t |> run_stand_in("a failed fetch and a failed conversion stop the publish before the clone is touched", "c2das_ports_convert_fails") @(t : T?; root, clone : string) {
        fwrite(path_join(root, "lua/fetch.sh"), "echo no network\nexit 1\n")
        var out : string
        t |> equal(publish(root, ["--repo", clone, "--allow-dirty"], out), 1, out)
        t |> success(out |> contains("lua: lua/fetch.sh failed: no network"), out)
        fwrite(path_join(root, "lua/fetch.sh"), "exit 0\n")
        fwrite(path_join(root, "lua/run.das"), "options gen2\n[export]\ndef main : int \{\n    return 1\n\}\n")
        t |> equal(publish(root, ["--repo", clone, "--allow-dirty"], out), 1, out)
        t |> success(out |> contains("lua: the conversion of the readable variant exited 1; lua/work/variants/readable/publish_run.log holds its log"), out)
        t |> equal(git(clone, ["status", "--porcelain"]), "")
        // the fast variant's conversion failing stops the publish too, and takes away the stamp an
        // earlier conversion at this HEAD left, so --no-convert refuses the half-written work folder
        fwrite(stamp_path(root), "{git(root, ["rev-parse", "HEAD"])}\nv9.9.9\n2020-01-01\n")
        fwrite(path_join(root, "lua/run.das"), "options gen2\nrequire daslib/clargs\n[export]\ndef main : int \{\n    return has_value(get_user_args(), \"ports/variants/lua.fast.json\") ? 4 : 0\n\}\n")
        t |> equal(publish(root, ["--repo", clone, "--allow-dirty"], out), 1, out)
        t |> success(out |> contains("lua: the conversion of the fast variant exited 4; lua/work/variants/fast/publish_run.log holds its log"), out)
        t |> success(!fexist(stamp_path(root)), out)
        t |> equal(git(clone, ["status", "--porcelain"]), "")
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

[test]
def test_bench(t : T?) {
    t |> run_stand_in("a bench run: every workload under every lane, a das cell standing only on the native output and exit code", "c2das_ports_bench") @(t : T?; root, clone : string) {
        var out : string
        t |> equal(publish(root, ["--repo", clone, "--no-convert", "--perf", "--samples", "2", "--lanes", "interp,jit,exe,aot,jit-fast,exe-fast", "--commit"], out), 0, out)
        var name : string
        let c <- capture_of(clone, name)
        t |> equal(c.program, "lua", name)
        t |> equal(c.commit, git(root, ["rev-parse", "HEAD"]))
        t |> equal(c.command, "scripts/publish_ports.sh --program lua --no-convert --perf --samples 2 --lanes interp,jit,exe,aot,jit-fast,exe-fast --timeout 1800")
        t |> equal(c.timeout, 1800)
        t |> success(c.machine.clang |> contains("clang version"), c.machine.clang)
        t |> success(!empty(c.machine.clang_path))
        t |> equal(c.machine.cpu, cpu_name())
        t |> equal(c.machine.box, box_of(cpu_name()), "a capture without --box records its CPU's box")
        // the file name and the timestamp name the same moment, the end of the run
        let minute = "{slice(c.timestamp, 0, 10)}T{slice(c.timestamp, 11, 13)}{slice(c.timestamp, 14, 16)}"
        t |> equal(slice(name, length("capture_"), length("capture_YYYY-MM-DDTHHMM")), minute, "{name} {c.timestamp}")
        // a sample ends with the program's output, not with popen's 100 ms watchdog tick
        let startup <- cell_of(t, c, "startup", "native")
        t |> success(empty(startup.error) && startup.time < 0.09lf, "{startup}")
        t |> success(startup.spread == startup.spread && startup.spread < 100.0lf, "{startup}")
        // a standing cell is the median of all its samples; the stand-in's `info` line is no output
        let fib <- cell_of(t, c, "fib", "interp")
        t |> success(empty(fib.error) && length(fib.samples) == 2, "{fib}")
        t |> success(length(fib.samples) == 2 && fib.time == (fib.samples[0] + fib.samples[1]) * 0.5lf, "{fib}")
        // each sample under the wrapper reports its work seconds, the line no part of the output the
        // comparison sees (the stand-ins print other numbers); the startup row runs bare
        t |> success(length(fib.work_samples) == 2 && fib.work_time == 0.002lf && fib.work_time_spread == 0.0lf, "{fib}")
        let native_fib <- cell_of(t, c, "fib", "native")
        t |> success(empty(native_fib.error) && length(native_fib.work_samples) == 2 && native_fib.work_time == 0.001lf, "{native_fib}")
        t |> success(empty(startup.work_samples), "{startup}")
        let suite <- cell_of(t, c, "test suite", "jit")
        t |> success(empty(suite.error) && length(suite.work_samples) == 2, "{suite}")
        // a failed cell keeps the sample that failed it
        let trees <- cell_of(t, c, "binary_trees", "interp")
        t |> success(!empty(trees.error) && length(trees.samples) == 1, "{trees}")
        let readme = fread(path_join(clone, "lua/README.md"))
        for (fact in ["- `perf/capture_*.json` - every capture", "`scripts/publish_ports.sh --program lua --no-convert --perf --samples 2 --lanes interp,jit,exe,aot,jit-fast,exe-fast --timeout 1800`", "Captured ", "A sample is one run of the whole program", " | `bench/timed.lua bench/fib.lua` ", "`-e \"_port=true\" bench/timed.lua all.lua`", "- JIT: `daslang -load_module <c2das-re>/dasCRuntime -load_module <c2das-re>/c_runtime -jit readable/lua/lua.das --`", "- JIT, fast: `daslang -load_module <c2das-re>/dasCRuntime -load_module <c2das-re>/c_runtime -jit fast/lua/lua.das --`", "- exe, fast: `daslang -exe fast/lua/lua.das, the binary run`", "- binary_trees, JIT, fast: not yet: exited 2 where the native build exits 0: EXCEPTION: boom\n", "| exe / native | AOT / native | JIT, fast / native | exe, fast / native |", "| interpreter / JIT | interpreter / exe | interpreter / AOT | JIT / AOT | JIT, fast / JIT | exe, fast / exe |", "A lane `, fast` runs the `fast/` variant's modules", "- AOT: `the -ctx context of readable/lua/lua.das and its host compiled by clang++ -O3 (c2das-re converter/tiers.das), the binary run with `--``", "| x native, JIT ", "(1) not from a search of the variant: the latest capture of this directory's `perf/`", "- binary_trees, AOT: not yet: exited 2 where the native build exits 0: EXCEPTION: boom\n", "- binary_trees, interpreter: not yet: exited 2 where the native build exits 0: EXCEPTION: boom\n", "- nbody, JIT: not yet: line 1 prints `drift` where the native build prints `", "- spectral_norm, clang -O3: not yet: exited 1\n", "- spectral_norm, exe: not yet: no native run to compare with", "- clang -O3: `", " -o lua_native lua.c -lm`"]) {
            t |> success(readme |> contains(fact), "README lacks {fact}:\n{readme}")
        }
        // the test-suite row runs in the test folder and compares the exit code and the closing
        // line alone, so `ALL` against `all.lua` stands
        t |> success(!(readme |> contains("- test suite, ")), readme)
        // each folder: one warm-up run, then the samples (a failing cell stops at its first)
        let tests = path_join(root, "lua/fetch/lua-5.9.1-tests")
        for (lane in ["interp", "jit", "exe", "aot", "jit-fast", "exe-fast"]) {
            // a binary lane runs once more: its build's run, then the wrapper's check
            let runs = lane |> starts_with("exe") || lane == "aot" ? 8 : 7
            t |> equal(line_count(path_join(root, "runs_{lane}.log")), runs, "{lane}: warm-up {runs - 6}, startup 2, fib 2, binary_trees 1, nbody 1")
            // a binary lane has no module cache to warm in the test-suite folder
            let samples = lane |> starts_with("exe") || lane == "aot" ? 2 : 3
            t |> equal(line_count(path_join(tests, "runs_{lane}.log")), samples, "{lane}: warm-up {samples - 2}, test suite 2")
        }
        // every lane stands on fib, the AOT lane's binary run with the arguments too
        for (lane in ["interp", "jit", "exe", "aot", "jit-fast", "exe-fast"]) {
            let lane_fib <- cell_of(t, c, "fib", lane)
            t |> success(empty(lane_fib.error), "{lane}: {lane_fib}")
        }
        // the stand-in's runs are spawns alone, so a work time is noise: the tables stand, the
        // numbers are the renderer's tests'
        for (head in ["Startup:\n\n| Lane ", "Work:\n\n| Workload ", "Ratios, a lane's work time over another's", "Times, the raw medians of whole runs"]) {
            t |> success(readme |> contains(head), "README lacks {head}:\n{readme}")
        }
        let top = fread(path_join(clone, "README.md"))
        t |> success(top |> contains("| [lua](lua/README.md) |") && top |> contains("|         5 |"), top)
        t |> equal(git(clone, ["status", "--porcelain"]), "")
    }
}

[test]
def test_default_lanes(t : T?) {
    t |> run_stand_in("--perf without --lanes measures every das lane, the AOT lanes and the fast variant's among them", "c2das_ports_default_lanes") @(t : T?; root, clone : string) {
        var out : string
        t |> equal(publish(root, ["--repo", clone, "--no-convert", "--perf", "--samples", "1", "--allow-dirty"], out), 0, out)
        var name : string
        let c <- capture_of(clone, name)
        t |> equal(c.command, "scripts/publish_ports.sh --program lua --no-convert --perf --samples 1 --lanes interp,jit,exe,aot,interp-fast,jit-fast,exe-fast,aot-fast --timeout 1800")
        t |> equal(join([for (lane in c.lanes); lane.name], ","), "native,interp,jit,exe,aot,interp-fast,jit-fast,exe-fast,aot-fast")
        for (lane in ["aot", "aot-fast"]) {
            let fib <- cell_of(t, c, "fib", lane)
            t |> success(empty(fib.error) && length(fib.samples) == 1, "{lane}: {fib}")
        }
    }
}

[test]
def test_sample_order(t : T?) {
    t |> run_stand_in("the samples interleave: each round one sample of every lane, the das lanes forward, then backward", "c2das_ports_sample_order") @(t : T?; root, clone : string) {
        var out : string
        t |> equal(publish(root, ["--repo", clone, "--no-convert", "--perf", "--samples", "3", "--lanes", "interp,jit,jit-fast", "--allow-dirty"], out), 0, out)
        let order = join([for (ln in split(fread(path_join(root, "runs_order_fib.log")), "\n")); ln; where !empty(ln)], " ")
        t |> equal(order, "interp jit jit-fast jit-fast jit interp interp jit jit-fast")
        var name : string
        let c <- capture_of(clone, name)
        let fib <- cell_of(t, c, "fib", "jit")
        t |> success(empty(fib.error) && length(fib.samples) == 3 && length(fib.work_samples) == 3, "{fib}")
    }
    t |> run_stand_in("no --samples: a short native run gives every lane the noisy count; the capture records 0, the trimmed rule and each cell's outlier", "c2das_ports_sample_rule") @(t : T?; root, clone : string) {
        var out : string
        t |> equal(publish(root, ["--repo", clone, "--no-convert", "--perf", "--lanes", "interp", "--allow-dirty"], out), 0, out)
        var name : string
        let c <- capture_of(clone, name)
        t |> equal(c.samples, 0)
        t |> equal(c.spread_rule, TRIMMED_SPREAD)
        for (lane in ["native", "interp"]) {
            let fib <- cell_of(t, c, "fib", lane)
            t |> success(empty(fib.error) && length(fib.samples) == NOISY_SAMPLES && length(fib.work_samples) == NOISY_SAMPLES, "{lane}: {fib}")
            t |> success(fib.outlier == outlier_of(fib.samples, fib.time) && fib.spread == spread_of(fib.samples, fib.time), "{lane}: {fib}")
        }
        let readme = fread(path_join(clone, "lua/README.md"))
        t |> success(readme |> contains("a cell is the median of {samples_text(0)}, ± half their range as a share of the median{spread_note(TRIMMED_SPREAD)}"), readme)
    }
}

[test]
def test_native_reuse(t : T?) {
    t |> run_stand_in("the native lane reuses the binary its key describes and builds again after a C source changes", "c2das_ports_native_reuse") @(t : T?; root, clone : string) {
        var inscope argv <- ["env", "DAS_LOG_LEVEL=info", "C2DAS_RUST={path_join(root, "rust")}"]
        argv |> push_from(publish_argv(["--repo", clone, "--no-convert", "--perf", "--samples", "1", "--lanes", "interp", "--allow-dirty"]))
        var out : string
        t |> equal(run_in(root, argv, out), 0, out)
        t |> success(!(out |> contains("native build reused")), out)
        let key = path_join(root, "lua/work/bench/lua_native.key")
        t |> success(fread(key) |> contains("lua/work/lua.c "), fread(key))
        t |> equal(run_in(root, argv, out), 0, out)
        t |> success(out |> contains("native build reused"), out)
        fwrite(path_join(root, "lua/work/lua.c"), LUA_C + "/* edited */\n")
        t |> equal(run_in(root, argv, out), 0, out)
        t |> success(!(out |> contains("native build reused")), out)
        var name : string
        let c <- capture_of(clone, name)
        let fib <- cell_of(t, c, "fib", "interp")
        t |> success(empty(fib.error), "{fib}")
    }
}

[test]
def test_stale_modules(t : T?) {
    t |> run_stand_in("a publish removes from each variant's folder every file its module list no longer names; a listed file stays", "c2das_ports_stale") @(t : T?; root, clone : string) {
        var out : string
        t |> equal(publish(root, ["--repo", clone, "--no-convert", "--allow-dirty"], out), 0, out)
        let dir = path_join(clone, "lua")
        fwrite(path_join(dir, "readable/luac/ldo.das"), "// a module of the former default\n")
        fwrite(path_join(dir, "fast/luac/sub/gone.das"), "// stale\n")
        t |> equal(publish(root, ["--repo", clone, "--no-convert", "--allow-dirty"], out), 0, out)
        for (gone in ["readable/luac/ldo.das", "fast/luac/sub/gone.das"]) {
            t |> success(!fexist(path_join(dir, gone)), gone)
        }
        published_modules(t, dir)
    }
}

// a --box this machine accepts: its own box, any box on an unknown CPU
def private flag_box : string {
    let own = box_of(cpu_name())
    return empty(own) ? "fx" : own
}

[test]
def test_fast_lanes(t : T?) {
    t |> run_stand_in("the -fast lanes run the fast variant's modules, a column each beside the readable variant's", "c2das_ports_fast_lanes") @(t : T?; root, clone : string) {
        // the readable variant's entry fails every workload, the fast one runs them
        fwrite(path_join(root, "lua/work/variants/readable/lua/lua.das"), "options gen2\n[export]\ndef main : int \{\n    return 5\n\}\n")
        var out : string
        t |> equal(publish(root, ["--repo", clone, "--no-convert", "--perf", "--samples", "1", "--lanes", "interp,interp-fast,jit-fast", "--allow-dirty", "--box", flag_box()], out), 0, out)
        var name : string
        let c <- capture_of(clone, name)
        t |> equal(c.machine.box, flag_box(), "--box names the box the capture records")
        for (lane in ["interp-fast", "jit-fast"]) {
            let fib <- cell_of(t, c, "fib", lane)
            t |> success(empty(fib.error) && length(fib.samples) == 1, "{lane}: {fib}")
        }
        t |> success(!empty(cell_of(t, c, "fib", "interp").error), "{cell_of(t, c, "fib", "interp")}")
        let readme = fread(path_join(clone, "lua/README.md"))
        for (fact in ["- interpreter, fast: `daslang -load_module <c2das-re>/dasCRuntime -load_module <c2das-re>/c_runtime fast/lua/lua.das --`", "| interpreter, fast / native |", "| interpreter, fast / interpreter |"]) {
            t |> success(readme |> contains(fact), "README lacks {fact}:\n{readme}")
        }
        // the variants table falls back to the capture: the fast column its -fast lanes, the readable
        // column its readable lanes, which stand on no workload here
        t |> success(readme |> contains("its `-fast` lanes"), readme)
        t |> success(line_count(path_join(root, "runs_jit-fast.log")) > 0, "no run of the jit-fast lane carried -jit over the fast tree")
    }
}

[test]
def test_closing_line(t : T?) {
    t |> run_stand_in("a test-suite run without the suite's closing line fails its cell, under the native oracle too, and a differing exit code is reported first", "c2das_ports_closing") @(t : T?; root, clone : string) {
        let args <- ["--repo", clone, "--no-convert", "--perf", "--samples", "1", "--lanes", "interp", "--allow-dirty"]
        var out : string
        // a run that exits 0 without the suite's closing line fails the cell: under the JIT an
        // uncaught Lua error exits 0, so all.lua stops early and still exits 0 (F75)
        fwrite(path_join(root, "lua/work/variants/readable/lua/lua.das"), "options gen2\nrequire strings\n{WORK_LINE_DAS}[export]\ndef main : int \{\n    work_line()\n    let argv <- get_command_line_arguments()\n    let last = argv[length(argv) - 1]\n    print(\"\{last == \"all.lua\" ? \"ALL\" : last\}\\n\")\n    return 0\n\}\n")
        t |> equal(publish(root, args, out), 0, out)
        var readme = fread(path_join(clone, "lua/README.md"))
        t |> success(readme |> contains("- test suite, interpreter: not yet: exited 0 without the line `final OK !!!`; its last line: ALL\n"), readme)
        t |> success(!(readme |> contains("- test suite, clang -O3")), readme)
        // an exit code that differs is reported before the closing line
        fwrite(path_join(root, "lua/work/variants/readable/lua/lua.das"), "options gen2\nrequire strings\n{WORK_LINE_DAS}[export]\ndef main : int \{\n    work_line()\n    let argv <- get_command_line_arguments()\n    let last = argv[length(argv) - 1]\n    print(\"\{last == \"all.lua\" ? \"ALL\" : last\}\\n\")\n    return last == \"all.lua\" ? 3 : 0\n\}\n")
        t |> equal(publish(root, args, out), 0, out)
        readme = fread(path_join(clone, "lua/README.md"))
        t |> success(readme |> contains("- test suite, interpreter: not yet: exited 3 where the native build exits 0: ALL\n"), readme)
        // the native oracle must print the line too: without it there is no oracle
        fwrite(path_join(root, "lua/work/lua.c"), "#include <stdio.h>\nint main(int argc, char **argv) \{\n    printf(\"%s\\n\", argv[argc - 1]);\n    return 0;\n\}\n")
        t |> equal(publish(root, args, out), 0, out)
        readme = fread(path_join(clone, "lua/README.md"))
        t |> success(readme |> contains("- test suite, clang -O3: not yet: exited 0 without the line `final OK !!!`; its last line: all.lua\n"), readme)
        t |> success(readme |> contains("- test suite, interpreter: not yet: no native run to compare with\n"), readme)
    }
}

[test]
def test_work_line(t : T?) {
    t |> run_stand_in("under the wrapper a run without its work seconds fails its cell, so does a line without seconds, and a lane whose warm-up prints none fails whole, the exe lane too", "c2das_ports_work_line") @(t : T?; root, clone : string) {
        let lua_module = path_join(root, "lua/work/variants/readable/lua/lua.das")
        // the line under the warm-up's empty script alone, one without seconds for nbody.lua, the
        // line amid binary_trees.lua's only output line (its halves around it), and two lines for
        // the test suite, as from a program that prints the mark itself
        fwrite(lua_module, "options gen2\nrequire strings\n[export]\ndef main : int \{\n    let argv <- get_command_line_arguments()\n    let last = argv[length(argv) - 1]\n    if (last |> ends_with(\"binary_trees.lua\")) \{\n        print(slice(last, 0, 5))\n        print(\"c2das_work_s=0.002000\\n\")\n        print(\"\{slice(last, 5)\}\\n\")\n        return 0\n    \}\n    if (last == \"all.lua\") \{\n        print(\"c2das_work_s=0.002000\\nc2das_work_s=0.002000\\nfinal OK !!!\\n\")\n        return 0\n    \}\n    if (last |> ends_with(\"empty.lua\")) \{\n        print(\"c2das_work_s=0.002000\\n\")\n    \} elif (last |> ends_with(\"nbody.lua\")) \{\n        print(\"c2das_work_s=soon\\n\")\n    \}\n    print(\"\{last\}\\n\")\n    return 0\n\}\n")
        var out : string
        t |> equal(publish(root, ["--repo", clone, "--no-convert", "--perf", "--samples", "1", "--lanes", "interp", "--allow-dirty"], out), 0, out)
        var readme = fread(path_join(clone, "lua/README.md"))
        t |> success(readme |> contains("- fib, interpreter: not yet: exited 0 under bench/timed.lua with no `c2das_work_s=` line; its last line: "), readme)
        t |> success(readme |> contains("- nbody, interpreter: not yet: exited 0 under bench/timed.lua with `c2das_work_s=soon`, no seconds; its last line: "), readme)
        t |> success(!(readme |> contains("- startup, interpreter")), readme)
        t |> success(readme |> contains("- test suite, interpreter: not yet: exited 0 under bench/timed.lua with 2 `c2das_work_s=` lines; its last line: final OK !!!\n"), readme)
        // the cut joins the halves, so the row matches the native build's
        var name : string
        let c <- capture_of(clone, name)
        let trees <- cell_of(t, c, "binary_trees", "interp")
        t |> success(empty(trees.error) && length(trees.work_samples) == 1 && trees.work_time == 0.002lf, "{trees}")
        // a failed cell records no work sample for a run whose line it could not read
        for (bench in ["fib", "nbody"]) {
            let failed <- cell_of(t, c, bench, "interp")
            t |> success(!empty(failed.error) && length(failed.samples) == 1 && empty(failed.work_samples), "{bench}: {failed}")
        }
        // the work line as the very last bytes of the output, no newline after it
        fwrite(lua_module, "options gen2\nrequire strings\n[export]\ndef main : int \{\n    let argv <- get_command_line_arguments()\n    print(\"\{argv[length(argv) - 1]\}\\nc2das_work_s=0.003000\")\n    return 0\n\}\n")
        t |> equal(publish(root, ["--repo", clone, "--no-convert", "--perf", "--samples", "1", "--lanes", "interp", "--allow-dirty"], out), 0, out)
        var last_name : string
        let last_capture <- capture_of(clone, last_name)
        let fib <- cell_of(t, last_capture, "fib", "interp")
        t |> success(empty(fib.error) && length(fib.work_samples) == 1 && fib.work_time == 0.003lf, "{fib}")
        // no line even under the empty script: the wrapper does not run there, the lane fails whole
        fwrite(lua_module, "options gen2\n[export]\ndef main : int \{\n    let argv <- get_command_line_arguments()\n    print(\"\{argv[length(argv) - 1]\}\\n\")\n    return 0\n\}\n")
        t |> equal(publish(root, ["--repo", clone, "--no-convert", "--perf", "--samples", "1", "--lanes", "interp,exe", "--allow-dirty"], out), 0, out)
        readme = fread(path_join(clone, "lua/README.md"))
        for (lane in ["interpreter", "exe"]) {
            t |> success(readme |> contains("- {lane}, every workload: not yet: the warm-up run of bench/timed.lua over an empty script printed no `c2das_work_s=` line: "), readme)
        }
    }
}

[test]
def test_bench_failures(t : T?) {
    t |> run_stand_in("a missing test-suite folder, a native timeout, a native build that fails beside an earlier binary, failing warm-ups, a capture that is not JSON", "c2das_ports_bench_fails") @(t : T?; root, clone : string) {
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
        fwrite(path_join(root, "lua/work/variants/readable/lua/lua.das"), "options gen2\nrequire strings\nrequire daslib/fio\n{WORK_LINE_DAS}[export]\ndef main : int \{\n    if (fexist(\"all.lua\")) \{\n        print(\"no test folder here\\n\")\n        return 4\n    \}\n    work_line()\n    let argv <- get_command_line_arguments()\n    print(\"\{argv[length(argv) - 1]\}\\n\")\n    return 0\n\}\n")
        t |> equal(publish(root, args, out), 0, out)
        readme = fread(path_join(clone, "lua/README.md"))
        t |> success(readme |> contains("- test suite, interpreter: not yet: the warm-up run exited 4: no test folder here\n"), readme)
        t |> success(readme |> contains("| fib "), readme)
        fwrite(path_join(root, "lua/work/lua.c"), "#include <unistd.h>\nint main(void) \{ sleep(5); return 0; \}\n")
        var timed <- clone_to_move(args)
        timed |> push_from(["--timeout", "1"])
        t |> equal(publish(root, timed, out), 0, out)
        readme = fread(path_join(clone, "lua/README.md"))
        t |> success(readme |> contains("- startup, clang -O3: not yet: timed out after 1 s"), readme)
        // an earlier native binary that would print the right output stays unused
        fwrite(path_join(root, "lua/work/lua.c"), "int main(void) \{ return not_c; \}\n")
        fwrite(path_join(root, "lua/work/bench/lua_native"), "#!/bin/sh\nfor a; do last=$a; done\necho \"$last\"\n")
        run_and_capture(["chmod", "+x", path_join(root, "lua/work/bench/lua_native")], out, 10.0)
        let long_line = repeat("x", 200)
        fwrite(path_join(root, "lua/work/variants/readable/lua/lua.das"), "options gen2\n[export]\ndef main : int \{\n    print(\"{long_line}\\n\")\n    return 3\n\}\n")
        t |> equal(publish(root, ["--repo", clone, "--no-convert", "--perf", "--samples", "1", "--lanes", "jit", "--allow-dirty"], out), 0, out)
        readme = fread(path_join(clone, "lua/README.md"))
        t |> success(readme |> contains("- clang -O3, every workload: not yet: the build failed: "), readme)
        // the native build takes the program's sources from the harness's manifest
        let manifest = path_join(root, "lua/work/lua.program.json")
        let manifest_text = fread(manifest)
        remove(manifest)
        t |> equal(publish(root, ["--repo", clone, "--no-convert", "--perf", "--samples", "1", "--lanes", "jit", "--allow-dirty"], out), 0, out)
        let refused_readme = fread(path_join(clone, "lua/README.md"))
        t |> success(refused_readme |> contains("- clang -O3, every workload: not yet: cannot read lua/work/lua.program.json"), out)
        t |> success(refused_readme |> contains("-o lua_native <the C files of lua/work/lua.program.json> -lm`"), refused_readme)
        fwrite(manifest, manifest_text)
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
    }
}

[test]
def test_head_to_head(t : T?) {
    t |> run_stand_in("the top-level README carries the head-to-head only when the comparison's capture exists, and refuses one that does not read", "c2das_ports_compare") @(t : T?; root, clone : string) {
        let args <- ["--repo", clone, "--no-convert", "--allow-dirty"]
        var out : string
        t |> equal(publish(root, args, out), 0, out)
        t |> success(!(fread(path_join(clone, "README.md")) |> contains("Head-to-head")), out)
        mkdir_rec(path_join(root, "compare"))
        fwrite(path_join(root, "compare/results_linux.json"), "\{\"doom\": \{\"status\": \"pending\", \"reason\": \"P6\"\}\}\n")
        t |> equal(publish(root, args, out), 0, out)
        let readme = fread(path_join(clone, "README.md"))
        t |> success(readme |> contains("\n\n## Head-to-head with the Rust translator\n\nRendered from c2das-re's `compare/results_linux.json` alone"), readme)
        t |> success(readme |> contains("No suite is captured yet."), readme)
        t |> success(readme |> ends_with("Doom: pending (P6).\n\n### Real projects\n\nNo project is captured yet.\n\n### Where the Rust translator is ahead\n\nNowhere in this capture.\n"), readme)
        fwrite(path_join(root, "compare/results_linux.json"), "\{ not json\n")
        t |> equal(publish(root, args, out), 1, out)
        t |> success(out |> contains("ports: "), out)
        t |> equal(fread(path_join(clone, "README.md")), readme, "a refused capture left the README as it was")
    }
}

[test]
def test_earlier_capture(t : T?) {
    t |> run_stand_in("a publish without --perf renders the tables and the projects row from the directory's latest capture, and writes none", "c2das_ports_earlier") @(t : T?; root, clone : string) {
        var c = Capture(program = "lua", commit = OTHER_SHA, command = "scripts/publish_ports.sh --program lua --perf", timestamp = "2026-01-02 03:04 UTC", samples = 1, timeout = 60, machine = Machine(arch = "x86_64", cpu = "Bench CPU"))
        c.lanes <- [Lane(name = "native", command = "run native"), Lane(name = "interp", command = "run interp")]
        c.workloads <- [Workload(name = "startup", args = "-e", startup = true), Workload(name = "fib", args = "bench/fib.lua")]
        c.cells <- [LaneCell(workload = "startup", lane = "native", time = 0.5lf), LaneCell(workload = "startup", lane = "interp", time = 10.0lf), LaneCell(workload = "fib", lane = "native", time = 1.5lf), LaneCell(workload = "fib", lane = "interp", time = 210.0lf)]
        mkdir_rec(path_join(clone, "lua/perf"))
        fwrite(path_join(clone, "lua/perf/capture_2026-01-02T030405Z.json"), write_json(JV(c)) + "\n")
        var out : string
        t |> equal(publish(root, ["--repo", clone, "--no-convert"], out), 0, out)
        let readme = fread(path_join(clone, "lua/README.md"))
        for (fact in ["## Performance\n\nMeasured at c2das-re `{slice(OTHER_SHA, 0, 12)}`, output changed since", "Captured 2026-01-02 03:04 UTC on x86_64, Bench CPU", "- `perf/capture_*.json` - every capture", "| fib      | `bench/fib.lua` | 1.000 s ±0% (by subtraction) | 200.000 s ±0% (by subtraction) |", "| interpreter | 10.000 s ±0% |        20.00 |", "| JIT         |  not measured | not measured |"]) {
            t |> success(readme |> contains(fact), "README lacks {fact}:\n{readme}")
        }
        t |> success(!(readme |> contains(PERF_NOT_YET)), readme)
        let top = fread(path_join(clone, "README.md"))
        t |> success(top |> contains("| [lua](lua/README.md) | 2026-01-02 03:04 UTC | x86_64, Bench CPU |         1 | 200.00 (by subtraction) | not measured |"), top)
        var captures = 0
        dir(path_join(clone, "lua/perf")) $(name) {
            if (name |> ends_with(".json")) {
                captures++
            }
        }
        t |> equal(captures, 1, "a publish without --perf wrote a capture")
    }
}

[test]
def test_criteria_section(t : T?) {
    t |> run_stand_in("the top-level README carries the readability criteria from metrics/criteria_linux.json after the programs and before the head-to-head, none without the file, and refuses one that does not read", "c2das_ports_criteria") @(t : T?; root, clone : string) {
        let args <- ["--repo", clone, "--no-convert", "--allow-dirty"]
        var out : string
        t |> equal(publish(root, args, out), 0, out)
        t |> success(!(fread(path_join(clone, "README.md")) |> contains("Readability criteria")), out)
        mkdir_rec(path_join(root, "metrics"))
        fwrite(path_join(root, "metrics/criteria_linux.json"), fread("metrics/criteria_linux.json"))
        mkdir_rec(path_join(root, "compare"))
        fwrite(path_join(root, "compare/results_linux.json"), "\{\"doom\": \{\"status\": \"pending\", \"reason\": \"P6\"\}\}\n")
        t |> equal(publish(root, args, out), 0, out)
        let readme = fread(path_join(clone, "README.md"))
        let section = "\n\n## Readability criteria\n\nThe compliance, in percent, per criterion and per input group, from c2das-re's `metrics/criteria_linux.json`: it counts lines and reads no clock, so it holds on any machine.\n\n| Criterion "
        let at = find(readme, section)
        t |> success(at > find(readme, "## Programs") && at < find(readme, "## Head-to-head"), readme)
        t |> success(readme |> contains("| **total** "), readme)
        fwrite(path_join(root, "metrics/criteria_linux.json"), "\{ not json\n")
        t |> equal(publish(root, args, out), 1, out)
        t |> success(out |> contains("ports: metrics/criteria_linux.json: "), out)
        t |> equal(fread(path_join(clone, "README.md")), readme, "a refused capture left the README as it was")
    }
}

[test]
def test_raw_captures(t : T?) {
    t |> run_stand_in("the raw captures present in the c2das-re tree are copied whole under their own paths, named in the top README and committed", "c2das_ports_raw") @(t : T?; root, clone : string) {
        let present <- ["compare/results_linux.json", "metrics/criteria_linux.json", "perf/results_linux.json", "perf/results_method_linux.json"]
        for (rel in present) {
            mkdir_rec(path_join(root, dir_name(rel)))
        }
        fwrite(path_join(root, "compare/results_linux.json"), "\{\"doom\": \{\"status\": \"pending\", \"reason\": \"P6\"\}\}\n")
        fwrite(path_join(root, "metrics/criteria_linux.json"), fread("metrics/criteria_linux.json"))
        fwrite(path_join(root, "perf/results_linux.json"), "\{\"tests\": \{\}\}\n")
        fwrite(path_join(root, "perf/results_method_linux.json"), "\{\"method\": 1\}\n")
        // a stale copy in the clone is replaced whole
        mkdir_rec(path_join(clone, "perf"))
        fwrite(path_join(clone, "perf/results_linux.json"), "stale\n")
        fwrite(path_join(clone, "perf/dasprofile_linux.json"), "earlier\n")
        var out : string
        t |> equal(publish(root, ["--repo", clone, "--no-convert", "--allow-dirty", "--commit"], out), 0, out)
        for (rel in present) {
            t |> equal(fread(path_join(clone, rel)), fread(path_join(root, rel)), rel)
        }
        // a copy the tree no longer has stays, and is named
        t |> equal(fread(path_join(clone, "perf/dasprofile_linux.json")), "earlier\n")
        let top = fread(path_join(clone, "README.md"))
        t |> success(top |> contains("\nRaw captures beside this README, each copied whole from c2das-re when its tree holds it: `compare/results_linux.json`, `metrics/criteria_linux.json`, `perf/results_linux.json`, `perf/results_method_linux.json`, `perf/dasprofile_linux.json`.\n"), top)
        t |> equal(git(clone, ["status", "--porcelain"]), "", "the raw copies are committed")
    }
    t |> run_stand_in("a raw copy that cannot be written fails the publish", "c2das_ports_raw_unwritable") @(t : T?; root, clone : string) {
        mkdir_rec(path_join(root, "perf"))
        fwrite(path_join(root, "perf/results_linux.json"), "\{\"tests\": \{\}\}\n")
        // a folder where the copy goes: no write succeeds there, root or not
        mkdir_rec(path_join(clone, "perf/results_linux.json"))
        var out : string
        t |> equal(publish(root, ["--repo", clone, "--no-convert", "--allow-dirty"], out), 1, out)
        t |> success(out |> contains("ports: cannot write {path_join(clone, "perf/results_linux.json")}"), out)
    }
}

// a stand-in project of the Rust checkout `<root>/rust`: its folder's `files` (paths under it, then
// text)
def private stand_in_project(root, name : string; files : array<tuple<path : string; text : string>>) {
    let dir = path_join(root, "rust/tests/manual/{name}")
    for (f in files) {
        mkdir_rec(dir_name(path_join(dir, f.path)))
        fwrite(path_join(dir, f.path), f.text)
    }
}

// binjgb converts whole; wasm3's unit includes the `all.c` graph, one file of which holds a
// variable-length array, so the program refuses and its files convert one by one
def private stand_in_projects(root : string) {
    let cases = "\{\"cases\": [\{\"id\": \"binjgb-cgb-acid2-std\", \"expected\": \{\"stdout\": \"hi\\n\"\}\}, \{\"id\": \"wasm3-fib32-std\", \"expected\": \{\"stdout\": \"\"\}\}]\}\n"
    mkdir_rec(path_join(root, "rust/tests/canonical"))
    fwrite(path_join(root, "rust/LICENSE"), "BSD stand-in\n")
    fwrite(path_join(root, "rust/tests/canonical/cases.json"), cases)
    stand_in_project(root, "binjgb", [
        (path = "src/binjgb_all.c", text = "#include <stdio.h>\nint main(void) \{ printf(\"hi\\n\"); return 0; \}\n"),
        (path = "upstream/binjgb/LICENSE", text = "MIT stand-in for binjgb\n")])
    stand_in_project(root, "wasm3", [
        (path = "src/all_host.c", text = "#include \"all.c\"\n#include \"host.c\"\n"),
        (path = "src/all.c", text = "#include <stdio.h>\n#include \"m3_add.c\"\n#include \"m3_vla.c\"\n"),
        (path = "src/host.c", text = "int main(void) \{ return 0; \}\n"),
        (path = "upstream/wasm3/source/m3_add.c", text = "int add(int a, int b) \{ return a + b; \}\n"),
        (path = "upstream/wasm3/source/m3_vla.c", text = "int first(int n) \{ int a[n + 1]; a[0] = n; return a[0]; \}\n"),
        (path = "upstream/wasm3/LICENSE", text = "MIT stand-in for wasm3\n")])
}

// the head-to-head capture of the stand-in root, an entry for binjgb alone, committed
def private stand_in_compare(root : string) {
    let entry = "\{\"date\": \"2029-01-01 00:00 UTC\", \"box\": \"PC\", \"samples\": 3, \"lanes\": [\"interp\"], \"native\": \{\"status\": \"pass\"\}, \"native_compiler\": \"clang version 99\", \"ours\": \{\"error\": \"\", \"lanes\": \{\"interp\": \{\"status\": \"pass\"\}\}\}, \"rust\": \{\"error\": \"\", \"lanes\": \{\"interp\": \{\"status\": \"pass\"\}\}\}, \"speed\": \{\"native\": \{\"decode\": \{\"time\": 0.5, \"spread\": 0.01\}\}, \"ours\": \{\"interp\": \{\"decode\": \{\"time\": 4.0, \"spread\": 0.01\}\}\}, \"rust\": \{\"interp\": \{\"decode\": \{\"time\": 3.0, \"spread\": 0.01\}\}\}\}\}"
    mkdir_rec(path_join(root, "compare"))
    fwrite(path_join(root, "compare/results_linux.json"), "\{\"projects\": \{\"binjgb\": {entry}\}\}\n")
    // the criteria capture, with a row for wasm3 alone
    var cap : CriteriaCapture
    cap.rows["project/wasm3"] <- sum_raw([{"c_files" => 3, "c_files_converted" => 2, "fn_matched" => 2}], array<int>(), array<int>())
    mkdir_rec(path_join(root, "metrics"))
    fwrite(path_join(root, "metrics/criteria_linux.json"), criteria_text(cap))
    git(root, ["add", "-A"])
    git(root, ["commit", "-q", "-m", "capture"])
}

[test]
def test_projects(t : T?) {
    t |> run_stand_in("a compare project converts whole, or file by file with the refusal named; the speed from the head-to-head under the commit that recorded it", "c2das_ports_projects") @(t : T?; root, clone : string) {
        stand_in_projects(root)
        stand_in_compare(root)
        let captured_at = git(root, ["rev-parse", "HEAD"])
        var out : string
        t |> equal(publish(root, ["--repo", clone, "--program", "binjgb", "--commit"], out), 0, out)
        let readme = fread(path_join(clone, "binjgb/README.md"))
        for (v in ["readable", "fast"]) {
            t |> success(readme |> contains("### `{v}/`\n\nThe program converts whole: `{v}/binjgb_all/` holds it"), readme)
            t |> success(fexist(path_join(clone, "binjgb/{v}/binjgb_all/binjgb_all.das")), out)
            let sidecar = fread(path_join(clone, "binjgb/{v}/binjgb.c2das"))
            t |> success(sidecar |> contains("\"<c2das>/tests/manual/binjgb/include\"") && sidecar |> contains("\"fn_macros\"") && !(sidecar |> contains(root)), sidecar)
            t |> equal(fread(path_join(clone, "binjgb/{v}/variant.json")), fread(path_join(root, "ports/variants/binjgb.{v}.json")))
        }
        // the variants table: the readable column falls back to the head-to-head's entry, 4.0 s over 0.5 s
        for (fact in ["## Variants\n\n- `readable/` - for reading", "| x native, interpreter ", " 8.00 (1) | ", "(1) not from a search of the variant: c2das-re's `compare/results_linux.json`, the project's entry measured 2029-01-01 00:00 UTC", "-jit fast/binjgb_all/binjgb_all.das -- "]) {
            t |> success(readme |> contains(fact), "README lacks {fact}:\n{readme}")
        }
        t |> success(!(readme |> contains("luaV_execute")), readme)
        t |> success(fread(path_join(clone, "binjgb/LICENSE")) |> contains("upstream/binjgb/LICENSE:\n\nMIT stand-in for binjgb\n"))
        t |> success(fread(path_join(clone, "binjgb/LICENSE")) |> contains("src/ and include/ of tests/manual/binjgb (the files of lookibed/c2das itself, its LICENSE):\n\nBSD stand-in\n"))
        t |> success(readme |> contains("| Ours | clang version 99 | 0.500000 |        8.00 |"), readme)
        t |> success(readme |> contains("## Readability criteria\n\nnot yet: c2das-re's `metrics/criteria_linux.json` holds no row `project/binjgb`; "), readme)
        // no converter commit since the entry's date: its date and the capture's commit, no change
        t |> success(readme |> contains("Measured 2029-01-01 00:00 UTC (capture committed at c2das-re `{slice(captured_at, 0, 12)}`).\n"), readme)
        t |> equal(git(clone, ["log", "-1", "--format=%s"]), "binjgb: regenerated from c2das-re v9.9.9-1-g{slice(captured_at, 0, 7)} ({captured_at})")
        // a later commit that leaves the converter as it was: the commit named, the output the same
        fwrite(path_join(root, "notes.txt"), "a note\n")
        git(root, ["add", "-A"])
        git(root, ["commit", "-q", "-m", "a note"])
        t |> equal(publish(root, ["--repo", clone, "--program", "binjgb"], out), 0, out)
        let same = fread(path_join(clone, "binjgb/README.md"))
        t |> success(same |> contains("Measured 2029-01-01 00:00 UTC (capture committed at c2das-re `{slice(captured_at, 0, 12)}`).\n"), same)
        t |> success(!(same |> contains("output changed since")), same)
        // a converter change after the capture: the output changed since
        mkdir_rec(path_join(root, "converter"))
        fwrite(path_join(root, "converter/changed.das"), "// changed\n")
        git(root, ["add", "-A"])
        // committed after the entry's date, as a converter change after a capture is
        var committed : string
        run_and_capture(["env", "GIT_COMMITTER_DATE=2030-01-01T00:00:00Z", "git", "-C", root, "-c", "user.name=test", "-c", "user.email=test@example.invalid", "commit", "-q", "-m", "converter"], committed, 60.0)
        t |> equal(publish(root, ["--repo", clone, "--program", "binjgb"], out), 0, out)
        let stale = fread(path_join(clone, "binjgb/README.md"))
        t |> success(stale |> contains("Measured 2029-01-01 00:00 UTC (capture committed at c2das-re `{slice(captured_at, 0, 12)}`), output changed since: the converter changed after that date"), stale)
        // wasm3 refuses whole; its files convert one by one, the refused one named
        t |> equal(publish(root, ["--repo", clone, "--program", "wasm3"], out), 0, out)
        let wasm3 = fread(path_join(clone, "wasm3/README.md"))
        t |> success(wasm3 |> contains("The program does not convert whole yet: "), wasm3)
        t |> success(wasm3 |> contains("variable-length array"), wasm3)
        t |> success(wasm3 |> contains("2 of 3"), wasm3)
        t |> success(wasm3 |> contains("| upstream/wasm3/source/m3_add.c | converted "), wasm3)
        t |> success(wasm3 |> contains("| upstream/wasm3/source/m3_vla.c | refused: "), wasm3)
        t |> success(wasm3 |> contains("not yet: c2das-re's `compare/results_linux.json` holds no entry for wasm3."), wasm3)
        // the criteria from the capture's row, recorded before the converter change
        t |> success(wasm3 |> contains("## Readability criteria\n\nFrom c2das-re's `metrics/criteria_linux.json` (`scripts/run_criteria.sh`), its row `project/wasm3`, recorded at c2das-re `{slice(captured_at, 0, 12)}`, output changed since: "), wasm3)
        t |> success(wasm3 |> contains("Measured on the 2 of 3 C files that convert alone"), wasm3)
        t |> success(wasm3 |> contains("| project/wasm3 |"), wasm3)
        t |> success(fexist(path_join(clone, "wasm3/fast/files/upstream/wasm3/source/m3_add/m3_add.das")), out)
        t |> success(fexist(path_join(clone, "wasm3/readable/files/src/host/host.das")), out)
        t |> success(!fexist(path_join(clone, "wasm3/readable/files/upstream/wasm3/source/m3_vla/m3_vla.das")), out)
        t |> success(!fexist(path_join(clone, "wasm3/readable/all_host")), out)
        t |> success(wasm3 |> contains("# readable/: not runnable yet"), wasm3)
        // --no-convert publishes no project
        t |> equal(publish(root, ["--repo", clone, "--program", "wasm3", "--no-convert"], out), 0, out)
        t |> success(out |> contains("wasm3: not published: a compare project converts on every publish"), out)
    }
}

[test]
def test_convert_variant(t : T?) {
    t |> run_stand_in("a project variant converts in a process of its own: the child writes the conversion as JSON, and refuses a program that is no compare project", "c2das_ports_convert_variant") @(t : T?; root, clone : string) {
        stand_in_projects(root)
        var out : string
        let results = path_join(root, "conversion.json")
        t |> equal(publish(root, ["--program", "wasm3", "--convert-variant", "fast", "--results", results], out), 0, out)
        let conversion = fread(results)
        t |> success(conversion |> contains("variable-length array") && conversion |> contains("upstream/wasm3/source/m3_add.c"), conversion)
        t |> success(fexist(path_join(root, "compare/work/ports/wasm3/fast/files/upstream/wasm3/source/m3_add/m3_add.das")), out)
        t |> equal(publish(root, ["--program", "lua", "--convert-variant", "fast", "--results", results], out), 1, out)
        t |> success(out |> contains("--convert-variant takes a compare project, not `lua`"), out)
        // the parent's publish refuses a tree with uncommitted files
        remove(results)
        git(root, ["add", "-A"])
        git(root, ["commit", "-q", "-m", "projects"])
        t |> equal(publish(root, ["--repo", clone, "--program", "binjgb"], out), 0, out)
        t |> success(out |> contains("binjgb: the fast variant converts in a process of its own: "), out)
    }
}

[test]
def test_project_refusal(t : T?) {
    t |> run_stand_in("a project without a license refuses before the first write into the clone; the others publish, commit and push, and the top README names the failure", "c2das_ports_project_refusal") @(t : T?; root, clone : string) {
        stand_in_projects(root)
        remove(path_join(root, "rust/tests/manual/binjgb/upstream/binjgb/LICENSE"))
        git(root, ["add", "-A"])
        git(root, ["commit", "-q", "-m", "projects"])
        var out : string
        t |> equal(publish(root, ["--repo", clone, "--commit", "--push"], out), 1, out)
        t |> success(out |> contains("ports: failed: binjgb: no license file or SPDX notice under "), out)
        t |> success(!fexist(path_join(clone, "binjgb")), out)
        t |> success(fexist(path_join(clone, "lua/README.md")) && fexist(path_join(clone, "wasm3/README.md")), out)
        let top = fread(path_join(clone, "README.md"))
        t |> success(top |> contains("## Directories\n\n- [lua](lua/)\n- [wasm3](wasm3/)\n"), top)
        t |> success(top |> contains("\n- binjgb: no license file or SPDX notice under "), top)
        t |> equal(git(clone, ["status", "--porcelain"]), "", "the failure line is committed")
        t |> equal(git(path_join(root, "ports.git"), ["rev-parse", "HEAD"]), git(clone, ["rev-parse", "HEAD"]), "what was committed is pushed")
    }
}

[test]
def test_apart(t : T?) {
    t |> run_stand_in("each program in a process of its own, a skipped one in none; a process that ends without an outcome is a failure naming how it ended, and the next program still publishes", "c2das_ports_apart_killed") @(t : T?; root, clone : string) {
        stand_in_projects(root)
        // the harness kills the publisher's process that runs it
        fwrite(path_join(root, "lua/run.das"), "options gen2\nrequire daslib/fio\n[export]\ndef main : int \{\n    unsafe(system(\"kill -KILL $(ps -o ppid= -p $PPID)\"))\n    return 0\n\}\n")
        git(root, ["add", "-A"])
        git(root, ["commit", "-q", "-m", "projects"])
        var out : string
        t |> equal(publish(root, ["--repo", clone], out), 1, out)
        t |> success(out |> contains("ports: failed: lua: the publish process was killed by signal 9 without an outcome"), out)
        t |> success(fexist(path_join(clone, "binjgb/README.md")) && !fexist(path_join(clone, "lua/README.md")), out)
        for (name in ["lua", "wasm3", "binjgb"]) {
            t |> success(out |> contains("{name}: in a process of its own: exec "), out)
        }
        t |> success(out |> contains("puredoom: not published: this tree has no doom/run.das") && !(out |> contains("puredoom: in a process of its own")), out)
    }
}

[test]
def test_project_criteria_provenance(t : T?) {
    t |> run_stand_in("a project's criteria: a change to the criteria's computation after the capture is a change since, a metrics-only commit is not; a dirty capture names no commit", "c2das_ports_criteria_provenance") @(t : T?; root, clone : string) {
        stand_in_projects(root)
        stand_in_compare(root)
        let captured_at = git(root, ["rev-parse", "HEAD"])
        var out : string
        t |> equal(publish(root, ["--repo", clone, "--program", "wasm3"], out), 0, out)
        let same = fread(path_join(clone, "wasm3/README.md"))
        t |> success(same |> contains("its row `project/wasm3`, recorded at c2das-re `{slice(captured_at, 0, 12)}`. Measured on "), same)
        mkdir_rec(path_join(root, "metrics/tests"))
        fwrite(path_join(root, "metrics/tests/test_criteria.das"), "// changed\n")
        fwrite(path_join(root, "metrics/ARCHITECTURE.md"), "# changed\n")
        git(root, ["add", "-A"])
        git(root, ["commit", "-q", "-m", "metrics only"])
        t |> equal(publish(root, ["--repo", clone, "--program", "wasm3"], out), 0, out)
        let metrics_only = fread(path_join(clone, "wasm3/README.md"))
        t |> success(metrics_only |> contains("its row `project/wasm3`, recorded at c2das-re `{slice(captured_at, 0, 12)}`. Measured on "), metrics_only)
        fwrite(path_join(root, "metrics/criteria_count.das"), "// changed\n")
        git(root, ["add", "-A"])
        git(root, ["commit", "-q", "-m", "criteria"])
        t |> equal(publish(root, ["--repo", clone, "--program", "wasm3"], out), 0, out)
        let changed = fread(path_join(clone, "wasm3/README.md"))
        t |> success(changed |> contains("recorded at c2das-re `{slice(captured_at, 0, 12)}`, output changed since: "), changed)
        var cap : CriteriaCapture
        cap.rows["project/wasm3"] <- sum_raw([{"c_files" => 4, "c_files_converted" => 2, "fn_matched" => 2}], array<int>(), array<int>())
        fwrite(path_join(root, "metrics/criteria_linux.json"), criteria_text(cap))
        t |> equal(publish(root, ["--repo", clone, "--program", "wasm3", "--allow-dirty"], out), 0, out)
        let dirty = fread(path_join(clone, "wasm3/README.md"))
        t |> success(dirty |> contains("its row `project/wasm3`, not committed yet. Measured on the 2 of 4 C files"), dirty)
    }
}

[test]
def test_stale_capture(t : T?) {
    t |> run_stand_in("a capture measured at another commit carries that commit, and the output changed since", "c2das_ports_stale_capture") @(t : T?; root, clone : string) {
        var c = Capture(program = "lua", commit = OTHER_SHA, timestamp = "2026-11-07 04:04 UTC", samples = 1, timeout = 1)
        c.workloads |> push(Workload(name = "startup", startup = true))
        mkdir_rec(path_join(clone, "lua/perf"))
        fwrite(path_join(clone, "lua/perf/capture_2026-11-07T040400Z.json"), write_json(JV(c)) + "\n")
        var out : string
        t |> equal(publish(root, ["--repo", clone, "--no-convert", "--program", "lua"], out), 0, out)
        let readme = fread(path_join(clone, "lua/README.md"))
        t |> success(readme |> contains("## Performance\n\nMeasured at c2das-re `{slice(OTHER_SHA, 0, 12)}`, output changed since"), readme)
    }
}

// the stand-in `doom/` harness of `root`, committed, with its work and fetch trees ignored as the
// repository ignores them: a converted tree with a C-IR file beside its modules, the verdicts of
// a publish's runs (`sync`, none when empty) and the conversion's stamp naming the new HEAD; the
// fetched commit holds a wad, which the publish never copies
def private stand_in_doom(root, sync : string) {
    fwrite(path_join(root, "VERSIONS.md"), VERSIONS + "puredoom: 355cfbd16fac (stand-in)\nfreedoom: 0.13.0 (stand-in)\n")
    mkdir_rec(path_join(root, "doom/patches"))
    fwrite(path_join(root, "doom/run.das"), "// stand-in\n")
    fwrite(path_join(root, "doom/doom.c2das"), "\{\"defines\": [\"DOOM\"]\}\n")
    fwrite(path_join(root, "doom/patches/0001-a.patch"), "first patch.\n\nCopyright.\n\n- a.c: does a.\n\ndiff --git a/a.c b/a.c\n")
    fwrite(path_join(root, ".gitignore"), fread(path_join(root, ".gitignore")) + "/doom/work/\n/doom/fetch/\n")
    git(root, ["add", "-A"])
    git(root, ["commit", "-q", "-m", "doom"])
    for (v in ["readable", "fast"]) {
        let tree = path_join(root, "doom/work/variants/{v}/source")
        mkdir_rec(tree)
        fwrite(path_join(tree, "doom_main.das"), "// main {v}\n")
        fwrite(path_join(tree, "doom_main.cir.json"), "\{\}\n")
        fwrite(path_join(tree, "program.modules.txt"), "doom_main.das\n")
        fwrite(path_join(tree, "program.layout.txt"), "doom_main\n")
        if (!empty(sync)) {
            fwrite(path_join(root, "doom/work/variants/{v}/publish_sync.txt"), sync)
        }
    }
    mkdir_rec(path_join(root, "doom/fetch/PureDOOM"))
    fwrite(path_join(root, "doom/fetch/PureDOOM/LICENSE"), "GNU GENERAL PUBLIC LICENSE Version 2\n")
    fwrite(path_join(root, "doom/fetch/PureDOOM/doom1.wad"), "IWAD")
    fwrite(path_join(root, "doom/work/publish.generation"), "{git(root, ["rev-parse", "HEAD"])}\nv9.9.9-1\n{git(root, ["log", "-1", "--format=%cs"])}\n")
}

[test]
def test_puredoom(t : T?) {
    t |> run_stand_in("a tree without doom/ publishes every other program and skips PureDOOM", "c2das_ports_no_doom") @(t : T?; root, clone : string) {
        var out : string
        t |> equal(publish(root, ["--repo", clone, "--no-convert", "--program", "puredoom"], out), 0, out)
        t |> success(out |> contains("puredoom: not published: this tree has no doom/run.das"), out)
        t |> success(!fexist(path_join(clone, "puredoom")), out)
    }
    t |> run_stand_in("puredoom/: the listed tree, the sidecar, the patches, the license, the sync table, no wad", "c2das_ports_doom") @(t : T?; root, clone : string) {
        stand_in_doom(root, "interp\t1\t2664 tics in sync\njit\t2\tfails: exit 1\n")
        var out : string
        t |> equal(publish(root, ["--repo", clone, "--no-convert", "--program", "puredoom", "--commit"], out), 0, out)
        let dir = path_join(clone, "puredoom")
        for (v in ["readable", "fast"]) {
            t |> equal(fread(path_join(dir, "{v}/doom/doom_main.das")), "// main {v}\n")
            t |> equal(fread(path_join(dir, "{v}/doom/program.layout.txt")), "doom_main\n")
            t |> success(!fexist(path_join(dir, "{v}/doom/doom_main.cir.json")))
            let sidecar = fread(path_join(dir, "{v}/doom.c2das"))
            t |> success(sidecar |> contains("\"DOOM\"") && sidecar |> contains("\"fn_macros\" : \"fold\""), sidecar)
            t |> equal(fread(path_join(dir, "{v}/variant.json")), fread(path_join(root, "ports/variants/puredoom.{v}.json")))
        }
        t |> equal(fread(path_join(dir, "LICENSE")), "GNU GENERAL PUBLIC LICENSE Version 2\n")
        t |> success(fexist(path_join(dir, "patches/0001-a.patch")))
        let readme = fread(path_join(dir, "README.md"))
        t |> success(readme |> contains("at `355cfbd16fac`, patched"), readme)
        t |> success(readme |> contains("  - `0001-a.patch` - first patch. a.c: does a.\n"), readme)
        t |> success(readme |> contains("`readable/`:\n\n") && readme |> contains("\n`fast/`:\n\n") && readme |> contains("## Variants\n\n- `readable/` - for reading"), readme)
        t |> success(readme |> contains("| interp | 2664 tics in sync | not run       | not run |"), readme)
        t |> success(readme |> contains("| jit    | not run           | fails: exit 1 | not run |"), readme)
        t |> success(readme |> contains("## Performance\n\nnot yet: "), readme)
        t |> equal(git(clone, ["log", "-1", "--format=%s"]), "puredoom: regenerated from c2das-re v9.9.9-1 ({git(root, ["rev-parse", "HEAD"])})")
        t |> success(!(git(clone, ["ls-files"]) |> contains(".wad")), git(clone, ["ls-files"]))
        t |> success(fread(path_join(clone, "README.md")) |> contains("- [puredoom](puredoom/)\n"))
    }
    t |> run_stand_in("no sync verdicts: refused before the first write", "c2das_ports_doom_refused") @(t : T?; root, clone : string) {
        stand_in_doom(root, "")
        let head = git(clone, ["rev-parse", "HEAD"])
        var out : string
        t |> equal(publish(root, ["--repo", clone, "--no-convert", "--program", "puredoom", "--commit"], out), 1, out)
        t |> success(out |> contains("no demo verdicts in doom/work/variants/readable/publish_sync.txt"), out)
        untouched(t, clone, head, out)
        t |> success(!fexist(path_join(clone, "puredoom")), out)
    }
}
