#include <stdio.h>

/* fscanf over a stream (Quake's `Host_Loadgame_f`): a version, a word, floats one per line */
int main(void) {
    FILE *f = tmpfile();
    fputs("5\nstart\n1.5\n2.25\n0.75\ne1m1\n", f);
    fseek(f, 0, SEEK_SET);
    int version = 0;
    char str[32];
    float parms[3];
    fscanf(f, "%i\n", &version);
    fscanf(f, "%s\n", str);
    for (int i = 0; i < 3; i++) {
        fscanf(f, "%f\n", &parms[i]);
    }
    char map[32];
    int r = fscanf(f, "%s\n", map);
    int end = fscanf(f, "%d", &version);
    printf("%d %s %g %g %g %s %d %d\n", version, str, parms[0], parms[1], parms[2], map, r, end);
    fclose(f);
    return 0;
}
