/* e.c and f.c take each other's function addresses and e.c spells f.c's record: no forward
   declaration of functions or objects parts them */
static struct S *keep;
int f_id(int x);

int e_run(void) {
    int (*p)(int) = f_id;
    return keep == 0 ? p(4) : 0;
}
