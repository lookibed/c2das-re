options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require ../harness.das

//! `fetch_doom2.sh` as a child process over a scratch pin file and a scratch wad folder (`VERSIONS_MD`
//! and `DOOM2_WAD_DIR`): no source, a wrong size, a line without a sha256 yet, a wrong hash, the
//! pinned hash, and a second run that finds the wad at the pin without a source.

let SCRIPT = "doom/fetch_doom2.sh"
let FAKE_WAD = "IWAD fake doom2!"   // 16 bytes: the scratch line pins 16

// a fresh scratch folder, "" when none can be made
def private scratch(name : string) : string {
    var error : string
    let dir = create_temp_directory(name, error)
    return empty(error) ? dir : ""
}

// the script under the scratch pin file and wad folder, with `source` as its argument when not ""
def private fetch(pin_file, wad_dir, source : string; var out : string&) : int {
    var argv <- ["env", "VERSIONS_MD={pin_file}", "DOOM2_WAD_DIR={wad_dir}", "DOOM2_WAD_SOURCE=", "bash", get_full_file_name(SCRIPT)]
    if (!empty(source)) {
        argv |> push(source)
    }
    return run_and_capture(argv, out, 60.0)
}

def private pin_line(size : int; sha : string) : string {
    let hash = empty(sha) ? "`doom2.wad` (sha256 not pinned yet)" : "`doom2.wad` (sha256 {sha})"
    return "lua: 5.4.8\ndoom2: 1.9 (a test release) ({size} bytes, test); {hash}\n"
}

[test]
def test_fetch_doom2(t : T?) {
    let root = scratch("fetch_doom2")
    t |> equal(empty(root), false, "no scratch folder")
    if (empty(root)) {
        return
    }
    let pin = path_join(root, "VERSIONS.md")
    let wads = path_join(root, "wads")
    let source = path_join(root, "owner_doom2.wad")
    fwrite(source, FAKE_WAD)
    let sha = file_sha256(source)
    t |> run("no doom2 line stops it") @(t : T?) {
        var out : string
        fwrite(pin, "lua: 5.4.8\n")
        t |> equal(fetch(pin, wads, source, out), 1, out)
        t |> success(out |> contains("no `doom2:` line"), out)
    }
    t |> run("no source: exit 2, the message names the argument and the variable, no mirror") @(t : T?) {
        var out : string
        fwrite(pin, pin_line(16, ""))
        t |> equal(fetch(pin, wads, "", out), 2, out)
        t |> success(out |> contains("DOOM2_WAD_SOURCE"), out)
        t |> success(out |> contains("no mirror"), out)
    }
    t |> run("a missing source file") @(t : T?) {
        var out : string
        t |> equal(fetch(pin, wads, path_join(root, "none.wad"), out), 2, out)
        t |> success(out |> contains("no file at"), out)
    }
    t |> run("the wrong size is refused and no copy stays") @(t : T?) {
        var out : string
        fwrite(pin, pin_line(17, ""))
        t |> equal(fetch(pin, wads, source, out), 1, out)
        t |> success(out |> contains("pins 17"), out)
        t |> success(out |> contains("not the pinned release"), out)
        t |> equal(fexist(path_join(wads, "doom2.wad.part")), false)
        t |> equal(fexist(path_join(wads, "doom2.wad")), false)
    }
    t |> run("a line without a sha256 prints the file's hash to pin and keeps no copy") @(t : T?) {
        var out : string
        fwrite(pin, pin_line(16, ""))
        t |> equal(fetch(pin, wads, source, out), 1, out)
        t |> success(out |> contains("pins no sha256 yet"), out)
        t |> success(out |> contains(sha), out)
        t |> equal(fexist(path_join(wads, "doom2.wad.part")), false)
        t |> equal(fexist(path_join(wads, "doom2.wad")), false)
    }
    t |> run("the wrong hash is refused") @(t : T?) {
        var out : string
        fwrite(pin, pin_line(16, "0000000000000000000000000000000000000000000000000000000000000000"))
        t |> equal(fetch(pin, wads, source, out), 1, out)
        t |> success(out |> contains("has sha256 {sha}"), out)
        t |> equal(fexist(path_join(wads, "doom2.wad")), false)
    }
    t |> run("the pinned hash places the wad; a second run without a source finds it at the pin") @(t : T?) {
        var out : string
        fwrite(pin, pin_line(16, sha))
        t |> equal(fetch(pin, wads, source, out), 0, out)
        t |> equal(file_sha256(path_join(wads, "doom2.wad")), sha)
        t |> equal(fexist(path_join(wads, "doom2.wad.part")), false)
        t |> equal(fetch(pin, wads, "", out), 0, out)
        t |> success(out |> contains("is at the pin"), out)
    }
    t |> run("the repository's own doom2 line names a size and no mirror") @(t : T?) {
        let line = [for (l in split(fread("VERSIONS.md"), "\n")); l; where l |> starts_with("doom2: ")]
        t |> equal(length(line), 1)
        if (length(line) == 1) {
            t |> success(line[0] |> contains("(14604584 bytes"), line[0])
            t |> success(line[0] |> contains("never fetched from a mirror"), line[0])
        }
    }
}
