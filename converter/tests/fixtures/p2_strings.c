int printf(const char *, ...);
int sprintf(char *, const char *, ...);
unsigned long strlen(const char *);
char *strcpy(char *, const char *);
char *strncpy(char *, const char *, unsigned long);
char *strcat(char *, const char *);
int strcmp(const char *, const char *);
int strncmp(const char *, const char *, unsigned long);
char *strchr(const char *, int);
char *strrchr(const char *, int);
char *strstr(const char *, const char *);
void *memchr(const void *, int, unsigned long);
int atoi(const char *);
long atol(const char *);
int toupper(int);
int isdigit(int);
int isalpha(int);
static const char *greeting = "hello";
static char buf[16] = "abc";
static const char *const names[] = { "zero", "one", "", "three" };
static char empty[1] = "";
static int count_upper(const char *s) {
    int n = 0;
    while (*s) {
        if (isalpha(*s) && toupper(*s) == *s) n++;
        s++;
    }
    return n;
}
int main(void) {
    char local[32] = "";
    const char *e = "";
    char num[8] = "42";
    strcpy(local, greeting);
    strcat(local, ", ");
    strncpy(local + strlen(local), names[1], 3);
    local[strlen(local)] = '\0';
    printf("%s %d %d %d\n", local, (int) strlen(local), strcmp(local, "hello, one"), strncmp(buf, "abd", 2));
    printf("%d %d %c %s\n", (int) (strchr(local, ',') - local), (int) (strrchr(greeting, 'l') - greeting), *(char *) memchr(greeting, 'e', 5), strstr(local, "one"));
    printf("%d %d %d %d\n", atoi(num) + (int) atol("100"), count_upper("Hello World"), (int) sizeof("abc"), "abcdef"[2]);
    printf("[%s] %d %d %d %d\n", names[2], (int) strlen(e), (int) strlen(empty), e[0], (int) sizeof names / (int) sizeof names[0]);
    sprintf(local, "%d-%s", 7, buf);
    printf("%s %d %d\n", local, isdigit(num[0]) != 0, isdigit('x'));
    return (int) strlen(local);
}
