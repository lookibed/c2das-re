options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/sha_256
require ../pipeline.das
require ../emit.das
require ../tiers.das

let FIXTURE = "converter/tests/fixtures/ret42.c"
let CIR_SHA = "0fc98ecbfd57f8acb5f340ca4b934f85c84b624ec962c1262aaf488bb92e9bca"
let DAS_SHA = "ee045546585d90de8cf1390a244e10065430cacdca9f586f3d61ba0c6f8608ad"

var res : ConvertResult
var out : string

[test]
def test_pipeline_ret42(t : T?) {
    if (!fexist(FIXTURE)) {
        t |> failure("run from the repository root: {FIXTURE} not found")
        return
    }
    var dir_error : string
    out = create_temp_directory("c2das_test", dir_error)
    if (!empty(dir_error)) {
        t |> failure("no temp directory: {dir_error}")
        return
    }
    res <- convert(FIXTURE, out, "msvc")
    t |> run("the P0 program converts, formats and compile-checks") @(t : T?) {
        t |> equal(res.ok, true, res.error)
        t |> equal(res.das_text |> find("def c_main : int \{\n    return 42\n\}") >= 0, true, res.das_text)
        t |> equal(res.das_text |> find("[export]\ndef main : int \{\n    return c_main()\n\}") >= 0, true, res.das_text)
        t |> equal(res.das_text |> starts_with(GENERATED_BANNER), true)
    }
    t |> run("the C-IR carries the target, the interned types and the return") @(t : T?) {
        t |> equal(res.cir_text |> find("\"cir\": \"0.1\"") >= 0, true)
        t |> equal(res.cir_text |> find("\"triple\": \"x86_64-pc-windows-msvc\"") >= 0, true)
        t |> equal(res.cir_text |> find("\"k\": \"func\"") >= 0, true)
        t |> equal(res.cir_text |> find("\"e\": \"int_lit\"") >= 0, true)
        t |> equal(res.cir_text |> find("\"v\": \"42\"") >= 0, true)
        t |> equal(res.cir_text |> ends_with("\}\n"), true)
    }
    t |> run("golden hashes of the C-IR and the das text") @(t : T?) {
        t |> equal(sha256_hex(res.cir_text), CIR_SHA, "the C-IR bytes changed:\n{res.cir_text}")
        t |> equal(sha256_hex(res.das_text), DAS_SHA, "the das text changed:\n{res.das_text}")
    }
    for (tier in ["interp", "jit", "exe", "aot"]) {
        t |> run("the converted program exits 42 under {tier}") @(t : T?) {
            if (!res.ok) {
                t |> skip("conversion failed")
                return
            }
            var output : string
            t |> equal(run_tier(res.das_path, tier, out, output), 42, output)
        }
    }
    rmdir_rec(out)
}
