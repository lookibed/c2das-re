/* local statics hoisted as `<function>_<name>` next to names that already spell that */

/* externals spelled like `e`'s hoisted local static and its next number */
extern int e_x;
extern int e_x1;

int e(void) {
    static int x = 1;
    return x++;
}

int e_read(void) {
    return e_x + e_x1;
}

/* two local statics of one name, and file-scope statics taking the first two numbers */
int f(void) {
    static int x = 1;
    {
        static int x = 50;
        x++;
    }
    return x++;
}

static int f_x = 100;
static int f_x1 = 200;

/* locals spelled like the numbers the hoisted statics take */
int g(void) {
    int f_x2 = 7;
    return f_x + f_x2;
}

int h(void) {
    int f_x3 = 9;
    return f_x1 + f_x3;
}

/* a local of the function itself spelled like its hoisted static */
int k(void) {
    static int x = 1;
    int k_x = 3;
    return x + k_x;
}
