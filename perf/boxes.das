options gen2

module boxes public

require strings
require daslib/strings_boost
require daslib/json_boost

//! The boxes that measure, the one place their names live: a capture records the box it ran on
//! beside its CPU model, and every table renders the two as one label, so a number always carries
//! the box it came from. It measures nothing and reads no file.

//! a CPU-model substring to the name of the box with that CPU, matched in this order
let BOXES <- [("Ryzen 3 1200", "bench"), ("Ryzen 7 7435HS", "PC"), ("FX(tm)-6300", "fx")]
//! the label of a capture that records neither its box nor its CPU
let UNLABELLED = "unlabelled box"
//! the spread above which a cell is suspect, ruling 29's publish rule for every table of a capture
//! (ports, compare, perf): never a number, never in a ratio, a mean or a delta
let SUSPECT_SPREAD = 0.2lf
let SUSPECT = "suspect"

//! Whether a cell of spread `spread` is suspect: above `SUSPECT_SPREAD`.
def is_suspect(spread : double) : bool => spread > SUSPECT_SPREAD

//! A suspect cell's text: `suspect` with its spread to a tenth of a percent.
def suspect_text(spread : double) : string => "{SUSPECT} (±{spread * 100.0lf:.1f}%)"

//! The box of the first `BOXES` substring `cpu` contains, "" when none does.
def box_of(cpu : string) : string {
    for (b in BOXES) {
        if (find(cpu, b._0) >= 0) {
            return b._1
        }
    }
    return ""
}

//! `<box> (<cpu>)`; the cpu alone without a box, the box alone without a cpu, `UNLABELLED` without either.
def box_label(box, cpu : string) : string {
    if (empty(box)) {
        return empty(cpu) ? UNLABELLED : cpu
    }
    return empty(cpu) ? box : "{box} ({cpu})"
}

//! The box a capture records, and a renderer shows: `named` (the `--box` flag, or the box a
//! capture stored) when there is one, else the box of `cpu`.
def capture_box(named, cpu : string) : string => empty(named) ? box_of(cpu) : named

//! "" when `flag` is empty, or names a box of `BOXES` that `cpu`, the CPU the run is on, does not
//! contradict; else the refusal of `--box`: a wrong label is worse than none.
def box_refusal(flag, cpu : string) : string {
    if (empty(flag)) {
        return ""
    }
    if (!has_value([for (b in BOXES); b._1], flag)) {
        return "--box takes " + join([for (b in BOXES); b._1], ", ") + ", not `{flag}`"
    }
    let own = box_of(cpu)
    return empty(own) || own == flag ? "" : "--box {flag} names another box than this CPU's: {cpu} is {own}"
}

//! The box of the capture `js`, else its CPU model when it names no box: what tells two
//! captures' machines apart.
def private machine_key(js : JsonValue const?) : string {
    let cpu = js?["cpu"] ?? ""
    let box = capture_box(js?["box"] ?? "", cpu)
    return empty(box) ? cpu : box
}

//! True when captures `a` and `b` ran on one box: the same box, or, where neither names one, the
//! same CPU model; false when either names neither.
def same_box(a, b : JsonValue const?) : bool {
    let key = machine_key(a)
    return !empty(key) && key == machine_key(b)
}

//! The line a renderer or a check prints in place of a comparison of captures `a` and `b` from two boxes.
def two_boxes_line(what : string; a, b : JsonValue const?) : string => "no {what}: {capture_label(a)} against {capture_label(b)}, numbers of two boxes are not compared"

//! The label of the capture or section `js` from its `box` and `cpu` fields, a capture written
//! before captures recorded a box showing the box of its cpu.
def capture_label(js : JsonValue const?) : string {
    let cpu = js?["cpu"] ?? ""
    return box_label(capture_box(js?["box"] ?? "", cpu), cpu)
}
