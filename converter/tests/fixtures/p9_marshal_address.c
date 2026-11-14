#include <stdio.h>
#include <stdlib.h>

/* the address of a scalar field of a marshal-only record (Doom's `pack = &pcx->data`, pcx_t 129
   bytes where das would make it 130): the record's bytes plus clang's offset of the field, read
   past the record as the program allocated it */
typedef struct {
    char manufacturer;
    unsigned short width;
    unsigned char data;
} __attribute__((packed)) header_t;

int main(void) {
    header_t *h = calloc(1, sizeof(header_t) + 4);
    h->width = 300;
    unsigned char *pack = &h->data;
    unsigned short *w = &h->width;
    pack[0] = 7;
    pack[2] = 9;
    printf("%d %d %d %d %d\n", (int) sizeof(header_t), h->data, pack[2], *w, (int) (pack - (unsigned char *) h));
    free(h);
    return 0;
}
