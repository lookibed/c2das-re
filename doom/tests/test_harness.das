options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require ../harness.das
require ../sources.das
require ../../converter/sidecar.das

//! The doom harness without the release: the checksum on known values, the pins of
//! `VERSIONS.md`, `fetch_problems` over a stand-in checkout built from the patch's own pre-image
//! (to which the patch applies) and a stand-in wad, the units check over a stand-in folder, the
//! reference log's format and refusals, and the sidecar through the converter's reader.

let PATCH = "doom/patches/0001-per-tic-checksum.patch"

// a fresh scratch folder, "" when none can be made
def private scratch(name : string) : string {
    var error : string
    let dir = create_temp_directory(name, error)
    return empty(error) ? dir : ""
}

// the pre-image of `patch` under `root`: per file it names, the context and removed lines of its
// hunks in order, so the patch applies to it
def private write_pre_image(patch, root : string) {
    var files : table<string; string>
    var current = ""
    var in_hunk = false
    for (line in split(fread(patch), "\n")) {
        if (line |> starts_with("diff --git ")) {
            in_hunk = false
        } elif (line |> starts_with("--- a/")) {
            current = slice(line, 6)
        } elif (line |> starts_with("@@")) {
            in_hunk = !empty(current)
        } elif (in_hunk && (line |> starts_with(" ") || line |> starts_with("-"))) {
            files.insert(current, files?[current] ?? "" + slice(line, 1) + "\n")
        }
    }
    for (path, text in keys(files), values(files)) {
        let full = path_join(root, path)
        mkdir_rec(dir_name(full))
        fwrite(full, text)
    }
}

// `argv` run in `dir`, its exit code
def private run_in(dir : string; argv : array<string>) : int {
    var cmd <- ["bash", "-c", "cd \"$0\" && exec \"$@\"", dir]
    cmd |> push_from(argv)
    var out : string
    return run_and_capture(cmd, out, 120.0)
}

[test]
def test_checksum(t : T?) {
    t |> run("the FNV-1a over the six values' little-endian bytes") @(t : T?) {
        t |> equal(tic_checksum([0u, 0u, 0u, 0u, 0u, 0u]), 0xe2ba14a5u)
        t |> equal(tic_checksum([1u, 2u, 3u, 4u, 5u, 6u]), 0x8fd0d222u)
        t |> equal(tic_checksum([0x00100000u, 0xfff00000u, 0u, 0x40000000u, 100u, 255u]), 0x46876903u)
    }
    t |> run("the frame's FNV-1a over the screen's bytes") @(t : T?) {
        t |> equal(frame_checksum([1u8, 2u8, 3u8]), 0x56cf37abu)
        t |> equal(frame_checksum([255u8, 255u8, 255u8, 255u8]), 0xe3160fb1u)
    }
    t |> run("tic 0 of every reference log is the zeroed 320x200 screen") @(t : T?) {
        var screen : array<uint8>
        screen |> resize(320 * 200)
        let fb = "fb={fmt(":08x", frame_checksum(screen))}"
        for (demo in range(1, 4)) {
            let first = tic_lines(fread("doom/ref/freedoom2_demo{demo}.log"))[0]
            t |> success(first |> ends_with(fb), "{first} against {fb}")
        }
    }
}

[test]
def test_pins(t : T?) {
    t |> run("the puredoom and freedoom lines of VERSIONS.md") @(t : T?) {
        let versions = fread("VERSIONS.md")
        t |> equal(length(puredoom_pin(versions)), 40)
        t |> equal(length(freedoom2_sha256(versions)), 64)
        t |> equal(puredoom_pin("lua: 5.4.8\n"), "")
        t |> equal(freedoom2_sha256("freedoom: 0.13.0\n"), "")
    }
}

[test]
def test_fetch_problems(t : T?) {
    let root = scratch("doom_fetch")
    t |> success(!empty(root), "a scratch folder")
    let tree = path_join(root, "PureDOOM")
    write_pre_image(PATCH, tree)
    t |> equal(run_in(tree, ["git", "init", "-q"]), 0)
    t |> equal(run_in(tree, ["git", "add", "-A"]), 0)
    t |> equal(run_in(tree, ["git", "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "pre-image"]), 0)
    var out : string
    run_and_capture(["git", "-C", tree, "rev-parse", "HEAD"], out, 60.0)
    let pin = strip(out)
    let wad = path_join(root, "freedoom2.wad")
    fwrite(wad, "IWAD stand-in\n")
    let wad_sha = file_sha256(wad)
    t |> run("an unpatched checkout is refused") @(t : T?) {
        let problems <- fetch_problems(tree, pin, [PATCH], wad, wad_sha)
        t |> equal(length(problems), 1)
        t |> success(length(problems) == 1 && find(problems[0], "is not applied") >= 0)
    }
    t |> run("the patch applies cleanly to its hunks' context") @(t : T?) {
        t |> equal(run_in(tree, ["git", "apply", get_full_file_name(PATCH)]), 0)
        t |> equal(length(fetch_problems(tree, pin, [PATCH], wad, wad_sha)), 0)
    }
    t |> run("a checkout off the pin is refused") @(t : T?) {
        let problems <- fetch_problems(tree, "0000000000000000000000000000000000000000", [PATCH], wad, wad_sha)
        t |> success(length(problems) == 1 && find(problems[0], " is at {pin}") >= 0)
    }
    t |> run("a wad of another hash is refused") @(t : T?) {
        let problems <- fetch_problems(tree, pin, [PATCH], wad, repeat("0", 64))
        t |> success(length(problems) == 1 && find(problems[0], "has sha256 {wad_sha}") >= 0)
    }
    t |> run("a missing wad is refused") @(t : T?) {
        let problems <- fetch_problems(tree, pin, [PATCH], path_join(root, "none.wad"), wad_sha)
        t |> success(length(problems) == 1 && find(problems[0], "no ") == 0)
    }
    t |> run("a folder that is no checkout is refused") @(t : T?) {
        let problems <- fetch_problems(root, pin, [PATCH], wad, wad_sha)
        t |> success(length(problems) == 1 && find(problems[0], "is no checkout") >= 0)
    }
}

[test]
def test_units(t : T?) {
    t |> run("every listed unit is a .c file of the folder") @(t : T?) {
        let dir = scratch("doom_units")
        for (unit in UNITS) {
            fwrite(path_join(dir, "{unit}.c"), "/* {unit} */\n")
        }
        t |> equal(length(missing_units(dir, UNITS)), 0)
        remove(path_join(dir, "g_game.c"))
        let missing <- missing_units(dir, UNITS)
        t |> success(length(missing) == 1 && missing[0] == "g_game")
    }
    t |> run("the units are PureDOOM's 62 files with the host last") @(t : T?) {
        t |> equal(length(UNITS), 62)
        let paths <- program_sources()
        t |> equal(length(paths), 63)
        t |> success(paths[62] |> ends_with("doom/host/doom_main.c"))
    }
}

[test]
def test_demo_log(t : T?) {
    t |> run("the tic lines under the header") @(t : T?) {
        var error : string
        let log = demo_log("Z_Init\ntic=0 cs=0896c202\ntic=1 cs=0896c203\nError: timed 2 gametics in 3 realtics\n", "pin", error)
        t |> equal(error, "")
        t |> equal(log, "# pin\ntic=0 cs=0896c202\ntic=1 cs=0896c203\n")
    }
    t |> run("a run that did not end in the timedemo line is refused") @(t : T?) {
        var error : string
        t |> equal(demo_log("tic=0 cs=0896c202\nSegmentation fault\n", "pin", error), "")
        t |> success(find(error, "did not end") >= 0)
    }
    t |> run("a tic count other than the timed gametics is refused") @(t : T?) {
        var error : string
        t |> equal(demo_log("tic=0 cs=0896c202\nError: timed 2 gametics in 3 realtics\n", "pin", error), "")
        t |> success(find(error, "timed 2 gametics and printed 1") >= 0)
    }
    t |> run("a tic line with the frame's checksum") @(t : T?) {
        var error : string
        let log = demo_log("tic=0 cs=0896c202 fb=38c165c5\nError: timed 1 gametics in 1 realtics\n", "pin", error)
        t |> equal(error, "")
        t |> equal(log, "# pin\ntic=0 cs=0896c202 fb=38c165c5\n")
    }
}

// two reference tic lines with the frame's checksum
def private fb_lines : array<string> => <- ["tic=0 cs=00000000 fb=00000000", "tic=1 cs=00000001 fb=00000001"]

[test]
def test_tic_sync(t : T?) {
    t |> run("a desync names the fields that differ") @(t : T?) {
        let expected <- fb_lines()
        t |> equal(differing_fields(expected[1], "tic=1 cs=00000001 fb=0000000f"), "fb")
        t |> equal(differing_fields(expected[1], "tic=1 cs=0000000f fb=00000001"), "cs")
        t |> equal(differing_fields(expected[1], "tic=2 cs=0000000f fb=0000000f"), "tic cs fb")
        t |> equal(differing_fields(expected[1], "tic=1 cs=00000001"), "fb")
        t |> equal(differing_fields("tic=1 cs=00000001", expected[1]), "fb")
    }
    t |> run("the summary names them") @(t : T?) {
        let sync = tic_sync(fb_lines(), ["tic=0 cs=00000000 fb=00000000", "tic=1 cs=00000001 fb=0000000f"], 0)
        t |> equal(sync.fields, "fb")
        t |> equal(sync_summary(sync), "desync after 1 tics in sync on fb: expected `tic=1 cs=00000001 fb=00000001`, got `tic=1 cs=00000001 fb=0000000f`")
    }
    t |> run("past the reference's end no field is named") @(t : T?) {
        var got <- fb_lines()
        got |> push("tic=2 cs=00000002 fb=00000002")
        let sync = tic_sync(fb_lines(), got, 0)
        t |> equal(sync.fields, "")
        t |> success(sync_summary(sync) |> starts_with("desync after 2 tics in sync: expected the demo's end"))
    }
}

[test]
def test_tic_lines(t : T?) {
    let text = "# header\ntic=0 cs=00000000\nZ_Init\ntic=1 cs=00000001\n"
    t |> equal(join(tic_lines(text), "|"), "tic=0 cs=00000000|tic=1 cs=00000001")
    t |> equal(join(non_tic_lines(text), "|"), "# header|Z_Init|")
}

[test]
def test_trace_lines(t : T?) {
    let text = "tic=0 cs=00000000\ntrace=0 x=00e00000 hp=100\nZ_Init\ntrace=1 x=00e00071 hp=100\n"
    t |> equal(join(trace_lines(text), "|"), "trace=0 x=00e00000 hp=100|trace=1 x=00e00071 hp=100")
    t |> equal(join(tic_lines(text), "|"), "tic=0 cs=00000000")
    let sync = tic_sync(trace_lines(text), ["trace=0 x=00e00000 hp=100", "trace=1 x=00deb79c hp=100"], 0)
    t |> equal(sync.in_sync, 1)
    t |> equal(sync.fields, "x")
}

[test]
def test_sidecar(t : T?) {
    t |> run("doom.c2das reads with the converter's reader") @(t : T?) {
        var error : string
        let side = read_sidecar(SIDECAR, error)
        t |> equal(error, "")
        t |> success(has_value(side.defines, "DOOM_TIC_CHECKSUM"))
        t |> equal(length(side.marshal), 11)
        t |> equal(length(side.over_indexed), 3)
        t |> equal(length(side.padded), 2)
    }
}
