/* c.c and d.c read each other's objects: only forward-declared objects part them */
int c_val = 2;
extern int d_val;
int d_twice(int x);

int c_run(void) {
    return d_val + d_twice(c_val);
}
