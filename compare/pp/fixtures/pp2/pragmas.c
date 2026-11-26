/* pragmas reach clang's output and PP.2's ledgers */
#pragma pack(push, 1)
struct packed { char c; int i; };
#pragma pack(pop)
#pragma weak weak_symbol
#pragma GCC visibility push(default)
int after_pragmas;
#
# /* the null directive */
int end_of_pragmas;
