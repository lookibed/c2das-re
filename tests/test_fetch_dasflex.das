options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost

//! dasFlex at its pin: the `VERSIONS.md` line and the fetched checkout's commit, the branches of
//! `scripts/fetch_dasflex.sh` in a stand-in root whose origin is a local repository, and the module
//! folder `das` of `scripts/env.sh` passes only once the fetch exists.

// the commit the `dasFlex:` line of `versions` pins, "" without the line
def private dasflex_pin(versions : string) : string {
    for (line in split(versions, "\n")) {
        if (starts_with(line, "dasFlex: ")) {
            return split(slice(line, 9), " ")[0]
        }
    }
    return ""
}

// `script` run by `sh -c` with its stdout and stderr in `out`
def private shell(script : string; var out : string&) : int => run_and_capture(["sh", "-c", "{script} 2>&1"], out, 120.0)

// `git` with a fixed author, for the stand-in repositories
let private GIT = "git -c user.name=t -c user.email=t@t"

[test(description = "VERSIONS.md pins dasFlex to a full commit, and the fetched checkout is at it")]
def test_pin(t : T?) {
    let pin = dasflex_pin(fread("VERSIONS.md"))
    t |> equal(length(pin), 40, pin)
    if (!fexist("fetch/dasFlex/.git")) {
        t |> skip("no fetch/dasFlex: scripts/fetch_dasflex.sh")
        return
    }
    var head : string
    let rc = run_and_capture(["git", "-C", "fetch/dasFlex", "rev-parse", "HEAD"], head, 30.0)
    t |> equal(rc, 0, head)
    t |> equal(strip(head), pin)
}

// a stand-in root at `dir` holding the fetch script and its helper, an origin repository `dir/up`
// with two commits and `dir/fetch/dasFlex` cloned from it; the two commits, the second checked out
def private stand_in(t : T?; dir : string) : array<string> {
    mkdir_rec(path_join(dir, "scripts"))
    mkdir_rec(path_join(dir, "suites"))
    mkdir_rec(path_join(dir, "up"))
    var out : string
    var rc = run_and_capture(["cp", "scripts/fetch_dasflex.sh", path_join(dir, "scripts")], out, 30.0)
    t |> equal(rc, 0, out)
    rc = run_and_capture(["cp", "suites/fetch_common.sh", path_join(dir, "suites")], out, 30.0)
    t |> equal(rc, 0, out)
    let up = path_join(dir, "up")
    fwrite(path_join(up, "f.txt"), "1\n")
    rc = shell("cd '{up}' && git init -q && {GIT} add f.txt && {GIT} commit -q -m one && git rev-parse HEAD", out)
    t |> equal(rc, 0, out)
    let first = strip(out)
    fwrite(path_join(up, "f.txt"), "2\n")
    rc = shell("cd '{up}' && {GIT} commit -q -am two && git rev-parse HEAD", out)
    t |> equal(rc, 0, out)
    let second = strip(out)
    rc = shell("git clone -q '{up}' '{dir}/fetch/dasFlex'", out)
    t |> equal(rc, 0, out)
    return <- [first, second]
}

// fetch_dasflex.sh in the stand-in root under a VERSIONS.md naming `pin` ("" for no line): its exit
// code, its output in `out` and the checkout's commit after it in `head`
def private fetch(dir, pin : string; var out, head : string&) : int {
    fwrite(path_join(dir, "VERSIONS.md"), empty(pin) ? "daScript commit: 0 (a stand-in)\n" : "dasFlex: {pin} (a stand-in)\n")
    let rc = shell("bash '{dir}/scripts/fetch_dasflex.sh'", out)
    var at : string
    shell("git -C '{dir}/fetch/dasFlex' rev-parse HEAD", at)
    head = strip(at)
    return rc
}

[test(description = "fetch_dasflex.sh leaves a clean checkout at the pin alone, moves a clean one to the pin, fetching a commit it lacks, and refuses a checkout with local changes, a commit nowhere and a VERSIONS.md with no pin", timeout = 300)]
def test_fetch_script(t : T?) {
    let dir = path_join(test_temp_dir(), "fetch_dasflex")
    let commits <- stand_in(t, dir)
    let first = commits[0]
    let second = commits[1]
    t |> run("no pin: refused") @(t : T?) {
        var out, head : string
        let rc = fetch(dir, "", out, head)
        t |> equal(rc, 1, out)
        t |> success(find(out, "names no dasFlex pin") >= 0, out)
    }
    t |> run("clean at the pin: left alone, silently") @(t : T?) {
        var out, head : string
        let rc = fetch(dir, second, out, head)
        t |> equal(rc, 0, out)
        t |> equal(out, "")
        t |> equal(head, second)
    }
    t |> run("clean at another commit: moved to the pin") @(t : T?) {
        var out, head : string
        let rc = fetch(dir, first, out, head)
        t |> equal(rc, 0, out)
        t |> equal(strip(out), "fetch: dasFlex at {first}")
        t |> equal(head, first)
    }
    t |> run("a pin the checkout lacks: fetched from its origin") @(t : T?) {
        var out, head : string
        let up = path_join(dir, "up")
        fwrite(path_join(up, "f.txt"), "3\n")
        var rc = shell("cd '{up}' && {GIT} commit -q -am three && git rev-parse HEAD", out)
        t |> equal(rc, 0, out)
        let third = strip(out)
        rc = fetch(dir, third, out, head)
        t |> equal(rc, 0, out)
        t |> equal(head, third)
    }
    t |> run("local changes: refused, the checkout untouched") @(t : T?) {
        var out, head, before : string
        shell("git -C '{dir}/fetch/dasFlex' rev-parse HEAD", before)
        fwrite(path_join(dir, "fetch/dasFlex/f.txt"), "edited\n")
        let rc = fetch(dir, first, out, head)
        t |> equal(rc, 1, out)
        t |> success(find(out, "has local changes") >= 0, out)
        t |> equal(head, strip(before))
        t |> equal(fread(path_join(dir, "fetch/dasFlex/f.txt")), "edited\n")
    }
    t |> run("a pin no repository holds: refused") @(t : T?) {
        var out, head : string
        var rc = shell("git -C '{dir}/fetch/dasFlex' checkout -q -- f.txt", out)
        t |> equal(rc, 0, out)
        rc = fetch(dir, "0000000000000000000000000000000000000000", out, head)
        t |> success(rc != 0, out)
    }
}

[test(description = "`das` of env.sh loads fetch/dasFlex as a module folder only once it exists", timeout = 120)]
def test_das_module_folders(t : T?) {
    let dir = path_join(test_temp_dir(), "env_das")
    mkdir_rec(path_join(dir, "scripts"))
    var out : string
    var rc = run_and_capture(["cp", "scripts/env.sh", path_join(dir, "scripts")], out, 30.0)
    t |> equal(rc, 0, out)
    let call = "DASLANG=echo bash -c \". '{dir}/scripts/env.sh' && das x.das\""
    rc = shell(call, out)
    t |> equal(rc, 0, out)
    t |> equal(strip(out), "-load_module {dir}/dasCRuntime -load_module {dir}/c_runtime x.das")
    mkdir_rec(path_join(dir, "fetch/dasFlex"))
    rc = shell(call, out)
    t |> equal(rc, 0, out)
    t |> equal(strip(out), "-load_module {dir}/dasCRuntime -load_module {dir}/c_runtime -load_module {dir}/fetch/dasFlex x.das")
}
