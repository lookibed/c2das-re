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
        // the arm needs the running daslang at exactly the pin: a later checkout is refused earlier
        let head_rc = run_and_capture(["git", "-C", get_das_root(), "rev-parse", "HEAD"], out, 30.0)
        if (head_rc != 0 || find(fread("VERSIONS.md"), "daScript commit: {strip(out)}") < 0) {
            t |> skip("the running daslang is not at VERSIONS.md's pin")
            return
        }
        let rc = build_web("PATH={pinned}", "--ports {ports} --host {get_das_root()} --out {out_dir}", out)
        t |> equal(rc, 1, out)
        t |> success(find(out, "not a wasm host") >= 0, out)
    }
    t |> success(!fexist(out_dir), "no refusal created the --out folder")
    rmdir_rec(work)
}

// runs `cmd` in a shell, its stdout and stderr in `out`
def private sh(cmd : string; var out : string&) : int => run_and_capture(["sh", "-c", "{cmd} 2>&1"], out, 60.0)

// a built site as the script lays it out, its build.json naming `c2das` and `ports`
def private fake_site(dir, c2das, ports : string) {
    mkdir_rec(path_join(dir, "puredoom"))
    fwrite(path_join(dir, "index.html"), "<p>demos</p>\n")
    fwrite(path_join(dir, "puredoom/doom.html"), "<p>doom</p>\n")
    fwrite(path_join(dir, "puredoom/build.json"), "\{\"c2das_re\": \"{c2das}\", \"ports\": \"{ports}\", \"converted_by\": \"deee3209ce\", \"daslang\": \"2decba91d5\", \"emscripten\": \"5.0.7\"\}\n")
}

// a git checkout at `dir` on `branch`, one commit holding a file `stale.txt`
def private fake_checkout(t : T?; dir, branch : string) {
    var out : string
    let rc = sh("git init -q -b '{branch}' '{dir}' && cd '{dir}' && echo old > stale.txt && git add stale.txt && git -c user.name=t -c user.email=t@t commit -q -m old", out)
    t |> equal(rc, 0, out)
}

[test(description = "build_web.sh --pages refuses a wrong checkout, a dirty or data-carrying site, and else replaces the checkout's top with the site, the workflow and the README")]
def test_build_web_pages(t : T?) {
    var dir_error : string
    let work = create_temp_directory("c2das_build_web_pages", dir_error)
    t |> equal(dir_error, "")
    let pages = path_join(work, "pages")
    fake_checkout(t, pages, "gh-pages")
    let site = path_join(work, "site")
    fake_site(site, "1111111111", "2222222222")
    t |> run("--commit without --pages") @(t : T?) {
        var out : string
        let rc = build_web("", "--from '{site}' --commit", out)
        t |> equal(rc, 1, out)
        t |> success(find(out, "there is none") >= 0, out)
    }
    t |> run("--pages that is no checkout, below the top of one, or on another branch") @(t : T?) {
        var out : string
        let plain = path_join(work, "plain")
        mkdir_rec(plain)
        let rc_plain = build_web("", "--from '{site}' --pages '{plain}'", out)
        t |> equal(rc_plain, 1, out)
        t |> success(find(out, "is not a git checkout") >= 0, out)
        let below = path_join(pages, "sub")
        mkdir_rec(below)
        let rc_below = build_web("", "--from '{site}' --pages '{below}'", out)
        t |> equal(rc_below, 1, out)
        t |> success(find(out, "is not the top of its checkout") >= 0, out)
        rmdir_rec(below)
        let main_branch = path_join(work, "main")
        fake_checkout(t, main_branch, "main")
        let rc_main = build_web("", "--from '{site}' --pages '{main_branch}'", out)
        t |> equal(rc_main, 1, out)
        t |> success(find(out, "is not on the gh-pages branch") >= 0, out)
    }
    t |> run("--from a folder that is no built site") @(t : T?) {
        var out : string
        let rc = build_web("", "--from '{work}' --pages '{pages}'", out)
        t |> equal(rc, 1, out)
        t |> success(find(out, "holds no built site") >= 0, out)
    }
    t |> run("--commit of a site built from a tree with changes") @(t : T?) {
        let dirty = path_join(work, "dirty")
        fake_site(dirty, "1111111111-dirty", "2222222222")
        var out : string
        let rc = build_web("", "--from '{dirty}' --pages '{pages}' --commit", out)
        t |> equal(rc, 1, out)
        t |> success(find(out, "names a tree with changes") >= 0, out)
        t |> success(fexist(path_join(pages, "stale.txt")), "the refusal wrote nothing")
    }
    t |> run("a site that holds a WAD") @(t : T?) {
        let data = path_join(work, "data")
        fake_site(data, "1111111111", "2222222222")
        fwrite(path_join(data, "puredoom/freedoom2.wad"), "IWAD")
        var out : string
        let rc = build_web("", "--from '{data}' --pages '{pages}' --commit", out)
        t |> equal(rc, 1, out)
        t |> success(find(out, "holds game data") >= 0, out)
        t |> success(fexist(path_join(pages, "stale.txt")), "the refusal wrote nothing")
    }
    t |> run("a clean site: the checkout's top replaced and committed, a second run commits nothing") @(t : T?) {
        var out : string
        let rc = build_web("", "--from '{site}' --pages '{pages}' --commit", out)
        t |> equal(rc, 0, out)
        t |> success(!fexist(path_join(pages, "stale.txt")), "the old top is gone")
        t |> success(fexist(path_join(pages, "puredoom/doom.html")), "the site is copied")
        t |> success(fexist(path_join(pages, ".github/workflows/pages.yml")), "the deploy workflow is there")
        let readme = fread(path_join(pages, "README.md"))
        t |> success(find(readme, "c2das-ports 2222222222") >= 0 && find(readme, "c2das-re 1111111111") >= 0, readme)
        let log_rc = sh("git -C '{pages}' log -1 --format=%s", out)
        t |> equal(log_rc, 0, out)
        t |> equal(strip(out), "site: c2das-re 1111111111, c2das-ports 2222222222, daScript 2decba91d5")
        let again = build_web("", "--from '{site}' --pages '{pages}' --commit", out)
        t |> equal(again, 0, out)
        t |> success(find(out, "already holds this site") >= 0, out)
    }
    rmdir_rec(work)
}
