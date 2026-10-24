options gen2

module sources public

require daslib/fio

//! The Lua release's sources as its Makefile links each program, which `lua/run.das` converts
//! and `metrics/readability.das` measures (`ARCHITECTURE.md` section 2). Paths are relative to the
//! repository root, where both run.

//! The fetched release's `src/`.
let SOURCES = "lua/fetch/lua-5.4.8/src"

//! The sidecar both programs convert under.
let SIDECAR = "lua/lua.c2das"

//! The sources of the Makefile's `CORE_O`, in its order, then the auxiliary library of its `LIB_O`.
let CORE <- ["lapi", "lcode", "lctype", "ldebug", "ldo", "ldump", "lfunc", "lgc", "llex", "lmem", "lobject", "lopcodes", "lparser", "lstate", "lstring", "ltable", "ltm", "lundump", "lvm", "lzio", "lauxlib"]

//! The rest of `LIB_O`, the standard libraries: the interpreter links them; the compiler, which
//! calls none of them, does not, as the Makefile's archive link pulls none into it.
let STANDARD <- ["lbaselib", "lcorolib", "ldblib", "liolib", "lmathlib", "loadlib", "loslib", "lstrlib", "ltablib", "lutf8lib", "linit"]

//! The program each manifest builds: its stem, the source holding its `main`, and whether it links
//! the standard libraries.
let PROGRAMS <- [("lua", "lua", true), ("luac", "luac", false)]

//! The C files of program `stem` (`lua` or `luac`) in link order, each by its full path: the core,
//! the standard libraries when it links them, then the source holding its `main`; none for another
//! stem.
def program_sources(stem : string) : array<string> {
    var c_paths : array<string>
    for (program in PROGRAMS) {
        if (program._0 == stem) {
            var inscope sources <- clone_to_move(CORE)
            if (program._2) {
                sources |> push_from(STANDARD)
            }
            sources |> push(program._1)
            c_paths <- [for (source in sources); get_full_file_name(path_join(SOURCES, "{source}.c"))]
        }
    }
    return <- c_paths
}
