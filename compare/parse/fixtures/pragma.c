/* pragmas clang -E keeps that change no C-IR: the preprocessor's ledger takes them, and the declarations around them parse */
int before;
#pragma GCC diagnostic push
int after;
#pragma GCC diagnostic ignored "-Wunused"
int last(void);
