// tic_digest.h - the C twin of web/puredoom/tic_digest.das: the fold of PureDOOM's per-tic checksum
// lines (web/ARCHITECTURE.md section 3). Doom prints each `tic=<n> cs=<hex> fb=<hex>` line in pieces,
// the first piece exactly `tic=`; every byte from that piece to its newline, newline included, goes
// into an FNV-1a 32 hash, and each newline counts a line. tests/test_web_tic_digest.das pins it.
//
// Copyright (C) 2026 the c2das-re authors; GPL-2, as main_web.c.

#ifndef TIC_DIGEST_H
#define TIC_DIGEST_H

#include <stdint.h>
#include <string.h>

typedef struct {
    int lines;
    int in_line;
    uint32_t hash;
} tic_digest_t;

#define TIC_DIGEST_INIT {0, 0, 2166136261u}

// takes one piece Doom printed; 1 when it belongs to a checksum line (folded, not printed)
static int tic_digest_piece(tic_digest_t* d, const char* piece)
{
    if (!d->in_line && strcmp(piece, "tic=") == 0)
        d->in_line = 1;
    if (!d->in_line)
        return 0;
    for (const unsigned char* p = (const unsigned char*)piece; *p; p++) {
        d->hash ^= *p;
        d->hash *= 16777619u;
        if (*p == '\n') {
            d->in_line = 0;
            d->lines++;
        }
    }
    return 1;
}

#endif
