options gen2
options indenting = 4

module tic_digest shared public

//! The fold of PureDOOM's per-tic checksum lines (web/ARCHITECTURE.md section 3): Doom prints each
//! `tic=<n> cs=<hex> fb=<hex>` line in pieces, the first piece exactly `tic=`; every byte from that
//! piece to its newline, newline included, goes into an FNV-1a 32 hash, and each newline counts a
//! line. `shell.html`'s `ticDigest` folds the native log's lines the same way.

struct TicDigest {
    lines : int = 0
    hash : uint = 2166136261u
    in_line : bool = false
}

//! Takes one piece Doom printed; true when the piece belongs to a checksum line (folded, not printed).
def tic_digest_piece(var digest : TicDigest; piece : uint8?) : bool {
    if (!digest.in_line && is_tic_start(piece)) {
        digest.in_line = true
    }
    if (!digest.in_line) {
        return false
    }
    var p = piece
    while (*p != 0u8) {
        digest.hash ^= uint(*p)
        digest.hash *= 16777619u
        if (*p == 10u8) {
            digest.in_line = false
            digest.lines++
        }
        p = unsafe(p + 1)
    }
    return true
}

// whether `piece` is exactly `tic=`
def private is_tic_start(piece : uint8?) : bool {
    let start = fixed_array<uint8>(116u8, 105u8, 99u8, 61u8)
    var p = piece
    for (c in start) {
        if (*p != c) {
            return false
        }
        p = unsafe(p + 1)
    }
    return *p == 0u8
}
