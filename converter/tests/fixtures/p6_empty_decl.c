/* P6.3d: a file-scope empty declaration, the `;;` of a stray semicolon or the `;` after a
   function's `}`, which clang reports as EmptyDecl, declares nothing */
int printf(const char *, ...);
;
static int n = 3;;
int twice(int v) { return v * 2; };
int main(void) {
    ;
    printf("%d %d\n", n, twice(n));
    return 0;
};
