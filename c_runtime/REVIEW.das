options gen2

require daslib/fio
require strings
require daslib/strings_boost
require dastest/review_gate

// The mechanical half of c_runtime/REVIEW.md (contract: REVIEW_COMMON.md at the repo root).
// Run from the repo root: daslang c_runtime/REVIEW.das - exit 0 clean, 1 with findings.

// every piece `c_runtime/<name>.das` has its fixture test `tests/test_<name>.das`
def private gate_piece_tests {
    dir("c_runtime/c_runtime") $(name) {
        if (name |> ends_with(".das")) {
            let stem = slice(name, 0, length(name) - 4)
            if (!fexist("c_runtime/tests/test_{stem}.das")) {
                gate_finding("c_runtime/c_runtime/{name}", "has no fixture test c_runtime/tests/test_{stem}.das")
            }
        }
    }
}

[export]
def main : int {
    gate_descriptor_census("c_runtime/.das_module", ["c_runtime/c_runtime"], {"c_runtime"})
    gate_piece_tests()
    return gate_verdict("c_runtime")
}
