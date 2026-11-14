options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require ../converter/tiers.das

//! Alignment-only packed records as plain structs (owner ruling 38 addendum 23, F51 lifted for them;
//! docs/probe-findings.md F108): a struct das aligns past clang's alignment of 1 (Doom's `mapthing_t`,
//! five `int16`; `filelump_t`, two `int` and a name) read and written where C memory holds it at an
//! odd address. An array of each lies 1, 3 and 5 bytes past a `malloc`'s start; its elements are
//! stored, copied element by element by struct assignment, cleared with `memset` and copied back
//! with `memcpy`, and read in loops field by field. Under the interpreter, the JIT, the JIT-linked
//! executable and the AOT host every value reads back as an aligned build computes it: x86-64
//! loads unaligned, and no tier's code assumes the alignment das gives the type.

let SOURCE = "options gen2\nrequire crt\n\nstruct Thing \{\n    x : int16\n    y : int16\n    angle : int16\n    kind : int16\n    flags : int16\n\}\n\nstruct Lump \{\n    filepos : int\n    size : int\n    name : uint8[8]\n\}\n\nlet N = 1000\n\ndef fill_thing(i : int) : Thing \{\n    return Thing(x = int16(i * 3 - 700), y = int16(i * 7 + 11), angle = int16(i % 360), kind = int16(i & 63), flags = int16(-i))\n\}\n\ndef fill_lump(i : int) : Lump \{\n    var l = Lump(filepos = i * 100003 - 5, size = i * 17 + 1)\n    for (k in range(8)) \{\n        l.name[k] = uint8((i + k * 31) & 255)\n    \}\n    return l\n\}\n\ndef thing_sum(t : Thing) : int64 => int64(t.x) * 3l + int64(t.y) * 5l + int64(t.angle) * 7l + int64(t.kind) * 11l + int64(t.flags) * 13l\n\ndef lump_sum(l : Lump) : int64 \{\n    var s = int64(l.filepos) * 3l + int64(l.size) * 5l\n    for (k in range(8)) \{\n        s += int64(l.name[k]) * int64(k + 1)\n    \}\n    return s\n\}\n\n[export]\ndef main : int \{\n    var bad = 0\n    var total = 0l\n    unsafe \{\n        let bytes = reinterpret<uint8?>(crt::malloc(uint64(N * 64 + 64)))\n        // arrays of the records at odd addresses: 1 and 3 bytes past an allocation's start\n        var things = reinterpret<Thing?>(bytes + 1)\n        var copies = reinterpret<Thing?>(bytes + N * 10 + 3)\n        for (i in range(N)) \{\n            things[i] = fill_thing(i)\n        \}\n        // struct assignment element by element, then a whole-block memcpy back over the source\n        for (i in range(N)) \{\n            copies[i] = things[i]\n        \}\n        crt::memset(things, 0, uint64(N * 10))\n        crt::memcpy(things, copies, uint64(N * 10))\n        for (i in range(N)) \{\n            let want = fill_thing(i)\n            var got = things[i]\n            if (got.x != want.x || got.y != want.y || got.angle != want.angle || got.kind != want.kind || got.flags != want.flags) \{\n                bad++\n            \}\n            total += thing_sum(got) + int64(copies[i].flags)\n        \}\n        var lumps = reinterpret<Lump?>(bytes + 1)\n        var lcopies = reinterpret<Lump?>(bytes + N * 16 + 5)\n        for (i in range(N)) \{\n            lumps[i] = fill_lump(i)\n        \}\n        for (i in range(N)) \{\n            lcopies[i] = lumps[i]\n        \}\n        crt::memset(lumps, 0, uint64(N * 16))\n        crt::memcpy(lumps, lcopies, uint64(N * 16))\n        for (i in range(N)) \{\n            let want = fill_lump(i)\n            if (lumps[i].filepos != want.filepos || lumps[i].size != want.size || lump_sum(lumps[i]) != lump_sum(want)) \{\n                bad++\n            \}\n            total += lump_sum(lumps[i])\n        \}\n        crt::free(bytes)\n    \}\n    var want_total = 0l\n    for (i in range(N)) \{\n        want_total += thing_sum(fill_thing(i)) + int64(int16(-i)) + lump_sum(fill_lump(i))\n    \}\n    print(\"misaligned bad=\{bad\} total=\{total\} want=\{want_total\}\\n\")\n    return bad == 0 && total == want_total ? 0 : 1\n\}\n"

let MISALIGNED_TIERS = fixed_array("interp", "jit", "exe", "aot")

[test]
def test_misaligned_records(tt : T?) {
    let work = test_temp_dir()
    let entry = path_join(work, "misaligned.das")
    fwrite(entry, SOURCE)
    for (tier in MISALIGNED_TIERS) {
        tt |> run("under {tier} arrays of int16 and int records at odd addresses store, copy and read back as aligned ones") @(t : T?) {
            var out : string
            let rc = run_tier(entry, tier, path_join(work, tier), out, CONVERTED_MODULES)
            to_log(LOG_INFO, "{tier}: rc {rc}\n{out}")
            t |> equal(rc, 0, "{tier}: {out}")
            t |> success(out |> contains("misaligned bad=0 total=149915982144 want=149915982144"), "{tier}: {out}")
        }
    }
}
