options gen2

module harness public

require strings
require daslib/fio
require daslib/strings_boost
require daslib/strings_convert
require math

//! The checks and formats `run.das` applies, apart from the processes it starts
//! (`ARCHITECTURE.md` sections 1, 3 and 5): the pins the `puredoom:` and `freedoom:` lines of
//! `VERSIONS.md` name, the fetch check of a tree, a wad and the patches, the tic and frame checksums and
//! the reference log of a demo run.

//! The FNV-1a offset basis and prime of the tic and frame checksums.
let FNV_BASIS = 2166136261u
let FNV_PRIME = 16777619u

//! The per-tic checksum the patch prints: the 32-bit FNV-1a over the little-endian bytes of each
//! value in order (`players[0].mo->x`, `y`, `z`, `angle`, `players[0].health`, `prndindex`).
def tic_checksum(values : array<uint>) : uint {
    var cs = FNV_BASIS
    for (value in values) {
        for (byte_index in range(4)) {
            cs = (cs ^ ((value >> uint(8 * byte_index)) & 0xffu)) * FNV_PRIME
        }
    }
    return cs
}

//! The per-frame checksum the patch prints as `fb=`: the same FNV-1a over the bytes of the screen.
def frame_checksum(screen : array<uint8>) : uint {
    var cs = FNV_BASIS
    for (b in screen) {
        cs = (cs ^ uint(b)) * FNV_PRIME
    }
    return cs
}

//! The text after `<key>: ` on the first line of `versions` that starts with it, "" without one.
def versions_line(versions, key : string) : string {
    for (line in split(versions, "\n")) {
        if (line |> starts_with("{key}: ")) {
            return slice(line, length(key) + 2)
        }
    }
    return ""
}

//! The PureDOOM commit the `puredoom:` line pins, "" without one.
def puredoom_pin(versions : string) : string {
    let line = versions_line(versions, "puredoom")
    let space = find(line, " ")
    return space < 0 ? line : slice(line, 0, space)
}

//! The sha256 of `freedoom2.wad` the `freedoom:` line pins, "" without one.
def freedoom2_sha256(versions : string) : string {
    let line = versions_line(versions, "freedoom")
    let mark = "`freedoom2.wad` (sha256 "
    let at = find(line, mark)
    return at < 0 ? "" : slice(line, at + length(mark), at + length(mark) + 64)
}

//! The sha256 of `path` as `sha256sum` prints it, "" when it cannot be read.
def file_sha256(path : string) : string {
    if (!stat(path).is_reg) {
        return ""
    }
    var out : string
    let rc = run_and_capture(["sha256sum", path], out, 120.0)
    return rc == 0 && length(out) >= 64 ? slice(out, 0, 64) : ""
}

//! What keeps the fetch from matching the pins: the checkout `tree` not at commit `pin`, a patch
//! of `patches` not applied to it, `wad` missing or not of sha256 `wad_sha`; empty when it matches.
def fetch_problems(tree, pin : string; patches : array<string>; wad, wad_sha : string) : array<string> {
    var problems : array<string>
    var out : string
    if (!stat(path_join(tree, ".git")).is_dir) {
        problems |> push("{tree} is no checkout; run doom/fetch.sh")
    } else {
        run_and_capture(["git", "-C", tree, "rev-parse", "HEAD"], out, 60.0)
        let head = strip(out)
        if (head != pin) {
            problems |> push("{tree} is at {head}, VERSIONS.md pins {pin}")
        }
        for (patch in patches) {
            if (run_and_capture(["git", "-C", tree, "apply", "--reverse", "--check", get_full_file_name(patch)], out, 60.0) != 0) {
                problems |> push("{patch} is not applied to {tree}")
            }
        }
    }
    let have = file_sha256(wad)
    if (empty(have)) {
        problems |> push("no {wad}; run doom/fetch.sh")
    } elif (have != wad_sha) {
        problems |> push("{wad} has sha256 {have}, VERSIONS.md pins {wad_sha}")
    }
    return <- problems
}

//! The units of `units` with no `<unit>.c` in `dir`.
def missing_units(dir : string; units : array<string>) : array<string> => <- [for (unit in units); unit; where !stat(path_join(dir, "{unit}.c")).is_reg]

//! The `tic=` lines of `text` in order: a run's output or a reference log, its header left out.
def tic_lines(text : string) : array<string> => <- [for (line in split(text, "\n")); line; where is_tic_line(line)]

//! The lines of `text` other than its `tic=` lines, in order.
def non_tic_lines(text : string) : array<string> => <- [for (line in split(text, "\n")); line; where !is_tic_line(line)]

// whether `line` is a tic line the patch prints
def private is_tic_line(line : string) : bool => line |> starts_with("tic=")

//! The N of the `Error: timed N gametics` line a `-timedemo` run ends in, -1 without one.
def timed_gametics(output : string) : int {
    for (line in split(output, "\n")) {
        if (line |> starts_with("Error: timed ")) {
            return to_int(split(slice(line, 13), " ")[0])
        }
    }
    return -1
}

//! The playback's own time a run's host prints at its end (`ARCHITECTURE.md` section 4): the tics
//! Doom ran and the CPU seconds of the update loop, both -1 without the line.
struct HostTiming {
    tics : int = -1
    seconds : double = -1.0lf
}

//! The first `host: timed <N> gametics in <S> s` line of `output`; -1 for both without one, or
//! when either number does not parse whole or is negative.
def host_timing(output : string) : HostTiming {
    let prefix = "host: timed "
    for (line in split(output, "\n")) {
        if (!(line |> starts_with(prefix))) {
            continue
        }
        var inscope words <- split(slice(line, length(prefix)), " ")
        if (length(words) != 5 || words[1] != "gametics" || words[2] != "in" || words[4] != "s") {
            return HostTiming()
        }
        let tics = try_to_int(words[0]) ?? -1
        let seconds = try_to_double(words[3]) ?? -1.0lf
        return tics < 0 || seconds < 0.0lf ? HostTiming() : HostTiming(tics = tics, seconds = seconds)
    }
    return HostTiming()
}

//! The reference log of a `-timedemo` run's `output`: `header` as a `# ` line, then every
//! `tic=` line in order; "" with `error` set when the run did not end in the timedemo's
//! `timed N gametics` line or printed other than N tic lines.
def demo_log(output, header : string; var error : string&) : string {
    let tics <- tic_lines(output)
    let gametics = timed_gametics(output)
    if (gametics < 0) {
        error = "the run did not end in `timed N gametics` after {length(tics)} tic lines"
        return ""
    }
    if (gametics != length(tics)) {
        error = "the run timed {gametics} gametics and printed {length(tics)} tic lines"
        return ""
    }
    return "# {header}\n" + join(tics, "\n") + "\n"
}

//! How a run's tic lines match a reference's: `compared` the lines held against it, `in_sync`
//! the leading ones that match, `desync` the first mismatch, "" while none, and `fields` the
//! fields of that mismatch that differ (`differing_fields`), "" past the reference's end.
struct TicSync {
    compared : int
    in_sync : int
    desync : string
    fields : string
}

//! The keys (`tic`, `cs`, `fb`) of the fields of tic line `got` that differ from `expected`'s,
//! field by field in order and space-separated; a field one line lacks differs.
def differing_fields(expected, got : string) : string {
    let want <- split(expected, " ")
    let have <- split(got, " ")
    var keys : array<string>
    for (i in range(max(length(want), length(have)))) {
        let field = i < length(want) ? want[i] : have[i]
        if (i >= length(want) || i >= length(have) || want[i] != have[i]) {
            let eq = find(field, "=")
            keys |> push(eq < 0 ? field : slice(field, 0, eq))
        }
    }
    return join(keys, " ")
}

//! `got` against `expected` over the first `tics` lines, every line of `expected` when `tics` is 0
//! or past it; held to the whole reference, a run that goes on past its last line desyncs there.
def tic_sync(expected, got : array<string>; tics : int) : TicSync {
    var sync = TicSync(compared = tics > 0 ? min(tics, length(expected)) : length(expected))
    for (i in range(min(sync.compared, length(got)))) {
        if (got[i] != expected[i]) {
            sync.desync = "expected `{expected[i]}`, got `{got[i]}`"
            sync.fields = differing_fields(expected[i], got[i])
            return sync
        }
        sync.in_sync++
    }
    if (sync.compared == length(expected) && length(got) > length(expected)) {
        sync.desync = "expected the demo's end after {length(expected)} tics, got `{got[length(expected)]}`"
    }
    return sync
}

//! The `trace=` lines of `text` in order, which the `DOOM_TIC_TRACE` build of patch 0002 prints.
def trace_lines(text : string) : array<string> => <- [for (line in split(text, "\n")); line; where line |> starts_with("trace=")]

//! `sidecar`'s text with `define` first among its defines; "" with `error` set when the text has no
//! single `"defines": [` to put it after.
def with_define(sidecar, define : string; var error : string&) : string {
    let mark = "\"defines\": ["
    if (length(split(sidecar, mark)) != 2) {
        error = "no single `{mark}` to add {define} to"
        return ""
    }
    return replace(sidecar, mark, "{mark}\"{define}\", ")
}

//! The patches a reference log's header names: each path with its sha256, joined by ` + `.
def patch_list(patches : array<string>) : string => join([for (patch in patches); "{patch} (sha256 {file_sha256(patch)})"], " + ")

//! One line on `sync`: the first desync with the fields that differ, a run short of the compared tics, or `N tics in sync`.
def sync_summary(sync : TicSync) : string {
    if (!empty(sync.desync)) {
        let on = empty(sync.fields) ? "" : " on {sync.fields}"
        return "desync after {sync.in_sync} tics in sync{on}: {sync.desync}"
    }
    if (sync.in_sync < sync.compared) {
        return "the run printed {sync.in_sync} of {sync.compared} tics, all in sync"
    }
    return "{sync.in_sync} tics in sync"
}
