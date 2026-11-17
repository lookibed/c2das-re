options gen2
options indenting = 4

module frame_digest shared public

//! The fold of quakegeneric's frame hashes (web/ARCHITECTURE.md section 7): each hash as the native
//! entry prints it, `frame[i]=v\n` with v a signed int, folded byte for byte into an FNV-1a 32
//! digest. `quake/shell.html`'s `frameDigest` folds the reference's lines the same way.

//! The digest of the first `count` of `hashes`.
def frame_digest(hashes : array<int>; count : int) : uint {
    var digest = 2166136261u
    for (i in range(count)) {
        let line = "frame[{i}]={hashes[i]}\n"
        for (c in line) {
            digest ^= uint(c)
            digest *= 16777619u
        }
    }
    return digest
}
