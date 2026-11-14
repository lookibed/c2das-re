/* the POSIX and stdio calls doomgeneric and quakegeneric make that the crt module binds (P9.32):
   the case-blind compares, `strdup`, `fputc`, `fgetc` and `mkdir` (on a folder that exists, so
   the run leaves nothing behind) */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/stat.h>

int main(void) {
    char *d = strdup("Abc");
    int same = strcasecmp(d, "aBC");
    int prefix = strncasecmp(d, "abx", 2);
    int less = strcasecmp("abc", "ABD") < 0;
    fputc('A' + same + prefix, stdout);
    fputc('\n', stdout);
    FILE *f = tmpfile();
    fputc('q', f);
    fputc('r', f);
    fseek(f, 0, SEEK_SET);
    int first = fgetc(f);
    int second = fgetc(f);
    int end = fgetc(f);
    fclose(f);
    int made = mkdir(".", 0755);
    printf("%s %d %c%c %d %d\n", d, less, first, second, end, made);
    free(d);
    return 0;
}
