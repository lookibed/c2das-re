// a layout file (`converter/ARCHITECTURE_LAYOUT.md`, The layout file): the metric names it apart,
// so its reinterpret, which a real one never holds, is no count of the program
[init]
def private c2das_layout_check {
    static_assert(typeinfo sizeof(type<int>) == 4, "int: 4 bytes")
    let probe = unsafe(reinterpret<uint8?>(null))
    assert(probe == null)
}
