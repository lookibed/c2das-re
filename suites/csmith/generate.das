options gen2

module generate public

require strings
require daslib/strings_boost
require daslib/fio
require ../suite_files.das

//! A seed's program: the pinned csmith run on the seed with the option list, its runtime headers
//! spliced in, so the program is one unit both the native build and the converter take
//! (suites/ARCHITECTURE.md, the csmith run). The differential driver and the readability metric
//! generate through it.

let CSMITH_DIR = "suites/csmith/fetch/csmith"

// what the converter's dialect takes of csmith's output beyond the pinned csmith's defaults
// (suites/ARCHITECTURE.md, the csmith run)
let CSMITH_OPTIONS <- ["--no-argc", "--no-packed-struct"]

// seconds csmith may take to write a program
let CSMITH_TIMEOUT = 120.0

// the spliced program's first line: the runtime's float wrappers, dead under csmith's default
// `--no-float`, call `fabsf`, which has no c_runtime mapping and which `UNSAFE_FLOAT` drops
let PRELUDE = "#define UNSAFE_FLOAT"

// how deep the runtime's headers include each other; a deeper splice is a cycle
let SPLICE_DEPTH = 8

// the lines of `path` with every `#include "x"` the csmith runtime holds replaced by that file's
// lines, since the runtime is `static` functions in headers and the dumper converts the main
// file's declarations alone; every occurrence is spliced, since headers of one guard sit in both
// branches of an `#if` (`csmith_minimal.h` and `random_inc.h` each include a `safe_math` header)
def private splice_runtime_headers(path : string; depth : int; var out : array<string>) : bool {
    let text = fread(path)
    if (empty(text) || depth > SPLICE_DEPTH) {
        return false
    }
    for (line in split(text, "\n")) {
        let trimmed = strip(line)
        let open = trimmed |> starts_with("#include \"") ? length("#include \"") : -1
        let close = open < 0 ? -1 : find(trimmed, "\"", open)
        if (close < 0) {
            out |> push(line)
            continue
        }
        let name = slice(trimmed, open, close)
        var found = ""
        for (dir in fixed_array("{CSMITH_DIR}/runtime", "{CSMITH_DIR}/build/runtime")) {
            if (empty(found) && fexist(path_join(dir, name))) {
                found = path_join(dir, name)
            }
        }
        if (empty(found)) {
            out |> push(line)
        } elif (!splice_runtime_headers(found, depth + 1, out)) {
            return false
        }
    }
    return true
}

//! A generated program: the spliced file, or why there is none.
struct CsmithProgram {
    c_path : string
    error : string
    timed_out : bool
}

//! The program of `seed` written into `dir`: csmith's output `<seed>.csmith.c`, spliced into
//! `<seed>.c`; csmith gets `limit` seconds.
def csmith_program(seed, dir : string; limit : float) : CsmithProgram {
    mkdir_rec(dir)
    let raw = "{dir}/{seed}.csmith.c"
    var args <- ["{CSMITH_DIR}/build/src/csmith", "--seed", seed]
    args |> push_from(CSMITH_OPTIONS, ["-o", raw])
    var gen : string
    let rc = run_and_capture(args, gen, limit)
    if (rc == popen_timed_out) {
        return CsmithProgram(timed_out = true)
    }
    if (rc != 0) {
        return CsmithProgram(error = "csmith refused the seed: {first_line(gen)}")
    }
    var lines <- [PRELUDE]
    if (!splice_runtime_headers(raw, 0, lines)) {
        return CsmithProgram(error = "cannot read {raw} or a runtime header it includes")
    }
    let c_path = "{dir}/{seed}.c"
    fwrite(c_path, join(lines, "\n"))
    return CsmithProgram(c_path = c_path)
}
