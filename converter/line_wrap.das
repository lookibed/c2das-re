options gen2

module line_wrap public

require strings
require daslib/strings_boost
require math

//! A converted module's long lines broken where the emitter marked an expression's structure:
//! after an argument's comma and after a binary operator. The emitter writes the mark into the
//! expression's text as it spells the node; this module only chooses which marks of a line too
//! long become line breaks, the shallowest parentheses first, filling each line, and drops the
//! rest. A mark breaks only inside a `(`, where das reads the next line as the same expression.

//! The widest line the layout leaves when a mark lets it break: the readability criterion's own bound.
let LINE_WIDTH = 160

//! The bytes the emitter writes where a line may break, in the order a line breaks at them within
//! one pair of parentheses: after a list's `,` (arguments, elements, fields), after `&&` and `||`,
//! after any other binary operator.
let LIST_MARK_BYTE = 28
let LOGIC_MARK_BYTE = 29
let OPERATOR_MARK_BYTE = 30

//! The marks as the text the emitter spells.
let LIST_MARK = to_char(LIST_MARK_BYTE)
let LOGIC_MARK = to_char(LOGIC_MARK_BYTE)
let OPERATOR_MARK = to_char(OPERATOR_MARK_BYTE)

//! The spaces a continuation line takes past its statement's indentation, and past a deeper break's line.
let private CONTINUATION = 8
let private DEEPER = 4

// a line's text with its usable marks: the byte offset of each and its rank, the parenthesis depth
// times three plus the mark's order (`LIST_MARK_BYTE` first), the lowest breaking first
struct private Piece {
    text : string
    marks : array<int2>
}

//! `text` with every mark dropped and each line longer than `LINE_WIDTH` broken at its marks.
[arch(at="ARCHITECTURE_EMITTER_TEXT.md#long-lines")]
def laid_out(text : string) : string {
    if (!has_mark(text)) {
        return text
    }
    let lines <- split(text, "\n")
    return join([for (l in lines); wrapped_line(l)], "\n")
}

// one line laid out: as it is past its marks when it fits, else filled from its shallowest marks
def private wrapped_line(line : string) : string {
    if (!has_mark(line)) {
        return line
    }
    let piece <- marked_piece(line)
    if (length(piece.text) <= LINE_WIDTH) {
        return piece.text
    }
    var out : array<string>
    fill(piece, indentation(piece.text) + CONTINUATION, out)
    return join(out, "\n")
}

// whether `text` holds a mark
def private has_mark(text : string) : bool => find(text, LIST_MARK) >= 0 || find(text, LOGIC_MARK) >= 0 || find(text, OPERATOR_MARK) >= 0

// the spaces that open `text`
def private indentation(text : string) : int {
    var n = 0
    for (ch in text) {
        break if (ch != ' ')
        n++
    }
    return n
}

// `line` without its marks, with the offset and rank of each mark inside a `(`; a
// mark inside a string or character literal, a comment, a `[` or a `{`, or outside every `(`, is
// dropped
def private marked_piece(line : string) : Piece {
    var piece : Piece
    var opens : array<int>
    var quote = 0
    var escaped = false
    var comment = false
    var last = 0
    piece.text = build_string() $(var w) {
        var at = 0
        for (ch in line) {
            if (ch >= LIST_MARK_BYTE && ch <= OPERATOR_MARK_BYTE) {
                if (quote == 0 && !comment && !empty(opens) && opens[length(opens) - 1] == '(') {
                    piece.marks |> push(int2(at, length(opens) * 3 + ch - LIST_MARK_BYTE))
                }
                continue
            }
            if (quote == 0 && ch == '/' && last == '/') {
                comment = true
            }
            last = ch
            if (quote != 0) {
                if (escaped) {
                    escaped = false
                } elif (ch == '\\') {
                    escaped = true
                } elif (ch == quote) {
                    quote = 0
                }
            } elif (ch == '"' || ch == '\'') {
                quote = ch
            } elif (ch == '(' || ch == '[' || ch == '{') {
                opens |> push(ch)
            } elif ((ch == ')' || ch == ']' || ch == '}') && !empty(opens)) {
                opens |> pop()
            }
            w |> write_char(ch)
            at++
        }
    }
    return <- piece
}

// `piece` into lines of `out`: whole when it fits or has no mark, else split at its marks of the
// lowest rank, the parts filling each line in turn, a continuation line indented to `cont`, and
// each line still too long split again at its own marks
def private fill(piece : Piece; cont : int; var out : array<string>) {
    if (length(piece.text) <= LINE_WIDTH || empty(piece.marks)) {
        out |> push(strip_right(piece.text))
        return
    }
    var rank = piece.marks[0].y
    for (m in piece.marks) {
        rank = min(rank, m.y)
    }
    var parts : array<Piece>
    var from = 0
    for (m in piece.marks) {
        if (m.y == rank) {
            parts |> emplace(part_of(piece, from, m.x))
            from = m.x
        }
    }
    parts |> emplace(part_of(piece, from, length(piece.text)))
    var current <- parts[0]
    for (k in range(1, length(parts))) {
        if (length(current.text) + length(parts[k].text) <= LINE_WIDTH) {
            var both <- joined(current, parts[k])
            delete current
            current <- both
        } else {
            fill(current, cont + DEEPER, out)
            var next <- continued(parts[k], cont)
            delete current
            current <- next
        }
    }
    fill(current, cont + DEEPER, out)
}

// the text of `piece` from byte `a` to byte `b` with the marks strictly inside
def private part_of(piece : Piece; a, b : int) : Piece {
    var part : Piece
    part.text = slice(piece.text, a, b)
    for (m in piece.marks) {
        if (m.x > a && m.x < b) {
            part.marks |> push(int2(m.x - a, m.y))
        }
    }
    return <- part
}

// `a` followed by `b`
def private joined(a, b : Piece) : Piece {
    var both : Piece
    both.text = a.text + b.text
    both.marks := a.marks
    both.marks |> reserve(length(a.marks) + length(b.marks))
    let shift = length(a.text)
    for (m in b.marks) {
        both.marks |> push(int2(m.x + shift, m.y))
    }
    return <- both
}

// `piece` opening a continuation line: its leading spaces replaced by `cont` of them
def private continued(piece : Piece; cont : int) : Piece {
    let skip = indentation(piece.text)
    var line : Piece
    line.text = repeat(" ", cont) + slice(piece.text, skip)
    line.marks |> reserve(length(piece.marks))
    for (m in piece.marks) {
        line.marks |> push(int2(m.x - skip + cont, m.y))
    }
    return <- line
}
