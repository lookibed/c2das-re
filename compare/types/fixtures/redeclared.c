/* types a declaration interns that no rebuilt declaration names: a block typedef's type under a
   name that has an entry already, an array type a redeclaration completes; both tables agree */
typedef short T;
extern int a[];
int a[2];

void f(void)
{
    typedef long T;
}

int main(void)
{
    return 0;
}
