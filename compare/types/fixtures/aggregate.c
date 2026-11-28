/* a record: Dumper A types it, the builder refuses it until the Aggregates phase */
struct point {
    int x, y;
};

int main(void)
{
    struct point p = {1, 2};
    return p.x - 1;
}
