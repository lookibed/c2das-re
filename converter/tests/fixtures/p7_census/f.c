struct S {
    int x;
};

int e_run(void);

int f_id(int x) {
    return x;
}

int f_back(void) {
    int (*q)(void) = e_run;
    return q();
}
