# converter Architecture - the emitter's member addresses and one past an array's end

Companion to `ARCHITECTURE.md` in this folder, continuing section 4 of `ARCHITECTURE_EMITTER.md`
beside `ARCHITECTURE_EMITTER_AGGREGATES.md`: how the address of a member at offset 0 and the
address one past an array's end are spelled.

### The address of a member at offset 0 {#first-member-address}

The address of a member, `&p->f`, is `addr(p.f)`, and an array member's decay `addr(p.a[0])`. Under
the `first_member` option `reinterpret` (`--first-member reinterpret` or the sidecar's
`"first_member": "reinterpret"`; `addr`, the default, is the idiomatic form) a member at clang's
offset 0 is its record's pointer reinterpreted to the result's type, which the interpreter runs
without the field access and the `addr`: `reinterpret<TValue?>(base + a)` for `&(base + a)->val`,
`reinterpret<int?>(p)` for `&p->a.b` when `a` and `b` both sit at offset 0, for `&(*p).a.b` and
for the decay of `p->cells`, and `reinterpret<Inner?>(p + i)` for `&p[i].a`. Every union member sits
at offset 0. A pointer `BitCast` under the record's pointer falls away, `reinterpret<Table?>(o)`
for `&((union GCUnion *) o)->h`, and a pointer that already has the result's das type is itself
(`ip` for `&((union Cell *) ip)->i` of an `int *ip`). A `const` or volatile member takes the pointer
type das spells for it, the qualifier dropped as everywhere. The option keeps `addr(...)` for a
member at another offset, for a chain that ends at a record held by value (`&s.a`, `&arr[i].a`),
for a member of a marshal-only record and for one of a marshal-only type; C takes no bitfield's
address. The readability criteria count each such `reinterpret` as noise, which is why it is
opt-in (`converter/tests/fixtures/p7_first_member.c`).

### One past an array's end

C may form `&a[N]`, the address one past the end of `T a[N]`, and das range-checks
`addr(a[N])` (`docs/probe-findings.md` F45), so `&a[k]` of an array takes one of three forms. A
constant index is folded: at the length it is `addr(a[0]) + N` (an enumerator keeps its name,
`addr(a[0]) + int(E.X)`), below or past it `addr(a[k])`, whose range check stands for C's
undefined behaviour past the end. A constant is a decimal literal within `int64` or an
enumerator, under integer casts that each hold its value; a `_Bool` cast holds none, since it
makes any nonzero value 1. A plain load (a variable or a field under casts, read without a
volatile access, never a bitfield or a union member, which read through an accessor call) into
an array without effects is, under the `past_end` option `inline` (`--past-end inline` or the
sidecar's `"past_end": "inline"`), `k == N ? addr(a[0]) + N : addr(a[k])`: das's own range
check on every index but the length, with no call per access (`end_index` was 12.6% of binjgb's
interpreter profile), the length typed as the index (`4u`, `4l`, `4ul`). By default (`call`), and
for any other index, which that form would spell or evaluate twice, it is `addr(a[0]) +
end_index(k, N)` (`c_runtime/c_bounds`, an unsigned compare against `N` that panics in das's
range-check wording): the conditional spells the index, the array and the length twice, and the
readability capture counts the repeated length (`literal_named` +59 over its inputs).
