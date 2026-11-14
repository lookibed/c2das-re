options gen2

module upstream_cells public

require strings
require daslib/strings_boost

//! A table cell a daslang defect slows: the program or kernel, the tier whose lanes it marks (the
//! tier and its `<tier>-<variant>` lanes), the lookibed/daScript fork issue, and the x native the
//! same build gives with the defect worked around by hand, with what that number is over.
struct UpstreamCell {
    program : string
    tier : string
    issue : int
    fixed : double
    fixed_over : string
}

//! What each fork issue does to a cell, the footnote's first half, in the footnotes' order.
let UPSTREAM_ISSUES : array<tuple<issue : int; what : string>> <- [(issue = 48, what = "daslang's AOT generator reads every module global through a hash lookup (`das_global<T, mnh>`), though the AOT context fixes each global's offset when it is generated")]

//! The cells #48 slows, proven by the A/B of the same generated C++ with every global read
//! rewritten to its fixed offset (`das_global_solid`), exclusive on box PC at daScript `6401904cf9`.
let UPSTREAM_CELLS <- [
    UpstreamCell(program = "puredoom", tier = "aot", issue = 48, fixed = 1.14lf, fixed_over = "readable, demo1"),
    UpstreamCell(program = "sieve", tier = "aot", issue = 48, fixed = 1.63lf),
    UpstreamCell(program = "str_copy", tier = "aot", issue = 48, fixed = 1.40lf),
    UpstreamCell(program = "switch_local", tier = "aot", issue = 48, fixed = 1.00lf),
    UpstreamCell(program = "matmul", tier = "aot", issue = 48, fixed = 1.01lf)
]

let private ISSUE_URL = "https://github.com/lookibed/daScript/issues/"

// whether `lane` is `tier` or one of its variant lanes (`aot-fast` of `aot`)
def private lane_of_tier(lane, tier : string) : bool => lane == tier || lane |> starts_with("{tier}-")

// whether any of `lanes` is one of `tier`'s
def private shows_tier(lanes : array<string>; tier : string) : bool {
    for (lane in lanes) {
        if (lane_of_tier(lane, tier)) {
            return true
        }
    }
    return false
}

//! The fork issue that slows `program`'s cell under `lane`, 0 for none.
[arch(at="ARCHITECTURE_UPSTREAM.md#upstream-cells")]
def upstream_issue(program, lane : string) : int {
    for (c in UPSTREAM_CELLS) {
        if (c.program == program && lane_of_tier(lane, c.tier)) {
            return c.issue
        }
    }
    return 0
}

//! `text` with the issue that slows `program` under `lane` after it, `5.19 (#48)`; unchanged
//! when no issue slows it or `text` holds no number (`n/a`, `not yet`, an error).
def upstream_marked(text, program, lane : string) : string {
    let issue = upstream_issue(program, lane)
    if (issue == 0 || empty(text) || !is_number(first_character(text))) {
        return text
    }
    return "{text} (#{issue})"
}

//! The footnote lines for the cells of `programs` marked under any of `lanes`: one line per issue,
//! what it does, the x native each program gives with it worked around, and the issue's link; none
//! when no cell is marked.
def upstream_footnotes(programs, lanes : array<string>) : array<string> {
    var lines : array<string>
    for (entry in UPSTREAM_ISSUES) {
        var inscope fixed <- [for (c in UPSTREAM_CELLS); "{c.program} {c.fixed:.2f}" + (empty(c.fixed_over) ? "" : " ({c.fixed_over})"); where c.issue == entry.issue && has_value(programs, c.program) && shows_tier(lanes, c.tier)]
        if (!empty(fixed)) {
            lines |> push("- (#{entry.issue}) {entry.what}; the same generated C++ with each read rewritten to its offset runs " + join(fixed, ", ") + " x native: [lookibed/daScript#{entry.issue}]({ISSUE_URL}{entry.issue}).")
        }
    }
    return <- lines
}
