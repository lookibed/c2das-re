options gen2
options indenting = 4

// The probe's memory run: `-- <file.i>...`. Per file, the lexer, RD and LR (each over its own
// fresh lex of the file) measured on the context heap: the allocations a step makes (rule 6
// wants a count that does not grow with the tokens), the bytes it allocates in total, and the
// bytes still live when it is done (the token array, or the token array and the tree).

require daslib/fio
require strings
require c1_lexer
require c1_rd
require c1_lr

struct Mark {
    count : uint64
    total : uint64
    live : uint64
    strings : uint64
}

def mark : Mark {
    let st = heap_allocation_stats()
    let ss = string_heap_allocation_stats()
    return Mark(count = heap_allocation_count(), total = st.x, live = heap_bytes_allocated(), strings = ss.x)
}

def report(what : string; a, b : Mark; ntok : int) {
    let count = b.count - a.count
    print("  {what}: {count} allocations ({float(count) / float(ntok)} per token), {(b.total - a.total) / 1024ul} KiB allocated, {(int64(b.live) - int64(a.live)) / 1024l} KiB live after, {(b.strings - a.strings) / 1024ul} KiB of strings\n")
}

[export]
def main() {
    let args <- get_command_line_arguments()
    let at = find_index(args, "--")
    for (i in range(at + 1, length(args))) {
        let path = args[i]
        let text = fread(path)
        print("{base_name(path)}\n")
        var src : Source
        let m0 = mark()
        lex(src, text, path)
        let m1 = mark()
        let ntok = length(src.toks)
        report("lexer", m0, m1, ntok)
        var r : Rd
        lex(r.src, text, path)
        let m2 = mark()
        rd_parse(r)
        let m3 = mark()
        report("RD parse ({length(r.ast.nodes)} nodes)", m2, m3, ntok)
        var l : LrParser
        lex(l.lexer.src, text, path)
        let m4 = mark()
        lr_parse(l)
        let m5 = mark()
        report("LR parse ({length(l.lexer.ast.nodes)} nodes)", m4, m5, ntok)
    }
}
