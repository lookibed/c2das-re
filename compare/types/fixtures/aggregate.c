/* a record with an initializer: Dumper A types it, the builder refuses the `offsetof` in it until A.4 */
struct point {
    int x, y;
};

int main(void)
{
    struct point p = {1, (int)__builtin_offsetof(struct point, y)};
    return p.x - 1;
}
