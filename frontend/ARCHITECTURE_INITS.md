# frontend Architecture - initializers

Companion to `ARCHITECTURE.md` in this folder: `c_inits.das`, the initializers of Dumper C's C-IR
builder, sections 68 to 72 and 78. An initializer is written as clang's semantic form holds it, which is
what Dumper A dumps (`converter/dumper_a.das`'s `dump_init_list`): an `init_list` per aggregate,
its items `{pos, v}` in the order of their positions, a position no item names left out (its
value is zero), every designator resolved to the position it names.

## 68. Initializers and lists {#c-inits-lists}

`c_initializer` gives the initializer node of an object of a pool type its C-IR (C11 6.7.9): a
string literal for a character array (an array of 8-bit integers), in parentheses or not, braced
or not (the items after a braced one typed and dropped, as clang drops excess items), is the
literal typed as the array itself (`char s[10] = "ab"` gives the literal `char[10]`), as clang
types it; any other value of a scalar, braced around one value or not, is converted to the scalar
by assignment (`ARCHITECTURE_EXPRS.md` section 42); the braced list of an aggregate - a struct, a
union or an array - is that aggregate's `init_list`, built by sections 69 to 71. A braced scalar
of other than one value is refused.

An unsized array takes its count from its initializer (`ARCHITECTURE_TYPES.md` section 27): a
list's count, `c_init_count`, is one past the last position the list fills at its top, the list
built over the array with no count (`int b[] = {[1 ... 3] = 4}` has 4 elements, `struct P a[] =
{1, 2, 3}` of a two-member `P` has 2).

## 69. Positions and the order of a list {#c-inits-order}

A list fills one object, its current object (6.7.9p17). A struct's positions are its field
indices, an unnamed bit-field skipped, since it is padding and clang gives it no item (`struct {
int a : 3; int : 2; int b : 4; } g = {1, 2}` fills positions 0 and 2); an anonymous member is a
position like any field. An array's positions are its indices, with no last one when it has no
count. A union has one position filled at most: an item without a designator fills its first
member, a designated one the member it names, and a later item replaces the member an earlier one
filled, so its list holds one item. An item with no designator fills the position after the one
the item before it filled, the first position for the first item. An item past the object's last
position is dropped, as clang drops it with a warning; it is not typed. An item for a position an
earlier item filled replaces it.

## 70. Designators {#c-inits-designators}

An item's designators are resolved from the list's own object: `.member` (or the old GNU
`member:`, which the parser reads as it) names a field of a struct or union, through the anonymous
members that make it visible, each anonymous member a subobject of its own; `[k]` an index of an
array, `k` an integer constant expression (`c_fold_node`); GNU's `[first ... last]` each index of
the range, the value built once per index, as Dumper A dumps clang's one shared value once per
position; when that value opens elided braces (section 71), the items after the range fill one
subobject the range's elements share, so each element takes a copy of the last one's list once
its frames close (`struct P a[3] = {[0 ... 1] = 1, 2, 3}` gives `a[0]` and `a[1]` both `{1, 2}`).
Every designator but the last opens the subobject it names: the list an earlier item made there,
or a new one. In a union, a new member's list replaces the member an earlier item filled
(`{.i = 5, .s.x = 1}` keeps `s` alone), and a union an earlier item filled, reopened, has no
position left for an item without a designator, so that item goes on past the union. The value then goes to the last designator's position, and the items
after it go on from the position after it, at the depth of the last designator: `struct Q { struct
P a; int b; } q = {.a.y = 4, 5}` with `P` of `x, y, z` puts 5 in `a.z`, and with `P` of `x, y` in
`b`, as each subobject that runs out of positions hands on to the object around it.

Refused: a member designator of other than a struct or union, an index designator of other than an
array, a member the record does not have, an index other than an integer constant expression, a
range followed by another designator, and a designator into a subobject an earlier item gave a
whole value (`{.a = p, .a.x = 1}`, clang's designated update of `p`, which Dumper A does not dump).

## 71. Elided braces {#c-inits-elision}

A value at the position of an aggregate subobject that does not initialize the subobject whole has
the subobject's braces elided (6.7.9p20): the subobject's list opens at that position and the value
goes to its first position, again with braces elided while that position is an aggregate; the items
after it fill the subobject while it has positions, then the object around it goes on (section 69).
A braced list, a string literal for a character array, and a value of the subobject's own record
type (`struct Q q = {p, 1}` with `p` a `struct P`: the value converted to the record, its read)
initialize a subobject whole; any other value, a string literal for an array of other than 8-bit
integers among them, opens its braces. A value that would open a flexible array member's braces
is refused (section 78).

## 72. Compound literals {#c-inits-compound}

`(T){...}` is a `compound_lit` of type `T` over its list (`c_compound_literal`): an aggregate's
list as an initializer's (sections 57 to 60), an unsized array's count taken from its list as an
unsized variable's is; a scalar's list an `init_list` of the scalar holding its one value at
position 0, converted by assignment, and none for `{}`; more than one value is refused. A
character array's lone braced string literal at file scope is an `init_list` holding the string at
position 0, where in a body it is the string itself: clang wraps a file-scope compound literal's
values in a constant expression, so Dumper A finds no bare string under the list. A compound literal
is an lvalue: its address is taken, an array one decays, any other is read (`LValueToRValue`). Its
type enters the table before its list's, the list's own type the same.

## 78. Flexible array members {#c-inits-flexible}

A flexible array member takes a value only at the top of a static object's initializer, clang's
GNU extension (an automatic object's, a compound literal's and a nested record's are refused,
`CTypes.init_static` marking the static object's list): a braced list or a character array's
string, by position or by a member designator. Its value is typed as clang types it, an array of
the count its list fills or of its string's bytes (`{2, {3, 4}}` gives `int[2]`, `{2, "ab"}`
`char[3]`), where Dumper A reads that type. A value with elided braces there is refused, and a
designator into its elements (`{.a[2] = 7}`) is invalid C, as clang rejects it.
