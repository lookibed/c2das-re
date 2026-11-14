options gen2

require strings
require daslib/strings_boost
require ports_render

//! PureDOOM's directory of the ports repository (`ARCHITECTURE_PUREDOOM.md`): the demo-sync record
//! the publish keeps beside the conversion, each patch's note and the README. It runs and reads
//! nothing; `publish.das` runs the harness and hands the texts in.

//! the tiers and the demos a publish holds to the reference logs
let SYNC_TIERS <- ["interp", "jit", "exe", "aot"]
let SYNC_DEMOS <- [1, 2, 3]

//! one demo of freedoom2 run by the converted program under one tier: the harness's verdict
struct SyncCell {
    tier : string
    demo : int
    verdict : string
}

//! The verdict of `doom/run.das --run --tier <tier> --demo <demo>`, which exited `rc` and printed
//! `out`: its summary line's text between the run's name and ` against <log>` (`N tics in sync`),
//! `fails: ` before it when the run did not pass; a run with no summary line fails on its first
//! reported line or its exit code.
def sync_verdict(tier : string; demo : int; rc : int; out : string) : string {
    let head = "{tier} demo{demo} on "
    var summary = ""
    for (line in split(out, "\n")) {
        let at = find(line, head)
        let colon = at < 0 ? -1 : find(line, ": ", at)
        if (colon >= 0 && empty(summary)) {
            let rest = slice(line, colon + 2)
            let against = find(rest, " against ")
            summary = against < 0 ? rest : slice(rest, 0, against)
        }
    }
    if (empty(summary)) {
        let first = first_line_of(out)
        summary = empty(first) ? "exit {rc}" : "exit {rc}: {first}"
    }
    return rc == 0 ? summary : "fails: {summary}"
}

def private first_line_of(text : string) : string {
    for (l in split(text, "\n")) {
        let line = strip(l)
        if (!empty(line) && !(line |> starts_with("[I] "))) {
            return length(line) > 160 ? slice(line, 0, 157) + "..." : line
        }
    }
    return ""
}

//! Whether the log of `doom/run.das --convert` reports the program converted in the source layout:
//! its `program (source): N files` line. The run's exit code does not tell, since it also fails
//! when a unit alone does not convert, which most units cannot without the link.
def program_converted(log : string) : bool {
    for (line in split(log, "\n")) {
        if (line |> contains("doom: program (source): ") && line |> ends_with(" partition lines")) {
            return true
        }
    }
    return false
}

//! `cells` as the record a publish keeps: a line per cell, its tier, demo and verdict tab-separated.
def sync_record(cells : array<SyncCell>) : string => join([for (c in cells); "{c.tier}\t{c.demo}\t{c.verdict}\n"], "")

//! The cells of a record `sync_record` wrote; a line without three fields is left out.
def read_sync(text : string) : array<SyncCell> {
    var cells : array<SyncCell>
    for (line in split(text, "\n")) {
        var inscope fields <- split(line, "\t")
        if (length(fields) == 3) {
            cells |> push(SyncCell(tier = fields[0], demo = to_int(fields[1]), verdict = fields[2]))
        }
    }
    return <- cells
}

//! The note of a patch file of `doom/patches/`: its first line, then its `- ` items with their
//! continuation lines joined, up to the diff; the copyright paragraph between them left out.
def patch_note(text : string) : string {
    let lines <- split(text, "\n")
    if (empty(lines)) {
        return ""
    }
    var items : array<string>
    for (line in lines) {
        if (line |> starts_with("diff ") || line |> starts_with("--- ") || line == "---") {
            break
        } elif (line |> starts_with("- ")) {
            items |> push(slice(line, 2))
        } elif (!empty(items) && line |> starts_with("  ") && !empty(strip(line))) {
            items[length(items) - 1] += " " + strip(line)
        }
    }
    var parts <- [strip(lines[0])]
    parts |> push_from(items)
    return join(parts, " ")
}

//! the inputs of PureDOOM's README: the pinned commit, the `freedoom:` line of `VERSIONS.md`, each
//! patch's file name and note, each variant's sync cells, the generation line, the command that
//! regenerated the directory, the variants section and the performance section's text
struct PureDoomReadme {
    pin : string
    freedoom : string
    patches : array<tuple<name : string; note : string>>
    syncs : array<tuple<name : string; cells : array<SyncCell>>>
    variants_text : string
    generation : string
    command : string
    fps_text : string
}

def private sync_table(cells : array<SyncCell>) : string {
    var rows : array<array<string>>
    rows |> reserve(length(SYNC_TIERS))
    for (tier in SYNC_TIERS) {
        var inscope row <- [tier]
        row |> reserve(1 + length(SYNC_DEMOS))
        for (demo in SYNC_DEMOS) {
            var verdict = "not run"
            for (c in cells) {
                if (c.tier == tier && c.demo == demo) {
                    verdict = c.verdict
                }
            }
            row |> push(verdict)
        }
        rows |> emplace(row)
    }
    return table_of(["Tier", "demo1", "demo2", "demo3"], rows, 4)
}

//! PureDOOM's README: the conversion, the patches, the game data it does not hold, how to run it,
//! the demo sync per tier and the frame rate against the native build.
def puredoom_readme_text(r : PureDoomReadme) : string {
    return build_string() $(var w) {
        w |> write("# puredoom\n\n")
        w |> write("[PureDOOM](https://github.com/Daivuk/PureDOOM) (Daivuk's embeddable Doom, GPL-2) at `{r.pin}`, patched, converted to daslang by [c2das-re](https://github.com/lookibed/c2das-re): ")
        w |> write("the 62 C files of `src/DOOM/` and c2das-re's headless host `doom/host/doom_main.c`, which holds `main`. ")
        w |> write("Everything in this directory is generated by `{r.command}` in c2das-re; never edit it, a fix belongs in c2das-re.\n\n")
        w |> write("## Variants\n\n{r.variants_text}\n")
        w |> write("## Files\n\n")
        for (v in r.syncs) {
            w |> write("- `{v.name}/doom/` - the {v.name} variant's conversion, a module per C file (`{v.name}/doom/program.layout.txt` lists the modules); `{v.name}/doom/doom_main.das` holds `main`.\n")
            w |> write("- `{v.name}/doom.c2das` - the sidecar the {v.name} variant was converted under, `{v.name}/variant.json` - its knobs with the reason and the numbers behind each.\n")
        }
        w |> write("- `patches/` - the patches c2das-re applies to the pinned commit before converting it.\n")
        w |> write("- `LICENSE` - PureDOOM's license, the GNU GPL version 2; the conversion and the patches are distributed under it.\n\n")
        w |> write("## Source\n\n")
        w |> write("- Upstream: https://github.com/Daivuk/PureDOOM at `{r.pin}`, with c2das-re's patches applied in order:\n")
        for (p in r.patches) {
            w |> write("  - `{p.name}` - {p.note}\n")
        }
        w |> write("- {r.generation}\n\n")
        w |> write("## Game data\n\n")
        w |> write("No WAD is published here. The demos run on `freedoom2.wad` of Freedoom (BSD), {r.freedoom}. ")
        w |> write("c2das-re's `doom/fetch.sh` clones PureDOOM at the pin, applies the patches, downloads that release, checks both hashes and extracts the wad into `doom/fetch/wads/`. ")
        w |> write("PureDOOM opens `$DOOMWADDIR/doom2.wad`, so a run links the wad under that name in its own folder.\n\n")
        w |> write("## Running\n\n")
        w |> write("The modules require c2das-re's `crt` and `c_runtime` modules: a c2das-re checkout at the commit above, with the daScript its `VERSIONS.md` pins built, `scripts/build_crt.sh` run and `doom/fetch.sh` run. With `<c2das-re>` that checkout:\n\n```\n")
        let load = "daslang -load_module <c2das-re>/dasCRuntime -load_module <c2das-re>/c_runtime"
        w |> write("mkdir run && ln -s <c2das-re>/doom/fetch/wads/freedoom2.wad run/doom2.wad\n")
        w |> write("DOOMWADDIR=run {load} readable/doom/doom_main.das -- -timedemo demo1\n")
        w |> write("DOOMWADDIR=run {load} -jit fast/doom/doom_main.das -- -timedemo demo1\n")
        w |> write("{load} -exe fast/doom/doom_main.das -output doom_exe && DOOMWADDIR=run ./doom_exe -timedemo demo1\n")
        w |> write("# the native build the tables compare with, in <c2das-re>:\n")
        w |> write("daslang -load_module dasCRuntime -load_module c_runtime doom/run.das -- --native\n```\n\n")
        w |> write("Everything after `--` is the program's own command line; the program plays the demo headless and ends with `timed N gametics`.\n\n")
        w |> write("## Demo sync\n\n")
        w |> write("Each demo of freedoom2 played by each variant's converted program under each tier, its per-tic game-state and frame checksums (patch `0001`) held to the native build's reference log `doom/ref/freedoom2_demo<N>.log` of c2das-re ")
        w |> write("by `doom/run.das --run --tier <tier> --demo <N> --variant <its file> --layout <its layout>`, run by this publish:\n\n")
        for (v, idx in r.syncs, count()) {
            w |> write("{idx > 0 ? "\n" : ""}`{v.name}/`:\n\n")
            w |> write(sync_table(v.cells))
        }
        w |> write("\n## Performance\n\n{r.fps_text}")
    }
}
