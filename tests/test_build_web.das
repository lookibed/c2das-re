options gen2
require dastest/testing_boost public
require strings
require daslib/fio

//! `scripts/build_web.sh`'s refusals (web/ARCHITECTURE.md section 2): each fires before the script's
//! first write, so the `--out` folder stays absent. None needs emscripten or the wasm host: emcc is a
//! script on a PATH of its own, and the hosts are a git repository at another commit and the pin
//! itself, whose daslang links libstdc++.

// runs build_web.sh with `args` under the environment assignments `env`, its stdout and stderr in `out`
def private build_web(env, args : string; var out : string&) : int => run_and_capture(["sh", "-c", "{env} bash scripts/build_web.sh {args} 2>&1"], out, 120.0)

// a folder shaped like a ports checkout's puredoom-readable as far as the script checks it
def private fake_ports(dir : string) {
    mkdir_rec(path_join(dir, "puredoom-readable/processed/doom"))
    fwrite(path_join(dir, "puredoom-readable/processed/doom/doom_main.das"), "")
}

// a PATH holding the tools the script runs before its emcc check, and an `emcc` printing `version_line`
def private tool_path(t : T?; dir, version_line : string) : string {
    let bin = path_join(dir, "bin")
    mkdir_rec(bin)
    var out : string
    for (tool in ["bash", "sh", "sed", "git", "ldd", "grep", "head", "dirname"]) {
        let rc = run_and_capture(["sh", "-c", "ln -sf \"$(command -v {tool})\" {bin}/{tool}"], out, 30.0)
        t |> equal(rc, 0, out)
    }
    if (!empty(version_line)) {
        fwrite(path_join(bin, "emcc"), "#!/bin/sh\necho '{version_line}'\n")
        let rc = run_and_capture(["chmod", "+x", path_join(bin, "emcc")], out, 30.0)
        t |> equal(rc, 0, out)
    }
    return bin
}

[test(description = "build_web.sh refuses a missing or empty ports checkout, a host off the pin, a host without libc++ and another emscripten, before writing")]
def test_build_web_refusals(t : T?) {
    var dir_error : string
    let work = create_temp_directory("c2das_build_web", dir_error)
    t |> equal(dir_error, "")
    let out_dir = path_join(work, "out")
    let ports = path_join(work, "ports")
    fake_ports(ports)
    t |> run("no --ports") @(t : T?) {
        var out : string
        let rc = build_web("", "--out {out_dir}", out)
        t |> equal(rc, 1, out)
        t |> success(find(out, "--ports <c2das-ports checkout> is required") >= 0, out)
    }
    t |> run("a ports checkout without the converted PureDOOM") @(t : T?) {
        var out : string
        let rc = build_web("", "--ports {work} --out {out_dir}", out)
        t |> equal(rc, 1, out)
        t |> success(find(out, "holds no converted PureDOOM") >= 0, out)
    }
    t |> run("no emcc, and an emscripten other than 5.0.7") @(t : T?) {
        var out : string
        let none = tool_path(t, path_join(work, "none"), "")
        let rc_none = build_web("PATH={none}", "--ports {ports} --out {out_dir}", out)
        t |> equal(rc_none, 1, out)
        t |> success(find(out, "emcc is not on PATH") >= 0, out)
        let other = tool_path(t, path_join(work, "other"), "emcc (Emscripten gcc/clang-like replacement + linker emulating GNU ld) 9.9.9 (deadbeef)")
        let rc = build_web("PATH={other}", "--ports {ports} --out {out_dir}", out)
        t |> equal(rc, 1, out)
        t |> success(find(out, "is not emscripten 5.0.7") >= 0, out)
    }
    let pinned = tool_path(t, path_join(work, "pinned"), "emcc (Emscripten gcc/clang-like replacement + linker emulating GNU ld) 5.0.7 (263db4cffa6f9fc2ec514a70abac81362ea41849)")
    t |> run("a host at another commit than VERSIONS.md's pin") @(t : T?) {
        let host = path_join(work, "host")
        mkdir_rec(host)
        var out : string
        let made = run_and_capture(["sh", "-c", "cd {host} && git init -q && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m x 2>&1"], out, 60.0)
        t |> equal(made, 0, out)
        let rc = build_web("PATH={pinned}", "--ports {ports} --host {host} --out {out_dir}", out)
        t |> equal(rc, 1, out)
        t |> success(find(out, "VERSIONS.md pins") >= 0, out)
    }
    t |> run("the pin itself, whose daslang links libstdc++") @(t : T?) {
        var out : string
        let rc = build_web("PATH={pinned}", "--ports {ports} --host {get_das_root()} --out {out_dir}", out)
        t |> equal(rc, 1, out)
        t |> success(find(out, "not a wasm host") >= 0, out)
    }
    t |> success(!fexist(out_dir), "no refusal created the --out folder")
    rmdir_rec(work)
}
