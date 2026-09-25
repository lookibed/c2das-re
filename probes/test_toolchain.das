options gen2
require dastest/testing_boost public
require cbind

[test]
def test_toolchain(t : T?) {
    t |> run("cbind loads and libclang answers") @(t : T?) {
        let idx = clang_createIndex(0, 0)
        t |> success(idx != null, "clang_createIndex")
        clang_disposeIndex(idx)
    }
}
