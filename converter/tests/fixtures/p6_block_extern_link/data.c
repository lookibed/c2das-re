int count = 3;
int table[] = {2, 4, 6, 8, 10};

int total(int n) {
    int s = 0;
    for (int i = 0; i < n; i++) {
        s += table[i];
    }
    return s;
}
