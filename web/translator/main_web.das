options gen2
options indenting = 4

//! The translator page's program (web/ARCHITECTURE.md section 8): c2das-re's own C-IR-to-das path
//! (`converter/cir_emit.das`; the build stages this file beside the converter's modules) compiled to wasm64, driven by daslang's web lifecycle. It has no
//! window: each animation frame it looks for a request the page left in the in-memory file system,
//! `/io/go`, converts `/io/in.cir.json` under the sidecar `/io/sidecar.c2das`, and answers with
//! `/io/out.das` or `/io/out.err`, then `/io/done`. The page writes the request and polls for the
//! answer, so a conversion costs one frame plus its own time.

require daslib/fio
require cir_emit
require sidecar

let private IO = "/io"

def private io(name : string) : string => "{IO}/{name}"

// one request: the C-IR and the sidecar the page wrote, the module or the error back
def private answer {
    remove(io("go"))
    remove(io("out.das"))
    remove(io("out.err"))
    let started = ref_time_ticks()
    var side_error : string
    let side <- read_sidecar(io("sidecar.c2das"), side_error)
    var error = empty(side_error) ? "" : "sidecar: {side_error}"
    if (empty(error)) {
        let emitted <- cir_to_das(fread(io("in.cir.json")), side)
        if (empty(emitted.error)) {
            fwrite(io("out.das"), emitted.das_text)
        } else {
            error = emitted.error
        }
    }
    if (!empty(error)) {
        fwrite(io("out.err"), error)
    }
    fwrite(io("done"), "{get_time_usec(started)}\n")
}

[export]
def init {
    mkdir_rec(IO)
    print("translator: ready\n")
}

[export]
def update : bool {
    if (fexist(io("go"))) {
        answer()
    }
    return true
}

[export]
def shutdown {
    pass
}

// a desktop run answers one request already in /io and ends
[export]
def main {
    init()
    update()
}
