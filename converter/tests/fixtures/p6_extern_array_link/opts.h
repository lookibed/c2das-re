/* the arrays every unit declares without a length; data.c defines them */
struct opt {
    const char *name;
    int value;
};

extern struct opt opts[];
extern int table[];
extern int grid[][3];

int total(int n);
int *slot(int k);
int whole(void);
