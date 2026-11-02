// research 03: llex.c:382 read_string's escape switch as the proposal spells it. A sketch, not
// compiled. Today: lua/work/lua/llex.das.inc:560-665, nine `goto label 1`, two `goto label 2`,
// three `goto label 3`, the three labels 645-663 each on a `c_label_end()`.
//
// The three labels are a cascade at the end of the `case '\\'` group: read_save falls into
// only_save falls into no_save, and no_save is `break`. Every goto to them is the last statement
// of its branch, so the gotos become one named choice and the cascade two guarded tails.

enum Escape {                    // the labels of read_string, in order of appearance
    read_save
    only_save
    no_save
}

    // inside `while (ls.current != del)`, the branch for `\\`:
    } elif (cur == '\\') {
        var c : int
        var escape = Escape.read_save
        save(ls, ls.current)
        next(ls)
        let e = ls.current
        if (e == 'a') {
            c = 7
        } elif (e == 'b') {
            c = 8
        } elif (e == 'f') {
            c = 12
        } elif (e == 'n') {
            c = 10
        } elif (e == 'r') {
            c = 13
        } elif (e == 't') {
            c = 9
        } elif (e == 'v') {
            c = 11
        } elif (e == 'x') {
            c = readhexaesc(ls)
        } elif (e == 'u') {
            utf8esc(ls)
            escape = Escape.no_save
        } elif (e == '\n' || e == '\r') {
            inclinenumber(ls)
            c = 10
            escape = Escape.only_save
        } elif (e == '\\' || e == '"' || e == '\'') {
            c = ls.current
        } elif (e == -1) {
            escape = Escape.no_save
        } elif (e == 'z') {
            ls.buff.n -= uint64(1)
            next(ls)
            while (lisspace(ls.current)) {
                if (currIsNewline(ls)) {
                    inclinenumber(ls)
                } else {
                    next(ls)
                }
            }
            escape = Escape.no_save
        } else {
            esccheck(ls, lisdigit(ls.current), "invalid escape sequence")
            c = readdecesc(ls)
            escape = Escape.only_save
        }
        if (escape == Escape.read_save) {              // read_save:
            next(ls)
        }
        if (escape != Escape.no_save) {                // only_save:
            ls.buff.n -= uint64(1)
            save(ls, c)
        }
                                                       // no_save: break
    } else {
