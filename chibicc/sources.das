options gen2

module sources public

require daslib/fio
require daslib/strings_boost

//! chibicc's sources as its Makefile links them, which the conversion test converts
//! (`ARCHITECTURE.md` section 2). Paths are relative to the repository root.

//! The fetched checkout with `patches/` applied.
let SOURCES = "chibicc/fetch/chibicc"

//! The sidecar the program converts under.
let SIDECAR = "chibicc/chibicc.c2das"

//! The native compiler `fetch.sh` builds from the same sources, the converted one's oracle.
let NATIVE = "chibicc/fetch/chibicc/chibicc"

//! The C files of the program in link order, the unit holding `main` last.
let UNITS <- ["codegen", "hashmap", "parse", "preprocess", "strarray", "tokenize", "type", "unicode", "host", "main"]

//! The program manifest's text: the units by their full paths and `main` as the entry.
def program_manifest : string {
    let folder = get_full_file_name(SOURCES)
    let tus <- [for (unit in UNITS); "\"{folder}/{unit}.c\""]
    let list = join(tus, ", ")
    return "\{\n \"tus\": [{list}],\n \"entry\": \"main\"\n\}\n"
}
