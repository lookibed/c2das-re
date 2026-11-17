options gen2
require dastest/testing_boost public
require daslib/fio
require strings
require ../pipeline.das
require ../cir_emit.das
require ../sidecar.das

//! `cir_emit.das`, the C-IR-to-das half the browser page runs: over a fixture's C-IR it gives the
//! module the whole pipeline wrote, and a C-IR that does not read gives the reader's error.

let FIXTURES = ["converter/tests/fixtures/p1_loops.c", "converter/tests/fixtures/p2_arrays.c"]

[test(description = "cir_to_das over a converted fixture's C-IR gives the pipeline's module, byte for byte, under the defaults and under other knobs")]
def test_cir_to_das_matches_pipeline(t : T?) {
    var dir_error : string
    let out = create_temp_directory("c2das_cir_emit", dir_error)
    t |> equal(dir_error, "")
    for (fixture in FIXTURES) {
        for (dispatch in ["", "goto"]) {
            var res <- convert(fixture, out, "linux", "", "", "", "", "", dispatch)
            t |> success(res.ok, "{fixture} converts: {res.error}")
            if (!res.ok) {
                continue
            }
            var side_error : string
            var side <- read_sidecar("", side_error)
            t |> equal(side_error, "")
            if (!empty(dispatch)) {
                side.switch_dispatch = dispatch
            }
            var emitted <- cir_to_das(res.cir_text, side)
            t |> equal(emitted.error, "")
            t |> success(emitted.das_text == res.das_text, "{fixture} {dispatch}: the page's module is the pipeline's")
            t |> equal(emitted.function_count, res.function_count)
        }
    }
    rmdir_rec(out)
}

[test(description = "a C-IR text that does not read gives the reader's error and no module")]
def test_cir_to_das_bad_cir(t : T?) {
    var side_error : string
    var side <- read_sidecar("", side_error)
    var emitted <- cir_to_das("\{ not c-ir", side)
    t |> success(starts_with(emitted.error, "reader: "), emitted.error)
    t |> equal(emitted.das_text, "")
}
