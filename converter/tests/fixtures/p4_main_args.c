int printf(const char *, ...);
unsigned long strlen(const char *);

/* `main(argc, argv)`: the count, every argument after the program's name, the null that ends
   the vector, a write into an argument's bytes, which the program owns; argv[0] is the
   program's name, whose text differs between a native build and a conversion, so only its
   presence prints */
int main(int argc, char *argv[]) {
    printf("argc %d name %d\n", argc, argv[0] != 0 && strlen(argv[0]) > 0);
    for (int i = 1; i < argc; i++) {
        printf("argv[%d] = '%s' %lu\n", i, argv[i], strlen(argv[i]));
    }
    printf("end %d\n", argv[argc] == 0);
    if (argc > 1 && argv[1][0] != '\0') {
        argv[1][0] = 'X';
        printf("written %s\n", argv[1]);
    }
    return argc;
}
