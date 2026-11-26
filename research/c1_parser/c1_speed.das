options gen2
options indenting = 4

// The probe's speed run: `-- <inputs.txt> <out.tsv> [rounds] [--only lex|rd|lr]`. The groups are
// each unit not named `cts_*`, and the `cts_*` units together (c-testsuite as a whole). Every
// round times, per group, the lexer alone, lexer + RD and lexer + LR, each with its tree built,
// the three interleaved and their order reversed every other round, so load on the machine hits
// all three alike; round 0 is a warm-up and is not recorded. Writes one row per group, mode and
// round (`group mode round tokens ms`) and prints median tokens/ms and the spread.

require daslib/fio
require strings
require daslib/strings_boost
require math
require daslib/algorithm
require c1_lexer
require c1_rd
require c1_lr

struct Unit {
    path : string
    text : string
}

struct Group {
    name : string
    units : array<Unit>
    tokens : int
}

def time_lex(g : Group) : float {
    let t0 = ref_time_ticks()
    for (u in g.units) {
        var src : Source
        lex(src, u.text, u.path)
    }
    return float(get_time_usec(t0)) / 1000.0
}

def time_rd(g : Group) : float {
    let t0 = ref_time_ticks()
    for (u in g.units) {
        var p : Rd
        lex(p.src, u.text, u.path)
        rd_parse(p)
    }
    return float(get_time_usec(t0)) / 1000.0
}

def time_lr(g : Group) : float {
    let t0 = ref_time_ticks()
    for (u in g.units) {
        var p : LrParser
        lex(p.lexer.src, u.text, u.path)
        lr_parse(p)
    }
    return float(get_time_usec(t0)) / 1000.0
}

def time_mode(g : Group; mode : string) : float {
    if (mode == "lex") {
        return time_lex(g)
    } elif (mode == "rd") {
        return time_rd(g)
    }
    return time_lr(g)
}

[export]
def main() {
    let args <- get_command_line_arguments()
    let at = find_index(args, "--")
    let out_path = args[at + 2]
    let rounds = at + 3 < length(args) && !starts_with(args[at + 3], "--") ? to_int(args[at + 3]) : 5
    let only_at = find_index(args, "--only")
    var modes <- ["lex", "rd", "lr"]
    if (only_at >= 0) {
        modes <- [args[only_at + 1]]
    }
    var groups : array<Group>
    var cts = Group(name = "c-testsuite")
    for (line in split(fread(args[at + 1]), "\n")) {
        if (empty(line)) {
            continue
        }
        let parts <- split(line, "\t")
        var u = Unit(path = parts[1], text = fread(parts[1]))
        var src : Source
        lex(src, u.text, u.path)
        if (!empty(src.err)) {
            continue
        }
        // a unit a parser refuses is left out of every group: only the accepted ones are timed
        var r : Rd
        lex(r.src, u.text, u.path)
        rd_parse(r)
        if (r.failed) {
            continue
        }
        let ntok = length(src.toks)
        if (starts_with(parts[0], "cts_")) {
            cts.units |> push(u)
            cts.tokens += ntok
        } else {
            var g = Group(name = parts[0], tokens = ntok)
            g.units |> push(u)
            groups |> emplace(g)
        }
    }
    if (length(cts.units) > 0) {
        groups |> emplace(cts)
    }
    var rows : array<string>
    var samples : table<string; array<float>>
    for (round in range(rounds + 1)) {
        for (g in groups) {
            var order <- clone_to_move(modes)
            if (round % 2 == 1) {
                reverse(order)
            }
            for (m in order) {
                let ms = time_mode(g, m)
                if (round > 0) {
                    rows |> push("{g.name}\t{m}\t{round}\t{g.tokens}\t{ms}")
                    samples["{g.name}/{m}"] |> push(ms)
                }
            }
        }
    }
    fwrite(out_path, join(rows, "\n") + "\n")
    for (g in groups) {
        for (m in modes) {
            var s <- clone_to_move(samples["{g.name}/{m}"])
            sort(s)
            let med = s[length(s) / 2]
            print("{g.name}\t{m}\t{g.tokens} tokens\tmedian {med} ms\t{float(g.tokens) / med} tok/ms\tspread {s[0]}..{s[length(s) - 1]} ms\n")
        }
    }
}
