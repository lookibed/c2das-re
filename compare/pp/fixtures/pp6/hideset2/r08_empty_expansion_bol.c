// r08 (H8): an empty expansion before a '#' on the same line, and before a directive on the next line
#define E
#define F()
int a; E # 7 "x.c"
int b E
#define X 1
X; F()
#define Y 2
Y;
E E # not_a_directive
