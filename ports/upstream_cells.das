options gen2

module upstream_cells public

require strings
require daslib/strings_boost

//! A table cell a daslang defect slows: the program or kernel, the tier whose lanes it marks (the
//! tier and its `<tier>-<variant>` lanes), the lookibed/daScript fork issue, and the x native the
//! same build gives with the defect worked around (by hand or by a patched generator), with what
//! that number is over.
struct UpstreamCell {
    program : string
    tier : string
    issue : int
    fixed : double
    fixed_over : string
}

//! What each fork issue does to a cell, the footnote's first half, in the footnotes' order: none
//! on the pin `b7d8f6f52f`, where #48's fix (upstream #4652) took its AOT cells to the x native
//! they gave with the defect worked around. A `var`, so a test can stand an issue in.
var UPSTREAM_ISSUES : array<tuple<issue : int; what : string>>

//! The cells a fork issue slows (`ARCHITECTURE_UPSTREAM.md`): none on the pin `b7d8f6f52f`. A
//! `var`, so a test can stand a cell in.
var UPSTREAM_CELLS : array<UpstreamCell>

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
            lines |> push("- (#{entry.issue}) {entry.what}; the same program's AOT reading each global at its fixed offset runs " + join(fixed, ", ") + " x native: [lookibed/daScript#{entry.issue}]({ISSUE_URL}{entry.issue}).")
        }
    }
    return <- lines
}
