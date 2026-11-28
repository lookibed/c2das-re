/* an aggregate unit the builder types byte for byte: an aligned record */
struct P { char c; } __attribute__((__aligned__(8)));
struct P gp;
int main(void)
{
    return gp.c;
}
