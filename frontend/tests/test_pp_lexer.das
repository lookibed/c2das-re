options gen2
require dastest/testing_boost public
require strings
require daslib/strings_boost
require ../pp_lexer.das

//! `frontend/pp_lexer.das`: C11 preprocessing tokens over a byte view, placed in the original file
//! through line splices, identifiers interned, nothing allocated per token.

// the class letter of a token kind: I identifier, N pp-number, C character constant, S string
// literal, H header name, O other, P punctuator
def private class_of(kind : int) : string {
    if (kind == int(PpTok.IDENTIFIER)) {
        return "I"
    } elif (kind == int(PpTok.PP_NUMBER)) {
        return "N"
    } elif (kind == int(PpTok.CHAR_CONSTANT)) {
        return "C"
    } elif (kind == int(PpTok.STRING_LITERAL)) {
        return "S"
    } elif (kind == int(PpTok.HEADER_NAME)) {
        return "H"
    } elif (kind == int(PpTok.OTHER)) {
        return "O"
    }
    return "P"
}

// the tokens of `bytes`, each `<class>:<spelling>` and a blank between them; with `flags`, a token
// at the start of a line gets `^` in front and one after skipped text `_`
def private lexed_bytes(var bytes : array<uint8>; flags : bool = false) : string {
    var lx : PpLexer
    pp_open(lx, bytes, 1)
    var parts : array<string>
    while (pp_next(lx)) {
        let mark = flags ? "{lx.tok.at_bol ? "^" : ""}{lx.tok.has_space ? "_" : ""}" : ""
        parts |> push("{mark}{class_of(lx.tok.kind)}:{pp_spelling(lx)}")
    }
    return join(parts, " ")
}

// `lexed_bytes` over the bytes of `text`
def private lexed(text : string; flags : bool = false) : string {
    var bytes <- [for (c in text); uint8(c)]
    return lexed_bytes(bytes, flags)
}

// every token of `text` placed in the file, `<spelling>@<offset>+<len>:<line>:<col>`
def private placed_tokens(text : string) : string {
    var lx : PpLexer
    pp_open_text(lx, text, 1)
    var parts : array<string>
    while (pp_next(lx)) {
        parts |> push("{pp_spelling(lx)}@{lx.tok.offset}+{lx.tok.len}:{lx.tok.line}:{lx.tok.col}")
    }
    return join(parts, " ")
}

[test(description = "every token class of C11 6.4 lexes as clang lexes it: identifiers, pp-numbers, character constants, string literals, punctuators and other characters")]
def test_token_classes(t : T?) {
    t |> run("identifiers take letters, digits, `_` and `$`") @(t : T?) {
        t |> equal(lexed("a _b c9 $x a$b"), "I:a I:_b I:c9 I:$x I:a$b")
        t |> equal(lexed("x\\U0001F600y"), "I:x\\U0001F600y")
    }
    t |> run("a pp-number continues with digits, letters, dots and an exponent sign (6.4.8)") @(t : T?) {
        t |> equal(lexed("1..2 1e-5 0x1.p-3 .5e 12abc 1e+ 1p- 1.e+5 0x1P+4f"), "N:1..2 N:1e-5 N:0x1.p-3 N:.5e N:12abc N:1e+ N:1p- N:1.e+5 N:0x1P+4f")
        t |> equal(lexed("1-2 1+e 1x-2"), "N:1 P:- N:2 N:1 P:+ I:e N:1x P:- N:2")
        t |> equal(lexed("1_000 0x_1"), "N:1_000 N:0x_1")
    }
    t |> run("a pp-number continues with UTF-8 letters and UCNs, not with `$`, as clang lexes it") @(t : T?) {
        t |> equal(lexed("1\u00e9 1\\u00e9 1$"), "N:1\u00e9 N:1\\u00e9 N:1 I:$")
        t |> equal(lexed("1\\U0001F600"), "N:1\\U0001F600")
    }
    t |> run("character constants and string literals take the C11 prefixes; u8 has no character constant") @(t : T?) {
        t |> equal(lexed("'a' L'b' u'c' U'd' u8'e'"), "C:'a' C:L'b' C:u'c' C:U'd' I:u8 C:'e'")
        t |> equal(lexed("\"s\" u8\"s\" u\"s\" U\"s\" L\"s\""), "S:\"s\" S:u8\"s\" S:u\"s\" S:U\"s\" S:L\"s\"")
    }
    t |> run("any escape is one character of a literal, so a quote after a backslash does not end it") @(t : T?) {
        t |> equal(lexed("\"a\\\"b\" '\\'' \"\\e\" '\\%'"), "S:\"a\\\"b\" C:'\\'' S:\"\\e\" C:'\\%'")
    }
    t |> run("an unterminated literal is one OTHER token to the end of its line, as clang lexes it") @(t : T?) {
        t |> equal(lexed("\"abc\nx 'y\nz"), "O:\"abc I:x O:'y I:z")
        t |> equal(lexed("L\"ab\nu8\"cd\nU'e\nx \"a\\\"b\ny"), "O:L\"ab O:u8\"cd O:U'e I:x O:\"a\\\"b I:y")
        t |> equal(lexed("'a\\'b\ny"), "O:'a\\'b I:y")
    }
    t |> run("an empty character constant is one OTHER token, as clang lexes it") @(t : T?) {
        t |> equal(lexed("'' x L''"), "O:'' I:x O:L''")
    }
    t |> run("an unterminated literal ending in a backslash at the end of the file is one OTHER token, as clang lexes it") @(t : T?) {
        t |> equal(lexed("x \"ab\\"), "I:x O:\"ab\\")
        t |> equal(lexed("x 'a\\"), "I:x O:'a\\")
    }
    t |> run("every punctuator of 6.4.6, the longest first, `#` and `##` among them") @(t : T?) {
        let puncts = "[ ] ( ) \{ \} . -> ++ -- & * + - ~ ! / % << >> < > <= >= == != ^ | && || ? : ; ... = *= /= %= += -= <<= >>= &= ^= |= , # ## ::"
        let expected <- [for (p in split(puncts, " ")); "P:{p}"]
        t |> equal(lexed(puncts), join(expected, " "))
        t |> equal(lexed("a...b ..c x->y a+++b"), "I:a P:... I:b P:. P:. I:c I:x P:-> I:y I:a P:++ P:+ I:b")
    }
    t |> run("`::` is one punctuator, as clang lexes it under gnu17; a third colon is a `:` of its own") @(t : T?) {
        t |> equal(lexed("a::b ::: ::> <::"), "I:a P::: I:b P::: P:: P::: P:> P:<: P::")
        var lx : PpLexer
        pp_open_text(lx, "::", 1)
        t |> success(pp_next(lx))
        t |> equal(lx.tok.kind, int(PpTok.COLONCOLON))
    }
    t |> run("a digraph has the kind of the punctuator it spells and keeps its spelling") @(t : T?) {
        t |> equal(lexed("<: :> <% %> %: %:%: %:%"), "P:<: P::> P:<% P:%> P:%: P:%:%: P:%: P:%")
        var lx : PpLexer
        pp_open_text(lx, "<: :> <% %> %: %:%:", 1)
        var kinds : array<int>
        while (pp_next(lx)) {
            kinds |> push(lx.tok.kind)
        }
        t |> equal(kinds, [int(PpTok.LBRACKET), int(PpTok.RBRACKET), int(PpTok.LBRACE), int(PpTok.RBRACE), int(PpTok.HASH), int(PpTok.HASHHASH)])
    }
    t |> run("any other character is one OTHER token (6.4p3): `@`, a backquote, a stray backslash, a code point no identifier takes") @(t : T?) {
        t |> equal(lexed("@ ` \\ a\\b \u00a0"), "O:@ O:` O:\\ I:a O:\\ I:b O:\u00a0")
    }
}

[test(description = "a raw string literal is one token with its prefixes, as the pinned clang lexes it under gnu17; a malformed delimiter or a missing `)delim\"` makes it one OTHER token")]
def test_raw_strings(t : T?) {
    t |> run("a quote inside the parentheses does not end it") @(t : T?) {
        t |> equal(lexed("x R\"(a\"b)\" y"), "I:x S:R\"(a\"b)\" I:y")
    }
    t |> run("every prefix, a delimiter of up to 16 characters, and a newline inside") @(t : T?) {
        t |> equal(lexed("LR\"ab(x)ab\" u8R\"q()q\" uR\"()\" UR\"$(a\nb)$\" R\"0123456789abcdef(z)0123456789abcdef\""),
                   "S:LR\"ab(x)ab\" S:u8R\"q()q\" S:uR\"()\" S:UR\"$(a\nb)$\" S:R\"0123456789abcdef(z)0123456789abcdef\"")
        t |> equal(placed_tokens("R\"(a\nb)\" c"), "R\"(a\nb)\"@0+8:1:1 c@9+1:2:5")
    }
    t |> run("only `)delim\"` ends it: a `)` with another delimiter or no quote is part of it") @(t : T?) {
        t |> equal(lexed("R\"a()b\")\")a\" x"), "S:R\"a()b\")\")a\" I:x")
    }
    t |> run("without the `R\"` right after the prefix it is an identifier and a string") @(t : T?) {
        t |> equal(lexed("Rx\"a\" r\"(a)\" u8 R \"(a)\""), "I:Rx S:\"a\" I:r S:\"(a)\" I:u8 I:R S:\"(a)\"")
    }
    t |> run("a delimiter past 16 characters or holding a character no delimiter takes is OTHER to the next quote") @(t : T?) {
        t |> equal(lexed("R\"0123456789abcdefg(z)0123456789abcdefg\" k"), "O:R\"0123456789abcdefg(z)0123456789abcdefg\" I:k")
        t |> equal(lexed("R\"x\" k R\"a b(c)a b\""), "O:R\"x\" I:k O:R\"a b(c)a b\"")
        t |> equal(lexed("R\"x y"), "O:R\"x y")
        t |> equal(lexed("R\"\\(a)\\\" x"), "O:R\"\\(a)\\\" I:x")
    }
    t |> run("a raw string no `)delim\"` closes is OTHER to the end of the file") @(t : T?) {
        t |> equal(lexed("a R\"(abc\nd"), "I:a O:R\"(abc\nd")
        t |> equal(lexed("R\"ab(c)a\""), "O:R\"ab(c)a\"")
    }
}

[test(description = "a UCN is part of an identifier and of a literal; an incomplete one is a backslash token and an identifier")]
def test_ucn(t : T?) {
    t |> equal(lexed("\\u00e9x x\\u00e9 \\U0001F600 \\u12 \"\\u00e9\" '\\U0001F600'"), "I:\\u00e9x I:x\\u00e9 I:\\U0001F600 O:\\ I:u12 S:\"\\u00e9\" C:'\\U0001F600'")
    t |> equal(lexed("\u00e9t\u00e9 \u0301x x\u0301"), "I:\u00e9t\u00e9 O:\u0301 I:x I:x\u0301")
}

[test(description = "comments are skipped as one space: `has_space` follows them, `at_bol` only a newline outside them (C11 6.10p2)")]
def test_comments_and_flags(t : T?) {
    t |> run("the first token is at the start of a line; a token after a blank or a comment has a space") @(t : T?) {
        t |> equal(lexed("a b/**/c//x\nd", true), "^I:a _I:b _I:c ^_I:d")
    }
    t |> run("a newline inside a block comment does not start a line: `x /*\\n*/ # y` is no directive") @(t : T?) {
        t |> equal(lexed("x /* a\n b */ # y", true), "^I:x _P:# _I:y")
    }
    t |> run("a block comment opening after a newline leaves the token after it at the start of its line") @(t : T?) {
        t |> equal(lexed("x\n/* a\n*/ # y", true), "^I:x ^_P:# _I:y")
        t |> equal(lexed("x\n/**/#", true), "^I:x ^_P:#")
    }
    t |> run("a `//` comment ends at the newline, which starts the next line") @(t : T?) {
        t |> equal(lexed("a // b /* c\n# d", true), "^I:a ^_P:# _I:d")
    }
    t |> run("a `*` inside a block comment does not end it; `/*/` opens one") @(t : T?) {
        t |> equal(lexed("a /* * ** b */ c /*/ d */ e"), "I:a I:c I:e")
    }
    t |> run("an unterminated block comment ends the file with a diagnostic at its `/*`, and the next call adds none") @(t : T?) {
        var lx : PpLexer
        pp_open_text(lx, "a /* b", 7)
        t |> success(pp_next(lx))
        t |> success(!pp_next(lx))
        t |> equal(lx.tok.kind, int(PpTok.EOF))
        t |> equal(length(lx.diags), 1)
        let d = lx.diags[0]
        t |> equal("{d.file} {d.offset} {d.line}:{d.col} {d.what}", "7 2 1:3 unterminated /* comment")
        t |> success(!pp_next(lx))
        t |> equal(length(lx.diags), 1)
    }
    t |> run("the unterminated comment's diagnostic is placed in the file through a splice before it") @(t : T?) {
        var lx : PpLexer
        pp_open_text(lx, "a\\\nb /* c", 1)
        while (pp_next(lx)) {
            pass
        }
        t |> equal(length(lx.diags), 1)
        let d = lx.diags[0]
        t |> equal("{d.offset} {d.line}:{d.col}", "5 2:3")
    }
    t |> run("a NUL byte is whitespace, as clang takes it") @(t : T?) {
        var bytes <- [uint8('a'), 0u8, uint8('b')]
        t |> equal(lexed_bytes(bytes, true), "^I:a _I:b")
    }
}

[test(description = "line splices are removed before lexing, and every token is placed in the original file through them")]
def test_splices(t : T?) {
    t |> run("a token split by a splice is one token at its original offset and line, its length spanning the splice") @(t : T?) {
        t |> equal(placed_tokens("in\\\nt x"), "int@0+5:1:1 x@6+1:2:3")
    }
    t |> run("a token after a splice on its own line is placed on the line after the splice") @(t : T?) {
        t |> equal(placed_tokens("a \\\n  b\nc"), "a@0+1:1:1 b@6+1:2:3 c@8+1:3:1")
        t |> equal(placed_tokens("a\\\n\\\nb c"), "ab@0+6:1:1 c@7+1:3:3")
    }
    t |> run("a token right after a splice starts at the splice's backslash, as clang places it") @(t : T?) {
        t |> equal(placed_tokens("a \\\nb\n\\\n\\\nc s\\\n= 1"), "a@0+1:1:1 b@2+3:1:3 c@6+5:3:1 s@12+1:5:3 =@13+3:5:4 1@17+1:6:3")
    }
    t |> run("a splice ending in `\\r\\n` or with blanks before the newline is a splice, as clang and gcc take it") @(t : T?) {
        t |> equal(placed_tokens("a\\\r\nb c"), "ab@0+5:1:1 c@6+1:2:3")
        t |> equal(placed_tokens("a\\  \nb"), "ab@0+6:1:1")
        t |> equal(lexed("a\\\t\nb c\\\f\nd e\\\v\nf"), "I:ab I:cd I:ef")
    }
    t |> run("a lone `\\r` is a newline, and a backslash before one is a splice, as clang takes them") @(t : T?) {
        t |> equal(placed_tokens("a\rb\\\rc d"), "a@0+1:1:1 bc@2+4:2:1 d@7+1:3:3")
        t |> equal(lexed("a\rb\r\n# c", true), "^I:a ^_I:b ^_P:# _I:c")
        t |> equal(lexed("\"ab\rc"), "O:\"ab I:c")
        t |> equal(placed_tokens("a\\\r"), "a@0+1:1:1")
    }
    t |> run("a splice inside a literal and a comment joins it; one inside `//` continues the comment") @(t : T?) {
        t |> equal(lexed("\"a\\\nb\" /\\\n* c *\\\n/ d // e\\\nf\ng"), "S:\"ab\" I:d I:g")
    }
    t |> run("a backslash at the end of the file, with or without a newline, is no splice") @(t : T?) {
        t |> equal(placed_tokens("a\\"), "a@0+1:1:1 \\@1+1:1:2")
        t |> equal(placed_tokens("a\\\n"), "a@0+1:1:1")
        t |> equal(placed_tokens("a \\ b"), "a@0+1:1:1 \\@2+1:1:3 b@4+1:1:5")
    }
    t |> run("a splice does not start a line or leave a space") @(t : T?) {
        t |> equal(lexed("a\\\n+\\\n+ b", true), "^I:a P:++ _I:b")
    }
}

[test(description = "the file's own bytes are lexed in place when it holds no splice, and copied once into a working buffer when it does")]
def test_no_copy(t : T?) {
    t |> run("no splice: the scanner reads the array the caller handed over") @(t : T?) {
        var bytes : array<uint8>
        bytes |> reserve(8)
        for (c in "int x;") {
            bytes |> push(uint8(c))
        }
        let before = unsafe(addr(bytes[0]))
        var lx : PpLexer
        pp_open(lx, bytes, 1)
        t |> equal(intptr(lx.flex.data), intptr(before))
        t |> success(empty(lx.splices))
    }
    t |> run("a splice: the scanner reads a working buffer and the table holds one entry per splice") @(t : T?) {
        var bytes : array<uint8>
        bytes |> reserve(8)
        for (c in "a\\\nb\\\nc") {
            bytes |> push(uint8(c))
        }
        let before = unsafe(addr(bytes[0]))
        var lx : PpLexer
        pp_open(lx, bytes, 1)
        t |> success(intptr(lx.flex.data) != intptr(before))
        t |> equal(length(lx.splices), 2)
    }
    t |> run("a backslash that starts no splice and a `\\r\\n` leave the bytes in place; a lone `\\r` copies them") @(t : T?) {
        for (text, kept in fixed_array("a\\b c", "a\r\nb", "a\rb"), fixed_array(true, true, false)) {
            var bytes : array<uint8>
            bytes |> reserve(8)
            for (c in text) {
                bytes |> push(uint8(c))
            }
            let before = unsafe(addr(bytes[0]))
            var lx : PpLexer
            pp_open(lx, bytes, 1)
            t |> equal(intptr(lx.flex.data) == intptr(before), kept, text)
        }
    }
    t |> run("`pp_read_file` leaves the spare byte: `pp_open` takes its array without moving it") @(t : T?) {
        var bytes : array<uint8>
        t |> success(pp_read_file("frontend/include/stdio.h", bytes))
        let before = unsafe(addr(bytes[0]))
        var lx : PpLexer
        pp_open(lx, bytes, 1)
        t |> equal(intptr(lx.flex.data), intptr(before))
    }
    t |> run("`pp_read_file` answers false for a file it cannot open") @(t : T?) {
        var bytes : array<uint8>
        t |> success(!pp_read_file("frontend/include/no_such_header.h", bytes))
    }
}

[test(description = "a UTF-8 byte order mark is skipped: the first token keeps its byte offset and column, has no space and starts its line")]
def test_bom(t : T?) {
    var lx : PpLexer
    pp_open_text(lx, "\xef\xbb\xbfint a;", 1)
    t |> success(pp_next(lx))
    t |> equal(pp_spelling(lx), "int")
    t |> equal(lx.tok.offset, 3)
    t |> equal(lx.tok.col, 4)
    t |> success(lx.tok.at_bol && !lx.tok.has_space)
    t |> equal(lexed("a \xef\xbb\xbf"), "I:a I:\xef\xbb\xbf")
    t |> equal(lexed("\xef\xbc\xbfx \xef\xbb\xbex"), "I:\xef\xbc\xbfx I:\xef\xbb\xbex")
}

[test(description = "a byte that starts no UTF-8 character is an OTHER token and a diagnostic at its original offset")]
def test_invalid_utf8(t : T?) {
    var lx : PpLexer
    pp_open_text(lx, "a\\\nb \xff c", 3)
    var kinds : array<int>
    while (pp_next(lx)) {
        kinds |> push(lx.tok.kind)
    }
    t |> equal(kinds, [int(PpTok.IDENTIFIER), int(PpTok.OTHER), int(PpTok.IDENTIFIER)])
    t |> equal(length(lx.diags), 1)
    let d = lx.diags[0]
    t |> equal("{d.file} {d.offset} {d.line}:{d.col} {d.what}", "3 5 2:3 invalid UTF-8: byte 255")
    t |> equal(lexed("\xc3\xa9 \xc3 \xe2\x82"), "I:\xc3\xa9 O:\xc3 O:\xe2 O:\x82")
}

// the diagnostics of `text`, each `<offset>:<what>`
def private diagnosed(text : string) : string {
    var lx : PpLexer
    pp_open_text(lx, text, 1)
    while (pp_next(lx)) {
        pass
    }
    let parts <- [for (d in lx.diags); "{d.offset}:{d.what}"]
    return join(parts, " ")
}

[test(description = "a surrogate, an overlong form and a code point past U+10FFFF, which the generator's `.` admits, are a byte each with a diagnostic, as clang splits them")]
def test_invalid_utf8_sequences(t : T?) {
    t |> run("a surrogate (ED A0..BF)") @(t : T?) {
        t |> equal(lexed("a \xed\xa0\x80 b"), "I:a O:\xed O:\xa0 O:\x80 I:b")
        t |> equal(placed_tokens("\xed\xa0\x80 b"), "\xed@0+1:1:1 \xa0@1+1:1:2 \x80@2+1:1:3 b@4+1:1:5")
        t |> equal(diagnosed("a \xed\xa0\x80"), "2:invalid UTF-8: byte 237 3:invalid UTF-8: byte 160 4:invalid UTF-8: byte 128")
    }
    t |> run("an overlong form (E0 80..9F, F0 80..8F)") @(t : T?) {
        t |> equal(lexed("\xe0\x9f\xbf \xf0\x8f\xbf\xbf"), "O:\xe0 O:\x9f O:\xbf O:\xf0 O:\x8f O:\xbf O:\xbf")
        t |> equal(diagnosed("\xe0\x80\x80"), "0:invalid UTF-8: byte 224 1:invalid UTF-8: byte 128 2:invalid UTF-8: byte 128")
    }
    t |> run("past U+10FFFF (F4 90..BF)") @(t : T?) {
        t |> equal(lexed("\xf4\x90\x80\x80"), "O:\xf4 O:\x90 O:\x80 O:\x80")
    }
    t |> run("the valid neighbours stay one OTHER token with no diagnostic") @(t : T?) {
        t |> equal(lexed("\xf4\x8f\xbf\xbf \xe3\x80\x80 \xc2\xa0"), "O:\xf4\x8f\xbf\xbf O:\xe3\x80\x80 O:\xc2\xa0")
        t |> equal(diagnosed("\xf4\x8f\xbf\xbf \xe3\x80\x80 \xed\x9f\xbf \xe0\xa0\x80 \xf0\x90\x80\x80"), "")
    }
}

[test(description = "a header name is one token only where the caller asks for one, and the lexer returns to pp-tokens after it")]
def test_header_name(t : T?) {
    var lx : PpLexer
    pp_open_text(lx, "<stdio.h> <a.h> \"a\\b.h\" <x", 1)
    t |> success(pp_next_header_name(lx))
    t |> equal("{class_of(lx.tok.kind)}:{pp_spelling(lx)}", "H:<stdio.h>")
    t |> success(pp_next(lx))
    t |> equal("{class_of(lx.tok.kind)}:{pp_spelling(lx)}", "P:<")
    while (pp_next(lx) && !pp_spelling_is(lx, ">")) {
        t |> success(lx.tok.kind != int(PpTok.HEADER_NAME))
    }
    t |> success(pp_next_header_name(lx))
    t |> equal("{class_of(lx.tok.kind)}:{pp_spelling(lx)}", "H:\"a\\b.h\"")
    t |> success(pp_next_header_name(lx))
    t |> equal("{class_of(lx.tok.kind)}:{pp_spelling(lx)}", "P:<")
    pp_open_text(lx, "/* c */ <a.h> /* d\n */ \"b.h\"", 1)
    t |> success(pp_next_header_name(lx))
    t |> equal("{class_of(lx.tok.kind)}:{pp_spelling(lx)}", "H:<a.h>")
    t |> success(pp_next_header_name(lx))
    t |> equal("{class_of(lx.tok.kind)}:{pp_spelling(lx)}", "H:\"b.h\"")
}

[test(description = "an identifier's symbol is the same for every spelling of its name, in one file and across a reopen, which changes the file id")]
def test_interning(t : T?) {
    var lx : PpLexer
    pp_open_text(lx, "foo bar foo 1 foo", 1)
    var syms : array<int>
    while (pp_next(lx)) {
        syms |> push(lx.tok.sym)
    }
    t |> equal(syms[0], syms[2])
    t |> equal(syms[0], syms[4])
    t |> success(syms[0] != syms[1])
    t |> equal(syms[3], -1)
    t |> equal(pp_symbol_text(lx, syms[1]), "bar")
    pp_open_text(lx, "bar baz", 2)
    t |> success(pp_next(lx))
    t |> equal(lx.tok.file, 2)
    t |> equal(lx.tok.sym, syms[1])
    t |> equal(lx.tok.line, 1)
    t |> success(pp_next(lx))
    t |> success(lx.tok.sym != syms[0] && lx.tok.sym != syms[1])
    t |> equal(pp_symbol_text(lx, syms[0]), "foo")
    t |> success(!pp_next(lx))
    t |> equal(lx.tok.sym, -1)
}

[test(description = "a reopen starts the file afresh: the token is the end with no symbol, and a spliced file's tokens are placed as a new lexer places them")]
def test_reopen(t : T?) {
    let second = "x\\\ny z\\\n= 1"
    var lx : PpLexer
    pp_open_text(lx, "a\\\nb c\\\nd \\\n e", 1)
    for (_ in range(3)) {
        t |> success(pp_next(lx))
    }
    t |> equal("{pp_spelling(lx)} {lx.applied}", "e 3")
    pp_open_text(lx, second, 2)
    t |> equal(lx.tok.kind, int(PpTok.EOF))
    t |> equal(lx.tok.sym, -1)
    var parts : array<string>
    while (pp_next(lx)) {
        parts |> push("{pp_spelling(lx)}@{lx.tok.offset}+{lx.tok.len}:{lx.tok.line}:{lx.tok.col}")
    }
    t |> equal(join(parts, " "), placed_tokens(second))
}

// the tokens of the file at `path` lexed after `lx` already met every name in it, and the heap and
// string-heap allocations the scan made
def private allocations_of_scan(var lx : PpLexer; path : string; file : int) : int3 {
    var bytes : array<uint8>
    pp_read_file(path, bytes)
    pp_open(lx, bytes, file)
    let heap = int(heap_allocation_count())
    let strings = int(string_heap_allocation_count())
    var count = 0
    while (pp_next(lx)) {
        count++
    }
    return int3(count, int(heap_allocation_count()) - heap, int(string_heap_allocation_count()) - strings)
}

[test(description = "lexing a real unit allocates nothing per token: no string at all, and no heap block once every name is interned")]
def test_no_allocation(t : T?) {
    let path = "frontend/include/stdio.h"
    var lx : PpLexer
    let first = allocations_of_scan(lx, path, 1)
    t |> success(first.x > 300, "{path}: {first.x} tokens")
    t |> equal(first.z, 0, "string allocations, first pass")
    t |> success(first.y <= symbol_count(lx.flex.syms), "heap allocations {first.y} over {symbol_count(lx.flex.syms)} distinct names")
    let again = allocations_of_scan(lx, path, 2)
    t |> equal(again.x, first.x)
    t |> equal(again.y, 0, "heap allocations, every name known")
    t |> equal(again.z, 0, "string allocations, every name known")
}

[test(description = "the current token's range in the working buffer and the buffer's first byte: a token past a splice is read there with the splice removed")]
def test_token_range(t : T?) {
    var lx : PpLexer
    pp_open_text(lx, "ab c\\\nd e", 0)
    var seen : array<string>
    while (pp_next(lx)) {
        let r = pp_token_range(lx)
        let data = pp_buffer_data(lx)
        seen |> push(build_string() $(var out) {
            out |> write("{r.start}+{r.len}:")
            for (i in range(r.start, r.start + r.len)) {
                out |> write_char(int(unsafe(data[i])))
            }
        })
    }
    t |> equal(join(seen, " "), "0+2:ab 3+2:cd 6+1:e")
}
