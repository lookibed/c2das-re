options gen2
options indenting = 4
options stack = 8388608

//! The translator page's Lua console (web/ARCHITECTURE.md section 8): Lua 5.4 as c2das-ports'
//! `lua/readable` converts it, compiled to wasm64, running the page's Lua code. The build stages
//! this file beside the converted modules. Each animation frame it looks for `/io/lua.go`, runs
//! `/io/script.lua` in a fresh Lua state with the standard libraries (Lua's `print` writes to the
//! page through stdout), prints the error if the chunk fails, and answers `/io/lua.done`. `os.exit`
//! raises a Lua error instead: an exit would end the program with no answer. A desktop run (`main`)
//! runs one request in the folder its first argument names, `/io` without one, and ends.

require daslib/clargs
require daslib/fio
require c_types
require crt
require lapi
require lauxlib
require lcode_cluster
require linit
require lobject_h_cluster

var private io_dir = "/io"

def private io(name : string) : string => "{io_dir}/{name}"

// run before every chunk: the page's program must outlive the chunk to answer
let private PRELUDE = "os.exit = function() error('os.exit ends nothing here: the page runs on', 2) end"

// `code` compiled and run in `L` with no arguments; the status, its error on top of the stack
def private run_in(var L : lua_State?; code : string) : int {
    var source = unsafe(reinterpret<uint8?>(code))
    var status = luaL_loadstring(L, source)
    if (status == 0) {
        status = lua_pcallk(L, 0, 0, 0, 0l, default<function<(var a0 : lua_State?; a1 : int; a2 : int64) : int>>)
    }
    return status
}

// the chunk in a fresh state after the prelude, its error printed
def private run_chunk(code : string) {
    var L = luaL_newstate()
    if (L == null) {
        print("lua: cannot create a state\n")
        return
    }
    luaL_openlibs(L)
    var status = run_in(L, PRELUDE)
    if (status == 0) {
        status = run_in(L, code)
    }
    if (status != 0) {
        let msg = lua_tolstring(L, -1, null)
        if (msg != null) {
            unsafe {
                print("lua error: {reinterpret<string>(msg)}\n")
            }
        }
    }
    lua_close(L)
    var stdout_file = unsafe(crt::c_stdout())
    unsafe(crt::fflush(stdout_file))
}

[export]
def init {
    mkdir_rec(io_dir)
    print("lua: ready\n")
}

[export]
def update : bool {
    if (fexist(io("lua.go"))) {
        remove(io("lua.go"))
        let started = ref_time_ticks()
        run_chunk(fread(io("script.lua")))
        fwrite(io("lua.done"), "{get_time_usec(started)}\n")
    }
    return true
}

[export]
def shutdown {
    pass
}

// a desktop run runs one chunk already in the folder and ends
[export]
def main {
    let args <- get_user_args()
    if (!empty(args)) {
        io_dir = args[0]
    }
    init()
    update()
}
