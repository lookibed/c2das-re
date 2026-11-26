options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require dastest/review_gate
require ../REVIEW.das

//! `frontend/REVIEW.das` on stand-in files under a temp folder: each ban fires with the file and
//! line, through a `require` that names a file too, and nothing else fires.

// the gate's findings on `entry` of the stand-in files `files` (name, text), written under a fresh
// folder, a line each with the folder cut off
def private findings_of(t : T?; files : array<tuple<name : string; text : string>>; entry : string) : string {
    let folder = path_join(test_temp_dir(), "gate_{length(test_temp_dir())}_{entry}")
    mkdir_rec(folder)
    for (file in files) {
        fwrite(path_join(folder, file.name), file.text)
    }
    gate_reset()
    var checked : table<string>
    check_file(path_join(folder, entry), path_join(folder, entry), checked)
    var found <- gate_findings()
    gate_reset()
    for (finding in found) {
        t |> success(finding |> starts_with(folder), finding)
    }
    return join([for (finding in found); slice(finding, length(folder) + 1)], "\n")
}

[test(description = "the frontend gate reports a require of the clang binding and a call that starts a process, in a file and in what it requires")]
def test_frontend_gate(t : T?) {
    t |> run("a file with neither is clean, a comment and a longer name included") @(t : T?) {
        let found = findings_of(t, [(name = "a.das", text = "options gen2\nrequire strings\n// {SPAWNERS[0]}(x)\n/* {SPAWNERS[0]}(x)\n /* require {CLANG_MODULE} */ {SPAWNERS[0]} */\nlet n = my_{SPAWNERS[0]}(1) + {CLANG_MODULE}(2)\nlet s = \"{SPAWNERS[0]}(x) \\\" require {CLANG_MODULE}\"\nlet c = '\"'\n")], "a.das")
        t |> equal(found, "")
    }
    t |> run("a require of the clang binding or a submodule of it is a finding at its line") @(t : T?) {
        for (target in [CLANG_MODULE, "{CLANG_MODULE}/cbind_boost"]) {
            let found = findings_of(t, [(name = "a.das", text = "options gen2\nrequire {target} public\n")], "a.das")
            t |> equal(found, "a.das:2: requires `{CLANG_MODULE}`: nothing under frontend/ needs clang")
        }
        let other = findings_of(t, [(name = "a.das", text = "require {CLANG_MODULE}_like\n")], "a.das")
        t |> equal(other, "")
    }
    t |> run("the functions that start a process are fio's and crt's") @(t : T?) {
        for (name in fixed_array("popen", "popen_binary", "popen_timeout", "popen_argv", "popen_argv_pipe", "spawn_process", "spawn_argv", "with_process", "run_and_capture", "executable_on_path", "system")) {
            t |> success(has_value(SPAWNERS, name), name)
        }
        t |> equal(length(SPAWNERS), 11)
    }
    t |> run("a call of each function that starts a process is a finding, qualified or not") @(t : T?) {
        for (spawner in SPAWNERS) {
            let found = findings_of(t, [(name = "a.das", text = "options gen2\n\nlet a = {spawner}(x)\nlet b = crt::{spawner}(x)\n")], "a.das")
            t |> equal(found, "a.das:3: names `{spawner}`: nothing under frontend/ starts a process\na.das:4: names `{spawner}`: nothing under frontend/ starts a process")
        }
    }
    t |> run("a spawner is found however it is called or named, and a require however it is spaced") @(t : T?) {
        let spawner = SPAWNERS[length(SPAWNERS) - 1]
        let forms = fixed_array("\"true\" |> {spawner}", "{spawner} (\"true\")", "let f = @@{spawner}", "x |> {spawner}()",
            "let s = \"a \{{spawner}(x)\} b\"", "let c = '\"' + {spawner}(x)", "let c = '\\\"' + {spawner}(x)",
            "let s = \"\{ f(\{1\}) + {spawner}(x) \}\"")
        for (form in forms) {
            let found = findings_of(t, [(name = "a.das", text = "options gen2\n{form}\n")], "a.das")
            t |> equal(found, "a.das:2: names `{spawner}`: nothing under frontend/ starts a process", form)
        }
        for (before in fixed_array("// x", "let s = \"\{x\}\"")) {
            let found = findings_of(t, [(name = "a.das", text = "{before}\nlet a = {spawner}(x)\n")], "a.das")
            t |> equal(found, "a.das:2: names `{spawner}`: nothing under frontend/ starts a process", before)
        }
        for (blanks in fixed_array("  ", "\t", " \t ")) {
            let found = findings_of(t, [(name = "a.das", text = "options gen2\n\nrequire{blanks}{CLANG_MODULE}\n")], "a.das")
            t |> equal(found, "a.das:3: requires `{CLANG_MODULE}`: nothing under frontend/ needs clang", blanks)
        }
    }
}

[test(description = "the frontend gate holds a require line and a file to the forms it can read, and follows a required file")]
def test_frontend_gate_requires(t : T?) {
    t |> run("a require line names the clang binding in any word, or is `require <module> [public]`") @(t : T?) {
        for (line in fixed_array("require ?{CLANG_MODULE} {CLANG_MODULE}", "require strings {CLANG_MODULE}", "require ?{CLANG_MODULE}", "require x/{CLANG_MODULE}", "require {CLANG_MODULE} public")) {
            let found = findings_of(t, [(name = "a.das", text = "options gen2\n{line}\n")], "a.das")
            t |> equal(found, "a.das:2: requires `{CLANG_MODULE}`: nothing under frontend/ needs clang", line)
        }
        for (line in fixed_array("require ?strings", "require strings fio", "require", "require strings private", "let a = 1; require strings", "require \"strings\"")) {
            let found = findings_of(t, [(name = "a.das", text = "options gen2\n{line}\n")], "a.das")
            t |> success(found |> starts_with("a.das:2: has a `require` line that is not ") && find(found, "\n") < 0, "{line}: {found}")
        }
        let plain = findings_of(t, [(name = "a.das", text = "require strings\nrequire daslib/strings_boost public\n  require ../x-y/z.das\nrequire m2\nrequire daslib/x86_64\n")], "a.das")
        t |> equal(plain, "")
    }
    t |> run("a text include is a finding, in a file and in what it requires") @(t : T?) {
        let found = findings_of(t, [(name = "a.das", text = "options gen2\n{INCLUDE} body.inc\nrequire b\n"), (name = "b.das", text = "{INCLUDE} c.inc\n")], "a.das")
        let lines <- split(found, "\n")
        t |> equal(length(lines), 2, found)
        t |> success(found |> starts_with("a.das:2: has an `{INCLUDE}`: the gate follows no text include"), found)
        t |> success(find(found, "\nb.das:1: has an `{INCLUDE}` (required from ") > 0, found)
    }
    t |> run("under the folder every .das file is checked, and a file that is no .das, .h or .md is a finding") @(t : T?) {
        let folder = path_join(test_temp_dir(), "gate_tree")
        mkdir_rec(path_join(folder, "sub"))
        for (name in fixed_array("a.das", "sub/body.inc", "sub/part.das.inc", "sub/x.h", "sub/y.md")) {
            fwrite(path_join(folder, name), "let n = {SPAWNERS[0]}(x)\n")
        }
        gate_reset()
        check_tree(folder)
        let found <- gate_findings()
        gate_reset()
        t |> equal(length(found), 3, join(found, "\n"))
        t |> success(length(found) == 3 && found[0] |> ends_with("a.das:1: names `{SPAWNERS[0]}`: nothing under frontend/ starts a process"), join(found, "\n"))
        t |> success(length(found) == 3 && found[1] |> ends_with("sub/body.inc: is no .das, .h or .md file: the gate reads no other source"), join(found, "\n"))
        t |> success(length(found) == 3 && found[2] |> ends_with("sub/part.das.inc: is no .das, .h or .md file: the gate reads no other source"), join(found, "\n"))
    }
    t |> run("a file required by its path alone is checked") @(t : T?) {
        let found = findings_of(t, [(name = "a.das", text = "require ./c.das\n"), (name = "c.das", text = "let n = {SPAWNERS[0]}(x)\n")], "a.das")
        t |> success(found |> starts_with("./c.das:1: names `{SPAWNERS[0]}` (required from ") && find(found, "\n") < 0, found)
    }
    t |> run("a file required by path or as a sibling module is checked, once, naming the file that reaches it") @(t : T?) {
        let files <- [
            (name = "a.das", text = "require b\nrequire ./c.das\nrequire strings\n"),
            (name = "b.das", text = "require c\nrequire a\nrequire {CLANG_MODULE}\n"),
            (name = "c.das", text = "let n = {SPAWNERS[0]}(x)\n")]
        let found = findings_of(t, files, "a.das")
        let lines <- split(found, "\n")
        t |> equal(length(lines), 2, found)
        t |> success(found |> starts_with("c.das:1: names `{SPAWNERS[0]}` (required from "), found)
        t |> success(find(found, "\nb.das:3: requires `{CLANG_MODULE}` (required from ") > 0, found)
    }
}
