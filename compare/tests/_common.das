options gen2

module _common public

require daslib/fio
require ../../perf/perf_lanes.das
require ../../perf/boxes.das

//! What the compare tests share.

//! `body` with `C2DAS_RUST_BIN` and `C2DAS_RUST` set to `bin_var` and `checkout_var`, both
//! restored after it.
def with_env(bin_var, checkout_var : string; body : block<() : void>) {
    let saved_bin = get_env_variable("C2DAS_RUST_BIN")
    let saved_checkout = get_env_variable("C2DAS_RUST")
    set_env_variable("C2DAS_RUST_BIN", bin_var)
    set_env_variable("C2DAS_RUST", checkout_var)
    invoke(body)
    set_env_variable("C2DAS_RUST_BIN", saved_bin)
    set_env_variable("C2DAS_RUST", saved_checkout)
}

//! A `--box` this machine accepts: its own box, `fx` on a CPU `BOXES` does not name.
def flag_box : string {
    let own = box_of(cpu_name())
    return empty(own) ? "fx" : own
}
