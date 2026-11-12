options gen2
require dastest/testing_boost public
require strings
require daslib/strings_boost
require ../cir.das

//! The C-IR 0.2 macro fields (`docs/c-ir-spec.md` section 6.3) through the reader and the
//! canonical writer: `macros` after `types`, `fn_macro` after `macro` on an expression and before
//! `loc` on a statement, `macro_args` after `fn_macro`, each absent when empty.

// `#define SQ(x) ((x) * (x))` as a statement `SQ(v);` and as `SET(v);`'s do-while body: one TU in
// the canonical spelling
let UNIT = "\{\n \"cir\": \"0.2\",\n \"producer\": \"test\",\n \"target\": \{\n  \"triple\": \"x86_64-unknown-linux-gnu\",\n  \"int\": 32,\n  \"long\": 64,\n  \"llong\": 64,\n  \"ptr\": 64,\n  \"char_signed\": false\n \},\n \"tu\": \"m.c\",\n \"types\": [\n  \{\n   \"k\": \"int\",\n   \"w\": 32,\n   \"signed\": true,\n   \"spell\": \"int\"\n  \}\n ],\n \"macros\": [\n  \{\n   \"name\": \"SQ\",\n   \"params\": [\"x\"],\n   \"file\": \"m.c\",\n   \"line\": 1,\n   \"text\": \"#define SQ(x) ((x) * (x))\",\n   \"uses\": [2]\n  \},\n  \{\n   \"name\": \"SET\",\n   \"params\": [\"v\", \"w\"],\n   \"file\": \"m.c\",\n   \"line\": 2,\n   \"text\": \"#define SET(v, w) do \{ v = 1; \} while (0)\",\n   \"uses\": [1, 0]\n  \}\n ],\n \"decls\": [\n  \{\n   \"k\": \"func\",\n   \"name\": \"f\",\n   \"c_name\": \"f\",\n   \"t\": 0,\n   \"static\": false,\n   \"params\": [],\n   \"body\": \{\n    \"s\": \"compound\",\n    \"body\": [\n     \{\n      \"s\": \"expr\",\n      \"e\": \{\n       \"e\": \"bin\",\n       \"t\": 0,\n       \"op\": \"mul\",\n       \"a\": \{\n        \"e\": \"ref\",\n        \"t\": 0,\n        \"name\": \"v\",\n        \"macro_args\": [\n         \{\n          \"site\": 0,\n          \"k\": 0\n         \}\n        ]\n       \},\n       \"b\": \{\n        \"e\": \"ref\",\n        \"t\": 0,\n        \"name\": \"v\",\n        \"macro_args\": [\n         \{\n          \"site\": 0,\n          \"k\": 0\n         \}\n        ]\n       \},\n       \"fn_macro\": [\n        \{\n         \"m\": 0,\n         \"site\": 0,\n         \"args\": [\"v\"]\n        \}\n       ]\n      \},\n      \"loc\": \{\n       \"file\": \"m.c\",\n       \"line\": 3,\n       \"col\": 1\n      \}\n     \},\n     \{\n      \"s\": \"do\",\n      \"body\": null,\n      \"cond\": null,\n      \"fn_macro\": [\n       \{\n        \"m\": 1,\n        \"site\": 1,\n        \"args\": [\"v\", \"2 / 0\"]\n       \}\n      ],\n      \"loc\": \{\n       \"file\": \"m.c\",\n       \"line\": 4,\n       \"col\": 1\n      \}\n     \}\n    ],\n    \"loc\": \{\n     \"file\": \"m.c\",\n     \"line\": 3,\n     \"col\": 1\n    \}\n   \},\n   \"loc\": \{\n    \"file\": \"m.c\",\n    \"line\": 3,\n    \"col\": 1\n   \}\n  \}\n ]\n\}\n"

var tu : CirTu
var error : string

[test]
def test_cir_macros(t : T?) {
    unsafe {
        delete tu
    }
    tu <- read_cir(UNIT, error)
    t |> run("the reader takes the macros table, each whole expansion's marks and each copy's") @(t : T?) {
        t |> equal(error, "")
        t |> equal(length(tu.macros), 2)
        t |> equal(tu.macros[0].text, "#define SQ(x) ((x) * (x))")
        t |> equal(tu.macros[1].uses[1], 0)
        let fn_body = tu.decls[0].body
        let sq = fn_body.body[0].e
        t |> equal(sq.fn_macro[0].m, 0)
        t |> equal(sq.fn_macro[0].args[0], "v")
        t |> equal(sq.a.macro_args[0].k, 0)
        t |> equal(sq.b.macro_args[0].site, 0)
        t |> equal(fn_body.body[1].fn_macro[0].site, 1)
        t |> equal(fn_body.body[1].fn_macro[0].args[1], "2 / 0")
    }
    t |> run("the writer spells them back byte for byte, and a unit without them has none") @(t : T?) {
        t |> equal(write_cir(tu), UNIT)
        var plain <- read_cir(UNIT, error)
        delete plain.macros
        t |> equal(write_cir(plain) |> find("\"macros\""), -1)
        delete_tu(plain)
    }
    t |> run("a reader of 0.2 refuses 0.1") @(t : T?) {
        var old <- read_cir(replace(UNIT, "\"cir\": \"0.2\"", "\"cir\": \"0.1\""), error)
        t |> equal(error, "c-ir version 0.1, expected 0.2")
        delete_tu(old)
    }
}
