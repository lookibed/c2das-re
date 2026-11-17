// C strings: bytes, pointer walks and the C library, as c2das-re keeps them (uint8, never das strings).
#include <stdio.h>
#include <string.h>
#include <ctype.h>

static void upcase(char *s)
{
    for (; *s; s++)
        *s = (char)toupper((unsigned char)*s);
}

static int count_char(const char *s, char c)
{
    int n = 0;
    while ((s = strchr(s, c)) != NULL) {
        n++;
        s++;
    }
    return n;
}

int main(void)
{
    char text[64];
    strcpy(text, "translated by c2das-re");
    printf("%s has %d bytes and %d 'a's\n", text, (int)strlen(text), count_char(text, 'a'));
    upcase(text);
    printf("%s\n", text);
    return 0;
}
