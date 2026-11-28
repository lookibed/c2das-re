/* a record with an initializer holding an `offsetof`: Dumper A and the builder agree */
struct point {
    int x, y;
};

int main(void)
{
    struct point p = {1, (int)__builtin_offsetof(struct point, y)};
    return p.x - 1;
}
