/* a pragma clang -E keeps: the preprocessor's ledger takes it, and the declarations around it parse */
int before;
#pragma pack(1)
int after;
#pragma GCC diagnostic ignored "-Wunused"
int last(void);
