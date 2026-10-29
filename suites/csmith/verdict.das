options gen2

module verdict public

require strings
require daslib/strings_boost
require daslib/fio
require ../suite_runner.das
require ../../converter/cir.das

//! A seed's verdict as a worker writes it beside the program, and the outcome the driver draws
//! from a worker that ended: its verdict, or `timeout` when the driver killed it, or `crash`
//! when it exited on its own without one.

//! A verdict line: the status, the signature a reduction keeps, and the reason for a person; an
//! empty status when no worker wrote one.
struct Verdict {
    status : string
    signature : string
    reason : string
}

def verdict_path(c_path : string) : string => path_join(dir_name(c_path), "{file_stem(c_path)}.verdict")

def write_verdict(c_path : string; v : Verdict) {
    fwrite(verdict_path(c_path), "{v.status}\t{v.signature}\t{v.reason}\n")
}

def read_verdict(c_path : string) : Verdict {
    let fields <- split(strip(fread(verdict_path(c_path))), "\t")
    if (length(fields) < 2) {
        return Verdict()
    }
    return Verdict(status = fields[0], signature = fields[1], reason = length(fields) > 2 ? fields[2] : "")
}

//! The outcome of seed `id`'s worker: `timeout` when the driver `killed` it past `limit`
//! seconds, `crash` when it exited with `rc` and no verdict, else the verdict it wrote.
def worker_outcome(id : string; killed : bool; rc : int; limit : float; v : Verdict) : Outcome {
    if (killed) {
        return Outcome(id = id, status = "timeout", reason = "the worker took longer than {int(limit)} s")
    }
    if (empty(v.status)) {
        return Outcome(id = id, status = "crash", reason = "the worker exited {rc} without a verdict")
    }
    return Outcome(id = id, status = v.status, reason = v.reason)
}
