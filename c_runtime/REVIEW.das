options gen2

require dastest/review_gate

// The mechanical half of c_runtime/REVIEW.md (contract: REVIEW_COMMON.md at the repo root).
// Run from the repo root: daslang c_runtime/REVIEW.das - exit 0 clean, 1 with findings.

[export]
def main : int {
    gate_descriptor_census("c_runtime/.das_module", ["c_runtime/c_runtime"], {"c_runtime"})
    return gate_verdict("c_runtime")
}
