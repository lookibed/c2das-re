options gen2
// the pipeline parses clang's JSON dump below its own frames
options stack = 1048576
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require ../convert_check.das
require ../../converter/pipeline.das
require ../../converter/tiers.das

//! The patches of `doom/patches/` held to what they fix, without the release: a patch's hunk,
//! before and after, spliced into a stand-in of the code around it, converted and run in a child
//! process for its exit code. 0005's hunk of `IdentifyVersion` under a `doom_malloc` that puts 16
//! canary bytes past every block: the pre-image writes the path's NUL one byte past the
//! `doomu.wad` block, the post-image stays inside it.

let PATCH_0005 = "doom/patches/0005-doomu-wad-path.patch"

// per file `patch` names, its hunks' lines in order on one side: the context and removed lines
// (the pre-image) or the context and added lines (the post-image)
def private hunk_images(patch : string; post : bool) : table<string; string> {
    var files : table<string; string>
    var current = ""
    var in_hunk = false
    let side = post ? "+" : "-"
    for (line in split(fread(patch), "\n")) {
        if (line |> starts_with("diff --git ")) {
            in_hunk = false
        } elif (line |> starts_with("--- a/")) {
            current = slice(line, 6)
        } elif (line |> starts_with("@@")) {
            in_hunk = !empty(current)
        } elif (in_hunk && (line |> starts_with(" ") || line |> starts_with(side))) {
            files.insert(current, files?[current] ?? "" + slice(line, 1) + "\n")
        }
    }
    return <- files
}

// IdentifyVersion's surroundings: PureDOOM's string helpers, a `doom_malloc` that records every
// block and fills 16 bytes past its end with 0xA5, and a `main` that runs the hunk (spliced at
// `@HUNK@`) with DOOMWADDIR `/wads`, then exits 1 naming the first block whose canary changed, or
// prints the retail path and exits 0
let STAND_IN = "#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\nstatic unsigned char *blocks[4];\nstatic int sizes[4];\nstatic int count;\nvoid *doom_malloc(int size) \{\n    unsigned char *p = malloc(size + 16);\n    memset(p + size, 0xA5, 16);\n    blocks[count] = p;\n    sizes[count] = size;\n    count++;\n    return p;\n\}\nint doom_strlen(const char *str) \{\n    int len = 0;\n    while (*str++) ++len;\n    return len;\n\}\nchar *doom_strcpy(char *dst, const char *src) \{\n    char *ret = dst;\n    while (*src) *dst++ = *src++;\n    *dst = *src;\n    return ret;\n\}\nchar *doom_concat(char *dst, const char *src) \{\n    char *ret = dst;\n    dst += doom_strlen(dst);\n    while (*src) *dst++ = *src++;\n    *dst = *src;\n    return ret;\n\}\nint main(void) \{\n    char *doomwaddir = \"/wads\";\n    char *doom2wad = doom_malloc(64);\n    char *doomuwad;\n    doom_strcpy(doom2wad, doomwaddir);\n@HUNK@    for (int i = 0; i < count; i++)\n        for (int k = 0; k < 16; k++)\n            if (blocks[i][sizes[i] + k] != 0xA5) \{\n                printf(\"block %d of %d bytes written %d past its end\\n\", i, sizes[i], k);\n                return 1;\n            \}\n    printf(\"%s\\n\", doomuwad);\n    return 0;\n\}\n"

// `hunk` spliced into the stand-in, converted into `root` and run under the interpreter: its exit
// code, its output in `out`
def private run_stand_in(t : T?; root, hunk : string; var out : string&) : int {
    mkdir_rec(root)
    let c_path = path_join(root, "stand.c")
    fwrite(c_path, replace(STAND_IN, "@HUNK@", hunk))
    let res <- convert_program([c_path], path_join(root, "out"), TARGET, "", "", "", "", "main", "source")
    t |> equal(res.error, "", "converted")
    return run_tier(path_join(root, "out/stand.das"), "interp", path_join(root, "run"), out, CONVERTED_MODULES, 300.0)
}

[test(description = "patch 0005 gives the retail IWAD path its NUL byte: the unpatched hunk writes one byte past its block, the patched one stays inside it", timeout = 1200)]
def test_doomu_wad_path(tt : T?) {
    let file = "src/DOOM/d_main.c"
    let pre = hunk_images(PATCH_0005, false)?[file] ?? ""
    let post = hunk_images(PATCH_0005, true)?[file] ?? ""
    tt |> success(!empty(pre) && !empty(post), "0005 has a hunk of {file}")
    return if (empty(pre) || empty(post))
    tt |> run("before the patch the retail path's NUL lands one byte past its 15-byte block") @(t : T?) {
        var out : string
        t |> equal(run_stand_in(t, path_join(test_temp_dir(), "pre"), pre, out), 1, out)
        t |> success(out |> contains("block 1 of 15 bytes written 0 past its end"), out)
    }
    tt |> run("after it the path and its NUL fit the 16-byte block") @(t : T?) {
        var out : string
        t |> equal(run_stand_in(t, path_join(test_temp_dir(), "post"), post, out), 0, out)
        t |> success(out |> contains("/wads/doomu.wad"), out)
    }
}
