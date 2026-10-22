options gen2

module c_label public

//! `c_label_end()`, the statement a C label stands on in a das block that is no loop's body
//! (llex.c's `no_save: break;` once a switch's if-chain drops the tail `break`, a label ending a
//! function, one before `if (DEBUG) {...}`). daslang's interpreter jumps only to a statement inside
//! such a block, and its optimizer folds an empty block or a statement without effect away
//! (`docs/probe-findings.md` F62); a `[sideeffects]` call stays, and does nothing.

[sideeffects]
def c_label_end {
    pass
}
