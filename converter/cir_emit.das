options gen2

module cir_emit public

require daslib/das_source_formatter
require cir
require emit
require line_wrap
require sidecar

//! One unit's C-IR text to its das module text: the steps of a conversion after the dump, which the
//! pipeline's `emit_unit` and the browser page (`web/translator/`) both take, so the page runs the
//! CLI's own path. It needs neither clang nor `cbind`: the dumper's half stays in `pipeline.das`.

//! What `cir_to_das` gives: the formatted module, or the step's error ("reader: ...", "emitter:
//! ..."), and the emitter's counts the pipeline reports.
struct CirEmitted {
    das_text : string
    error : string
    c_functions : int
    function_count : int
    fold_counts : table<string; int>
}

//! The module `tu` spells under `side`, formatted; `tu` is deleted.
def tu_to_das(var tu : CirTu; side : Sidecar) : CirEmitted {
    var res : CirEmitted
    // on the heap: an `Emitter` in this frame would take a third of das's default stack from the walk under it
    var em = new Emitter
    emit_tu(*em, tu, side)
    delete_tu(tu)
    if (empty(em.error)) {
        res.c_functions = em.c_functions
        res.function_count = em.function_count
        res.fold_counts := em.fold_counts
    } else {
        res.error = "emitter: {em.error}"
    }
    let text = em.text
    unsafe {
        delete em
    }
    if (empty(res.error) && has_mark(text)) {
        res.error = "emitter: a line-layout mark reached the module"
    }
    if (empty(res.error)) {
        res.das_text = format_source_string(text)
    }
    return <- res
}

//! The module the C-IR text `cir_text` (one unit, `write_cir`'s bytes) spells under `side`.
def cir_to_das(cir_text : string; side : Sidecar) : CirEmitted {
    var read_error : string
    var tu <- read_cir(cir_text, read_error)
    if (!empty(read_error)) {
        delete_tu(tu)
        var res : CirEmitted
        res.error = "reader: {read_error}"
        return <- res
    }
    return <- tu_to_das(tu, side)
}
