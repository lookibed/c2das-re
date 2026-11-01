options gen2

module _common public

require daslib/fio

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
