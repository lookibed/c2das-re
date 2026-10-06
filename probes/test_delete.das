options gen2
options persistent_heap
require dastest/testing_boost public

struct Node {
    v : int
    left : Node?
    right : Node?
    kids : array<Node?>
}

def private make_tree : Node ? {
    var root = new Node(v = 1)
    root.left = new Node(v = 2)
    root.right = new Node(v = 3)
    root.kids <- [new Node(v = 4), new Node(v = 5)]
    root.kids[0].left = new Node(v = 6)
    return root
}

[test]
def test_delete(t : T?) {
    t |> run("delete of a struct frees its pointer fields and the pointees of its pointer arrays") @(t : T?) {
        let before = heap_bytes_allocated()
        var root = make_tree()
        t |> equal(heap_bytes_allocated() > before, true)
        unsafe {
            delete root
        }
        t |> equal(root == null, true)
        t |> equal(heap_bytes_allocated(), before)
    }
}
