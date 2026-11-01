options gen2

module audit_tables public

require strings
require daslib/strings_boost
require daslib/json_boost
require daslib/md_boost
require audit_constructs

//! The tables of the interpreter audit's capture (`perf/audit_linux.json`): the construct table and
//! the whole-benchmark table. It measures nothing and reads no file.

//! the Lua benchmarks the audit times whole, each with the argument it runs with
struct Bench {
    name : string
    arg : string
}

//! the four benchmarks of `ports/lua/bench/`, each smaller than the ports' default so the
//! interpreter lanes end in seconds
let BENCHES <- [Bench(name = "fib", arg = "27"), Bench(name = "binary_trees", arg = "12"), Bench(name = "nbody", arg = "20000"), Bench(name = "spectral_norm", arg = "100")]

def time_of(cell : JsonValue?) : double => cell?["time"] ?? 0.0lf

//! Whether the JSON object `js` holds `key`.
def has_key(js : JsonValue?; key : string) : bool => js != null && js.value is _object && key_exists(js.value as _object, key)

def private factor_text(num, den : double) : string => num > 0.0lf && den > 0.0lf ? "{num / den:.2f}x" : "n/a"

// a cell's error, clipped to the table
def private why(cell : JsonValue?) : string {
    let e = cell?["error"] ?? ""
    return empty(e) ? "n/a" : "error: {length(e) > 60 ? slice(e, 0, 60) + "..." : e}"
}

// the error of `parent`'s `lane` cell, else of `parent` itself (a step every lane stands on)
def private why_lane(parent : JsonValue?; lane : string) : string {
    let own = why(parent?[lane])
    return own != "n/a" ? own : why(parent)
}

// why a construct's `lane` has no cost: the rewrite's error, else the conversion's
def private cost_error(conv, alt : JsonValue?; lane : string) : string {
    let own = why_lane(alt, lane)
    return own != "n/a" ? own : why_lane(conv, lane)
}

//! The JIT's converted time over the rewrite's, or `SUSPECT` when the rewrite runs under a tenth of
//! native: the rewrite then let the JIT drop the kernel's work, a different program.
def jit_cost_text(conv, alt : JsonValue?; native : double) : string {
    let t = time_of(alt?["jit"])
    if (t <= 0.0lf) {
        return cost_error(conv, alt, "jit")
    }
    return t * 10.0lf < native ? "SUSPECT {t / native:.3f}x native" : factor_text(time_of(conv?["jit"]), t)
}

//! The construct table of a capture: per construct the native time, the interpreter's factor over
//! native as converted, the construct's own cost (the interpreter as converted over the rewrite),
//! the same under the JIT, the Rust translation's interpreter factor and the sites in Lua's hot
//! modules.
def construct_table(js : JsonValue?) : string {
    let headers <- ["construct", "kernel", "native", "interp x native", "interp: converted / rewrite", "jit: converted / rewrite", "Rust interp x native", "sites {join(HOT_FILES, "/")}"]
    let aligns <- [for (h in headers); h == "construct" || h == "kernel" ? ColAlign.left : ColAlign.right]
    var rows : array<array<string>>
    rows |> reserve(length(constructs()))
    for (c in constructs()) {
        let k = js?["kernels"]?[c.kernel]
        let native = time_of(k?["native"])
        let conv = k?["converted"]
        let alt = k?[c.spelling]
        let interp = time_of(conv?["interp"])
        let rust = k?["rust"]
        let rust_text = (rust?["status"] ?? "") == "ran" ? factor_text(time_of(rust?["interp"]), native) : (rust?["status"] ?? "n/a")
        let sites = js?["sites"]?[c.spelling]
        let site_text = has_key(js?["sites"], c.spelling) ? join([for (stem in HOT_FILES); "{sites?[stem] ?? 0}"], "/") : "n/a"
        rows |> emplace([c.name, "{c.kernel} ({c.spelling})",
            native > 0.0lf ? "{native * 1000000.0lf:.1f} us" : why(k?["native"]),
            interp > 0.0lf ? factor_text(interp, native) : why_lane(conv, "interp"),
            time_of(alt?["interp"]) > 0.0lf ? factor_text(interp, time_of(alt?["interp"])) : cost_error(conv, alt, "interp"),
            jit_cost_text(conv, alt, native),
            rust_text, site_text])
    }
    return render_md_table(headers, aligns, rows)
}

//! The whole-benchmark table of a capture: per benchmark the native seconds, the interpreter over
//! the scc and source layouts with each one's factor over native, and source over scc, the cost of
//! the source layout's late-bound calls.
def bench_table(js : JsonValue?) : string {
    let headers <- ["bench", "arg", "native s", "interp scc s", "scc x native", "interp source s", "source x native", "source / scc"]
    let aligns <- [for (h in headers); h == "bench" ? ColAlign.left : ColAlign.right]
    var rows : array<array<string>>
    rows |> reserve(length(BENCHES))
    for (b in BENCHES) {
        if (!has_key(js?["benches"], b.name)) {
            continue
        }
        let row = js?["benches"]?[b.name]
        let native = row?["native"] ?? 0.0lf
        let scc = row?["interp-scc"] ?? 0.0lf
        let source = row?["interp-source"] ?? 0.0lf
        rows |> emplace([b.name, row?["arg"] ?? "",
            native > 0.0lf ? "{native:.3f}" : why(row?["native"]),
            scc > 0.0lf ? "{scc:.2f}" : why(row?["interp-scc"]), factor_text(scc, native),
            source > 0.0lf ? "{source:.2f}" : why(row?["interp-source"]), factor_text(source, native), factor_text(source, scc)])
    }
    return render_md_table(headers, aligns, rows)
}

//! Both tables of a capture with the machine line above them.
def audit_text(js : JsonValue?) : string {
    var text = "{js?["cpu"] ?? "unknown CPU"}, {js?["samples"] ?? 0} samples per kernel lane, Rust {js?["rust_commit"] ?? "n/a"}\n\n{construct_table(js)}\n"
    if (has_key(js, "benches")) {
        text += "\n{bench_table(js)}\n"
    }
    return text
}

