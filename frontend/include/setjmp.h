/* <setjmp.h> of the own libc header set (frontend/include/ARCHITECTURE.md). */
#ifndef _SETJMP_H
#define _SETJMP_H

struct __jmp_buf_tag {
    long long __jmpbuf[8];
    int __mask_was_saved;
    unsigned long long __saved_mask[16];
};
typedef struct __jmp_buf_tag jmp_buf[1];

int setjmp(jmp_buf);
int _setjmp(jmp_buf);
#define setjmp(env) _setjmp (env)
void longjmp(jmp_buf, int);
void _longjmp(jmp_buf, int);

#endif
