options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require ../tiers.das

//! The `exe` and `aot` builds of `run_tier` and `build_tier`: a binary is reused while the program,
//! its module folders and the daslang checkout are unchanged, and built again when any of them is.

// no module folders, flags or program arguments
let NO_ARGS : array<string>

// `helper.das` of the test program: a module whose `value` is `n`
def private helper_text(n : int) : string => "options gen2\nmodule helper public\ninclude helper_part.das.inc\ndef value() : int \{\n    return {n} + part()\n\}\n"

// a program in `dir` exiting `n`: `main.das` requires `helper.das`, which includes a fragment;
// `unrelated.das` beside them belongs to none of it; `mods/m/` stands for a module folder
def private write_program(dir : string; n : int) : string {
    let das_path = path_join(dir, "main.das")
    fwrite(das_path, "options gen2\nrequire helper\n[export]\ndef main() : int \{\n    return value()\n\}\n")
    fwrite(path_join(dir, "helper.das"), helper_text(n))
    fwrite(path_join(dir, "helper_part.das.inc"), "def part() : int \{\n    return 0\n\}\n")
    fwrite(path_join(dir, "unrelated.das"), "options gen2\n")
    mkdir_rec(path_join(dir, "mods/m/tests"))
    fwrite(path_join(dir, "mods/m/m.das"), "options gen2\n")
    fwrite(path_join(dir, "mods/m/tests/t.das"), "options gen2\n")
    return das_path
}

[test]
def test_build_key(t : T?) {
    var dir_error : string
    let dir = create_temp_directory("c2das_build_key", dir_error)
    if (!empty(dir_error)) {
        t |> failure("no temp directory: {dir_error}")
        return
    }
    let das_path = write_program(dir, 7)
    let key = build_key(das_path, "aot", dir, [path_join(dir, "mods/m")], NO_ARGS)
    t |> run("the key names the tier, the daslang checkout, the program's files and the module folders' own") @(t : T?) {
        t |> success(key |> starts_with("tier aot\ndaslang "), key)
        for (name in ["main.das", "helper.das", "helper_part.das.inc", "mods/m/m.das", "liblibDaScript.a"]) {
            t |> success(key |> contains(name), "{name}: {key}")
        }
        t |> success(!(key |> contains("unrelated.das")), key)
        t |> success(!(key |> contains("mods/m/tests")), key)
    }
    t |> run("a change to a required file, a module folder's file, the tier or the exe flags changes the key") @(t : T?) {
        fwrite(path_join(dir, "helper.das"), helper_text(8))
        t |> success(build_key(das_path, "aot", dir, [path_join(dir, "mods/m")], NO_ARGS) != key)
        let changed = build_key(das_path, "aot", dir, [path_join(dir, "mods/m")], NO_ARGS)
        fwrite(path_join(dir, "mods/m/m.das"), "options gen2\n// changed\n")
        t |> success(build_key(das_path, "aot", dir, [path_join(dir, "mods/m")], NO_ARGS) != changed)
        let exe = build_key(das_path, "exe", dir, [path_join(dir, "mods/m")], NO_ARGS)
        t |> success(exe != build_key(das_path, "aot", dir, [path_join(dir, "mods/m")], NO_ARGS))
        t |> success(exe != build_key(das_path, "exe", dir, [path_join(dir, "mods/m")], ["-no-module-cache"]))
    }
    t |> run("a file outside the program does not change the key") @(t : T?) {
        let before = build_key(das_path, "aot", dir, [path_join(dir, "mods/m")], NO_ARGS)
        fwrite(path_join(dir, "unrelated.das"), "options gen2\n// changed\n")
        t |> equal(build_key(das_path, "aot", dir, [path_join(dir, "mods/m")], NO_ARGS), before)
    }
    rmdir_rec(dir)
}

[test]
def test_binary_argv(t : T?) {
    t |> run("the program's arguments follow an exe binary, and `--` under aot; none, no `--`") @(t : T?) {
        t |> equal(join(binary_argv("exe", "b", ["-x"]), " "), "b -x")
        t |> equal(join(binary_argv("aot", "b", ["-x"]), " "), "b -- -x")
        let none : array<string>
        t |> equal(join(binary_argv("aot", "b", none), " "), "b")
    }
}

[test(timeout = 1200)]
def test_build_reuse(t : T?) {
    var dir_error : string
    let dir = create_temp_directory("c2das_build_reuse", dir_error)
    if (!empty(dir_error)) {
        t |> failure("no temp directory: {dir_error}")
        return
    }
    for (tier in ["exe", "aot"]) {
        let work = path_join(dir, tier)
        mkdir_rec(work)
        let das_path = write_program(work, 7)
        t |> run("{tier}: the first run builds, a second one reuses the binary, a changed program builds again") @(t : T?) {
            var out : string
            let first = build_tier(das_path, tier, work, out, NO_ARGS, 600.0, NO_ARGS)
            t |> equal(first.rc, 0, out)
            t |> success(!first.reused, "the first build reused a binary")
            t |> equal(first.bin, tier_binary(das_path, tier, work))
            t |> equal(run_tier(das_path, tier, work, out, NO_ARGS), 7, out)
            let second = build_tier(das_path, tier, work, out, NO_ARGS, 600.0, NO_ARGS)
            t |> equal(second.rc, 0, out)
            t |> success(second.reused, "a second build of the same program built again")
            fwrite(path_join(work, "helper.das"), helper_text(9))
            let changed = build_tier(das_path, tier, work, out, NO_ARGS, 600.0, NO_ARGS)
            t |> equal(changed.rc, 0, out)
            t |> success(!changed.reused, "a changed required file reused the old binary")
            t |> equal(run_tier(das_path, tier, work, out, NO_ARGS), 9, out)
        }
        t |> run("{tier}: a binary replaced since its build is built again") @(t : T?) {
            let bin = tier_binary(das_path, tier, work)
            fwrite(bin, "#!/bin/sh\nexit 3\n")
            var out : string
            let rebuilt = build_tier(das_path, tier, work, out, NO_ARGS, 600.0, NO_ARGS)
            t |> success(!rebuilt.reused, "the replaced binary was reused")
            t |> equal(run_tier(das_path, tier, work, out, NO_ARGS), 9, out)
        }
    }
    t |> run("a failed build leaves neither the earlier binary nor a key, so the next run builds again") @(t : T?) {
        let work = path_join(dir, "exe")
        let das_path = path_join(work, "main.das")
        var out : string
        t |> success(run_tier(das_path, "exe", work, out, NO_ARGS, 600.0, ["-bogus-flag"]) != 0, out)
        t |> success(!fexist(exe_binary(das_path, work) + ".key"))
        t |> success(!fexist(exe_binary(das_path, work)))
        let next = build_tier(das_path, "exe", work, out, NO_ARGS, 600.0, NO_ARGS)
        t |> success(!next.reused)
    }
    rmdir_rec(dir)
}
