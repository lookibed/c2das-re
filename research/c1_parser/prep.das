options gen2

// Preprocesses the probe's inputs with clang under Dumper A's frontend flags (`dumper_frontend_flags`
// of the linux dialect) plus each program's sidecar defines: `-- <out_dir> <fetch_root>`, where
// fetch_root is the checkout whose `lua/fetch`, `doom/fetch` and `suites/c_testsuite/fetch` trees are
// read. Writes `<out_dir>/<name>.i` per unit and `<out_dir>/inputs.txt`, one `name<TAB>path.i` line
// each, the five large files first.

require daslib/fio
require strings
require daslib/strings_boost
require ../../converter/dumper_a.das
require ../../converter/cir.das

struct Unit {
    name : string
    path : string
    defines : array<string>
}

let LUA_DEFINES <- ["LUA_USE_JUMPTABLE=0"]
let DOOM_DEFINES <- ["DOOM_IMPLEMENT_PRINT", "DOOM_IMPLEMENT_MALLOC", "DOOM_IMPLEMENT_FILE_IO", "DOOM_IMPLEMENT_EXIT", "DOOM_IMPLEMENT_GETENV", "DOOM_TIC_CHECKSUM"]

def units_of(root : string) : array<Unit> {
    var units : array<Unit>
    let lua = "{root}/lua/fetch/lua-5.4.8/src"
    let doom = "{root}/doom/fetch/PureDOOM/src/DOOM"
    units |> emplace(Unit(name = "lua_lvm", path = "{lua}/lvm.c", defines <- clone_to_move(LUA_DEFINES)))
    units |> emplace(Unit(name = "lua_lparser", path = "{lua}/lparser.c", defines <- clone_to_move(LUA_DEFINES)))
    units |> emplace(Unit(name = "doom_p_enemy", path = "{doom}/p_enemy.c", defines <- clone_to_move(DOOM_DEFINES)))
    units |> emplace(Unit(name = "doom_g_game", path = "{doom}/g_game.c", defines <- clone_to_move(DOOM_DEFINES)))
    units |> emplace(Unit(name = "doom_info", path = "{doom}/info.c", defines <- clone_to_move(DOOM_DEFINES)))
    let ts = "{root}/suites/c_testsuite/fetch/c-testsuite/tests/single-exec"
    var ids : array<string>
    dir(ts) $(f) {
        if (ends_with(f, ".c")) {
            ids |> push(slice(f, 0, length(f) - 2))
        }
    }
    sort(ids)
    for (id in ids) {
        units |> emplace(Unit(name = "cts_{id}", path = "{ts}/{id}.c"))
    }
    return <- units
}

[export]
def main() {
    let args <- get_command_line_arguments()
    let at = find_index(args, "--")
    if (at < 0 || at + 2 >= length(args)) {
        print("usage: prep.das -- <out_dir> <fetch_root>\n")
        unsafe(fio::exit(2))
    }
    let out_dir = args[at + 1]
    let root = args[at + 2]
    var error : string
    let frontend <- dumper_frontend_flags(target_by_name("linux"), error)
    if (!empty(error)) {
        print("{error}\n")
        unsafe(fio::exit(1))
    }
    var list : array<string>
    var failed = 0
    for (u in units_of(root)) {
        let out_path = "{out_dir}/{u.name}.i"
        var argv <- [default_clang(), "-E"]
        argv |> push_from(frontend, [for (d in u.defines); "-D{d}"], [u.path, "-o", out_path])
        var out : string
        let rc = run_and_capture(argv, out, 120.0)
        if (rc != 0) {
            print("{u.name}: clang -E exited {rc}: {out}\n")
            failed++
            continue
        }
        list |> push("{u.name}\t{out_path}")
    }
    fwrite("{out_dir}/inputs.txt", join(list, "\n") + "\n")
    print("{length(list)} units preprocessed, {failed} failed\n")
}
