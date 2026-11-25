/* <stdio.h> of the own libc header set (frontend/include/ARCHITECTURE.md). */
#ifndef _STDIO_H
#define _STDIO_H

#include <stddef.h>

#ifndef __GNUC_VA_LIST
#define __GNUC_VA_LIST
typedef __builtin_va_list __gnuc_va_list;
#endif

typedef struct _IO_FILE FILE;

#define _IOFBF 0
#define _IOLBF 1
#define _IONBF 2
#define BUFSIZ 8192
#define EOF (-1)
#define SEEK_SET 0
#define SEEK_CUR 1
#define SEEK_END 2
#define L_tmpnam 20
#define TMP_MAX 238328
#define FILENAME_MAX 4096
#define FOPEN_MAX 16

extern FILE *stdin;
extern FILE *stdout;
extern FILE *stderr;
#define stdin stdin
#define stdout stdout
#define stderr stderr

int remove(const char *);
int rename(const char *, const char *);
FILE *tmpfile(void);
char *tmpnam(char *);
int fclose(FILE *);
int fflush(FILE *);
FILE *fopen(const char *, const char *);
FILE *freopen(const char *, const char *, FILE *);
int setvbuf(FILE *, char *, int, size_t);
int fprintf(FILE *, const char *, ...);
int printf(const char *, ...);
int sprintf(char *, const char *, ...);
int snprintf(char *, size_t, const char *, ...);
int vfprintf(FILE *, const char *, __gnuc_va_list);
int vprintf(const char *, __gnuc_va_list);
int vsprintf(char *, const char *, __gnuc_va_list);
int vsnprintf(char *, size_t, const char *, __gnuc_va_list);
int fscanf(FILE *, const char *, ...);
int sscanf(const char *, const char *, ...);
int vfscanf(FILE *, const char *, __gnuc_va_list);
int vsscanf(const char *, const char *, __gnuc_va_list);
int fgetc(FILE *);
char *fgets(char *, int, FILE *);
int fputc(int, FILE *);
int fputs(const char *, FILE *);
int getc(FILE *);
int ungetc(int, FILE *);
size_t fread(void *, size_t, size_t, FILE *);
size_t fwrite(const void *, size_t, size_t, FILE *);
int fseek(FILE *, long, int);
long ftell(FILE *);
void clearerr(FILE *);
int feof(FILE *);
int ferror(FILE *);

#endif
