/* an expression's type first used before the declaration that uses it: the builder interns it
   where the expression stands, as Dumper A does, so the whole tables agree */
int f(void)
{
    return (int)(char)1;
}

short s;
char c;
