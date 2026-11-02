options gen2

module sources public

require daslib/fio

//! PureDOOM's multi-file form as the harness builds it (`ARCHITECTURE.md` section 2): the units of
//! the pinned commit's `src/DOOM/` and the host holding `main`. Paths are relative to the
//! repository root, where the harness runs.

//! The fetched commit's `src/DOOM/`.
let SOURCES = "doom/fetch/PureDOOM/src/DOOM"

//! The headless host, the program's `main`.
let HOST = "doom/host/doom_main.c"

//! The sidecar the program converts under; its `defines` are the native build's too.
let SIDECAR = "doom/doom.c2das"

//! The units of `src/DOOM/`, every `.c` file, in the byte order of their names, the order of
//! PureDOOM's CMake glob.
let UNITS <- ["DOOM", "am_map", "d_items", "d_main", "d_net", "doomdef", "doomstat", "dstrings", "f_finale", "f_wipe", "g_game", "hu_lib", "hu_stuff", "i_net", "i_sound", "i_system", "i_video", "info", "m_argv", "m_bbox", "m_cheat", "m_fixed", "m_menu", "m_misc", "m_random", "m_swap", "p_ceilng", "p_doors", "p_enemy", "p_floor", "p_inter", "p_lights", "p_map", "p_maputl", "p_mobj", "p_plats", "p_pspr", "p_saveg", "p_setup", "p_sight", "p_spec", "p_switch", "p_telept", "p_tick", "p_user", "r_bsp", "r_data", "r_draw", "r_main", "r_plane", "r_segs", "r_sky", "r_things", "s_sound", "sounds", "st_lib", "st_stuff", "tables", "v_video", "w_wad", "wi_stuff", "z_zone"]

//! The C files of the program in link order, each by its full path: the units, then the host.
def program_sources : array<string> {
    var c_paths <- [for (unit in UNITS); get_full_file_name(path_join(SOURCES, "{unit}.c"))]
    c_paths |> push(get_full_file_name(HOST))
    return <- c_paths
}
