/* a record with an initializer: Dumper A types it, the builder refuses its initializer until A.3 */
struct point {
    int x, y;
};

int main(void)
{
    struct point p = {1, 2};
    return p.x - 1;
}
