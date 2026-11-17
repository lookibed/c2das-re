options gen2
options indenting = 4
options stack = 8388608

//! The translator page's Lua console (web/ARCHITECTURE.md section 8): Lua 5.4 as c2das-ports'
//! `lua/readable` converts it, compiled to wasm64, running the page's Lua code. The build stages
//! this file beside the converted modules. Each animation frame it looks for `/io/lua.go`, runs
//! `/io/script.lua` in a fresh Lua state with the standard libraries (Lua's `print` writes to the
//! page through stdout), prints the error if the chunk fails, and answers `/io/lua.done`.

require daslib/fio
require c_types
require crt
require lapi
require lauxlib
require lcode_cluster
require linit
require lobject_h_cluster

let private IO = "/io"

def private io(name : string) : string => "{IO}/{name}"

// the chunk in a fresh state: compiled, run with no arguments, its error printed
def private run_chunk(code : string) {
    var L = luaL_newstate()
    if (L == null) {
        print("lua: cannot create a state\n")
        return
    }
    luaL_openlibs(L)
    var source = unsafe(reinterpret<uint8?>(code))
    var status = luaL_loadstring(L, source)
    if (status == 0) {
        status = lua_pcallk(L, 0, 0, 0, 0l, default<function<(var a0 : lua_State?; a1 : int; a2 : int64) : int>>)
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
    mkdir_rec(IO)
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

// a desktop run runs one chunk already in /io and ends
[export]
def main {
    init()
    update()
}
