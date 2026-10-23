/* a barrier in a header of the program's own folder: the asm statement converts with the file */
#ifndef P5_GNU_SHIMS_H
#define P5_GNU_SHIMS_H

static inline void header_barrier(void) { __asm__ __volatile__("" : : : "memory"); }

#endif
