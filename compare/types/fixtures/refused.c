/* a scalar-only unit the builder refuses: a wide string literal */
int main(void)
{
    return L"x"[0] - 120;
}
