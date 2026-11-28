options gen2
options indenting = 4

module c_inits public

require math
require daslib/cmp
require c_exprs public

//! Initializers as clang's semantic form holds them and Dumper A writes them
//! (`ARCHITECTURE_INITS.md`): designators resolved to positions, elided braces opened as the
//! subobjects' own lists, the union's one member, braced scalars, character arrays from string
//! literals, compound literals, and the count an unsized array takes from its list.

// the object a list is filling: its `init_list` node, its unqualified pool type, the position the
// next item without a designator fills, and, for a union, whether a member holds a value
struct Frame {
    x : CirExpr?
    t : int
    next : int
    filled : bool
}

def private unq(r : CIr; t : int) : int => r.unqualified[t]

def private is_record(r : CIr; t : int) : bool => r.pool[unq(r, t)].k == "struct" || r.pool[unq(r, t)].k == "union"

def private is_aggregate(r : CIr; t : int) : bool => is_record(r, t) || r.pool[unq(r, t)].k == "array"

// whether pool type `t` is an array of plain 8-bit integers, which a string literal initializes
def private is_char_array(r : CIr; t : int) : bool {
    let u = unq(r, t)
    return false if (r.pool[u].k != "array")
    let e = unq(r, r.pool[u].elem)
    return r.pool[e].k == "int" && r.pool[e].w == 8
}

// whether field `f` takes an initializer: every field but an unnamed bit-field, which is padding
def private initialized(f : CirField) : bool => !(f.is_bitfield && empty(f.name))

// the first position of a record of pool type `u` at or after `pos` that takes an initializer;
// the field count when none does
def private field_at_or_after(r : CIr; u, pos : int) : int {
    var at = pos
    while (at < length(r.pool[u].fields) && !initialized(r.pool[u].fields[at])) {
        at++
    }
    return at
}

// the position after `pos` in object `fr`'s order
[arch(at="ARCHITECTURE_INITS.md#c-inits-order")]
def private after(r : CIr; fr : Frame; pos : int) : int => r.pool[fr.t].k == "array" ? pos + 1 : field_at_or_after(r, fr.t, pos + 1)

// whether object `fr` has no position left for an item without a designator
[arch(at="ARCHITECTURE_INITS.md#c-inits-order")]
def private exhausted(r : CIr; fr : Frame) : bool {
    let k = r.pool[fr.t].k
    if (k == "array") {
        return r.pool[fr.t].count >= 0 && fr.next >= r.pool[fr.t].count
    } elif (k == "union") {
        return fr.filled || fr.next >= length(r.pool[fr.t].fields)
    }
    return fr.next >= length(r.pool[fr.t].fields)
}

// the pool type of position `pos` of object `fr`: the element or the field (a qualifier is dropped
// where the value converts and where the table interns the type, so the record's adds nothing)
def private slot_type(r : CIr; fr : Frame; pos : int) : int => r.pool[fr.t].k == "array" ? r.pool[fr.t].elem : r.pool[fr.t].fields[pos].t

// a frame over a new empty list of pool type `t`, at its first position; null with the error set
// for an incomplete record or a flexible array member's list
def private frame_of(var r : CIr; var p : CParser; t, tok : int; var fr : Frame&) : bool {
    let u = unq(r, t)
    if (is_record(r, u) && (!c_tag_complete(r, p) || !key_exists(r.layouts, u))) {
        c_refuse(r, p, tok, "an initializer of an incomplete record")
        return false
    }
    fr = Frame(x = new CirExpr(e = "init_list", t = t), t = u, next = r.pool[u].k == "array" ? 0 : field_at_or_after(r, u, 0))
    return true
}

// value `v` placed at position `pos` of object `fr`, replacing an earlier one there; a union keeps
// its last member alone
def private put(var fr : Frame; pos : int; var v : CirExpr?) {
    for (old in fr.x.init_items) {
        if (old.pos == pos) {
            delete_expr(old.v)
            old.v = v
            return
        }
    }
    fr.x.init_items |> push(CirInitItem(pos = pos, v = v))
}

// the frame of the subobject at position `pos` of the top frame, its list made there or the one an
// earlier item made; false with the error set when an earlier item gave it a value that is no list
// (clang's designated update of such a value)
def private open_subobject(var r : CIr; var p : CParser; var stack : array<Frame>; pos, tok : int) : bool {
    var top = stack[length(stack) - 1]
    let st = slot_type(r, top, pos)
    for (old in top.x.init_items) {
        if (old.pos == pos) {
            if (old.v.e != "init_list") {
                c_refuse(r, p, tok, "a designator into a subobject an earlier initializer gave a whole value")
                return false
            }
            stack |> push(Frame(x = old.v, t = unq(r, st), next = r.pool[unq(r, st)].k == "array" ? 0 : field_at_or_after(r, unq(r, st), 0)))
            return true
        }
    }
    var fr : Frame
    return false if (!frame_of(r, p, st, tok, fr))
    top.x.init_items |> push(CirInitItem(pos = pos, v = fr.x))
    if (r.pool[top.t].k == "union") {
        top.filled = true
    }
    stack[length(stack) - 1] = top
    stack |> push(fr)
    return true
}

// the positions designator node `dn` names in object `top`: a member's path through the anonymous
// members that make it visible, or an index; `last` the last index of a GNU range, -1 for none;
// empty with the error set for a designator refused
def private designator_path(var r : CIr; var p : CParser; dn : CNodeRec; top : Frame; var last : int&) : array<int> {
    var path : array<int>
    last = -1
    if (dn.kind == CNode.DESIG_FIELD) {
        if (!is_record(r, top.t)) {
            c_refuse(r, p, dn.tok, "a member designator of other than a struct or union")
            return <- path
        }
        let name = pp_symbol_text(p.unit.lx, dn.a)
        path <- c_member_path(r, top.t, name)
        if (empty(path)) {
            c_refuse(r, p, dn.tok, "a designator of a member '{name}' its record does not have, which")
        }
        return <- path
    }
    if (r.pool[top.t].k != "array") {
        c_refuse(r, p, dn.tok, "an index designator of other than an array")
        return <- path
    }
    var v = 0l
    var w = 0l
    if (!c_fold_node(r, p, dn.a, v) || (dn.b >= 0 && !c_fold_node(r, p, dn.b, w))) {
        c_refuse(r, p, dn.tok, "an array index other than an integer constant expression")
        return <- path
    }
    path |> push(int(v))
    last = dn.b >= 0 ? int(w) : -1
    return <- path
}

// the designators from `d` resolved against the top frame: each picks a position, every one but
// the last opening its subobject, a member an anonymous member makes visible through that member;
// the last position, and the last index of a GNU range, in `pos` and `last`
[arch(at="ARCHITECTURE_INITS.md#c-inits-designators")]
def private designate(var r : CIr; var p : CParser; var stack : array<Frame>; d, tok : int; var pos : int&; var last : int&) : bool {
    var at = d
    while (at >= 0) {
        let dn = p.ast.nodes[at]
        var inscope path <- designator_path(r, p, dn, stack[length(stack) - 1], last)
        return false if (empty(path))
        for (step, i in path, count()) {
            if (i + 1 < length(path) || dn.next >= 0) {
                if (last >= 0) {
                    c_refuse(r, p, dn.tok, "a range designator followed by another designator")
                    return false
                }
                stack[length(stack) - 1].next = step
                return false if (!open_subobject(r, p, stack, step, tok))
            } else {
                pos = step
            }
        }
        at = dn.next
    }
    return true
}

// the value `n`, already typed as `typed` when not null, placed at the top frame's next position;
// an aggregate there that `n` does not initialize whole has its braces elided: its list opens and
// takes `n` at its own first position; the top frame then moves past the position filled
[arch(at="ARCHITECTURE_INITS.md#c-inits-elision")]
def private place(var r : CIr; var p : CParser; var stack : array<Frame>; n : int; var typed : CirExpr?; tok : int) : bool {
    var top = stack[length(stack) - 1]
    let pos = top.next
    let st = slot_type(r, top, pos)
    let node = p.ast.nodes[n]
    var v : CirExpr?
    if (node.kind == CNode.INIT_LIST || (node.kind == CNode.STRING && is_char_array(r, st)) || !is_aggregate(r, st)) {
        if (typed != null) {
            v = c_assigned(r, typed, st)
        } else {
            v = c_initializer(r, p, n, st)
        }
        return false if (v == null)
    } else {
        if (is_record(r, st) && node.kind != CNode.STRING) {
            if (typed == null) {
                typed = c_expr(r, p, n)
                return false if (typed == null)
            }
            if (unq(r, typed.t) == unq(r, st)) {
                v = c_assigned(r, typed, st)
            }
        }
        if (v == null) {
            if (r.pool[unq(r, st)].k == "array" && r.pool[unq(r, st)].count < 0) {
                delete_expr(typed)
                c_refuse(r, p, tok, "an initializer of a flexible array member")
                return false
            }
            if (!open_subobject(r, p, stack, pos, tok)) {
                delete_expr(typed)
                return false
            }
            return place(r, p, stack, n, typed, tok)
        }
    }
    put(top, pos, v)
    if (r.pool[top.t].k == "union") {
        top.filled = true
        var keep = v
        for (item in top.x.init_items) {
            if (item.v != keep) {
                delete_expr(item.v)
            }
        }
        top.x.init_items |> clear()
        top.x.init_items |> push(CirInitItem(pos = pos, v = keep))
    }
    top.next = after(r, top, pos)
    stack[length(stack) - 1] = top
    return true
}

// every list under `x`, `x` included, in the order of its positions
def private sort_positions(var x : CirExpr?) {
    return if (x == null || x.e != "init_list")
    sort(x.init_items, cmp_by(_.pos))
    for (item in x.init_items) {
        sort_positions(item.v)
    }
}

// the braced list `n` of an aggregate of pool type `t`: each item at the position its designators
// name or the next one in order, a subobject with elided braces taking the items after it while it
// has positions, an item past the object's last position dropped, as clang drops it
[arch(at="ARCHITECTURE_INITS.md#c-inits-designators")]
def private aggregate_list(var r : CIr; var p : CParser; n, t : int) : CirExpr? {
    var stack : array<Frame>
    var root : Frame
    return null if (!frame_of(r, p, t, p.ast.nodes[n].tok, root))
    stack |> push(root)
    var item = p.ast.nodes[n].a
    while (item >= 0) {
        let it = p.ast.nodes[item]
        var ok = true
        if (it.a >= 0) {
            stack |> resize(1)
            var pos = -1
            var last = -1
            ok = designate(r, p, stack, it.a, it.tok, pos, last)
            if (ok) {
                let depth = length(stack)
                stack[depth - 1].next = pos
                if (last >= 0) {
                    for (k in range(pos, last + 1)) {
                        stack |> resize(depth)
                        stack[depth - 1].next = k
                        ok = ok && place(r, p, stack, it.b, null, it.tok)
                    }
                } else {
                    ok = place(r, p, stack, it.b, null, it.tok)
                }
            }
        } else {
            while (length(stack) > 1 && exhausted(r, stack[length(stack) - 1])) {
                stack |> pop()
                stack[length(stack) - 1].next = after(r, stack[length(stack) - 1], stack[length(stack) - 1].next)
            }
            if (!exhausted(r, stack[length(stack) - 1])) {
                ok = place(r, p, stack, it.b, null, it.tok)
            }
        }
        if (!ok) {
            delete_expr(root.x)
            return null
        }
        item = it.next
    }
    sort_positions(root.x)
    return root.x
}

//! The initializer node `init` of an object of pool type `t`, converted as C11 6.7.9 says and
//! shaped as clang's semantic form: a character array's string literal, braced or not, typed as
//! the array; an aggregate's list by `aggregate_list`; a scalar's value, braced or not, by
//! assignment; null with the error set at the first construct refused.
[arch(at="ARCHITECTURE_INITS.md#c-inits-lists")]
def c_initializer(var r : CIr; var p : CParser; init, t : int) : CirExpr? {
    let n = p.ast.nodes[init]
    if (n.kind == CNode.STRING && is_char_array(r, t)) {
        var s = c_string_literal(r, p, n.a, n.b)
        if (s != null) {
            s.t = t
        }
        return s
    } elif (n.kind != CNode.INIT_LIST) {
        var x = c_expr(r, p, init)
        return x == null ? null : c_assigned(r, x, t)
    }
    let first = n.a
    if (!is_aggregate(r, t)) {
        if (first < 0 || p.ast.nodes[first].next >= 0 || p.ast.nodes[first].a >= 0) {
            c_refuse(r, p, n.tok, "a braced scalar initializer of other than one value")
            return null
        }
        return c_initializer(r, p, p.ast.nodes[first].b, t)
    }
    if (is_char_array(r, t) && first >= 0 && p.ast.nodes[first].next < 0 && p.ast.nodes[first].a < 0 && p.ast.nodes[p.ast.nodes[first].b].kind == CNode.STRING) {
        return c_initializer(r, p, p.ast.nodes[first].b, t)
    }
    return aggregate_list(r, p, init, t)
}

//! The count an unsized array of pool element type `elem` takes from initializer list `init`: one
//! past the last position its list fills; -2 with the error set where the list is refused.
[arch(at="ARCHITECTURE_INITS.md#c-inits-lists")]
def c_init_count(var r : CIr; var p : CParser; init, elem : int) : int {
    var x = aggregate_list(r, p, init, c_array(r, elem, -1))
    return -2 if (x == null)
    var count = 0
    for (item in x.init_items) {
        count = max(count, item.pos + 1)
    }
    delete_expr(x)
    return count
}

//! The compound literal `(T){...}` of node `n`: its type, an unsized array sized by its list, and
//! its list; a scalar's list holds its one value at position 0, none for `{}`; a character array's
//! lone braced string at file scope stays a list over the string.
[arch(at="ARCHITECTURE_INITS.md#c-inits-compound")]
def c_compound_literal(var r : CIr; var p : CParser; n : int) : CirExpr? {
    let node = p.ast.nodes[n]
    var t = c_type_name_type(r, p, node.a)
    return null if (t < 0)
    if (r.pool[unq(r, t)].k == "array" && r.pool[unq(r, t)].count < 0) {
        let count = c_initializer_count(r, p, node.b, r.pool[unq(r, t)].elem)
        return null if (count < 0)
        t = c_array(r, r.pool[unq(r, t)].elem, count)
    }
    var init : CirExpr?
    let first = p.ast.nodes[node.b].a
    let lone_string = first >= 0 && p.ast.nodes[first].next < 0 && p.ast.nodes[first].a < 0 && p.ast.nodes[p.ast.nodes[first].b].kind == CNode.STRING
    if (empty(r.id_marks) && lone_string && is_char_array(r, t)) {
        // at file scope clang wraps the list's value in a constant expression, so Dumper A keeps
        // the list over the string
        var s = c_initializer(r, p, p.ast.nodes[first].b, t)
        return null if (s == null)
        init = new CirExpr(e = "init_list", t = t)
        init.init_items |> push(CirInitItem(pos = 0, v = s))
    } elif (is_aggregate(r, t)) {
        init = c_initializer(r, p, node.b, t)
    } else {
        if (first >= 0 && (p.ast.nodes[first].next >= 0 || p.ast.nodes[first].a >= 0)) {
            c_refuse(r, p, node.tok, "a scalar compound literal of other than one value")
            return null
        }
        init = new CirExpr(e = "init_list", t = t)
        if (first >= 0) {
            var v = c_initializer(r, p, p.ast.nodes[first].b, t)
            if (v == null) {
                delete_expr(init)
                return null
            }
            init.init_items |> push(CirInitItem(pos = 0, v = v))
        }
    }
    return init == null ? null : new CirExpr(e = "compound_lit", t = t, init = init)
}
