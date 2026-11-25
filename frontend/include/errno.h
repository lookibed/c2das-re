/* <errno.h> of the own libc header set (frontend/include/ARCHITECTURE.md). */
#ifndef _ERRNO_H
#define _ERRNO_H

int *__errno_location(void);
#define errno (*__errno_location ())

#define EISDIR 21
#define EINVAL 22
#define EDOM 33
#define ERANGE 34
#define EILSEQ 84

#endif
