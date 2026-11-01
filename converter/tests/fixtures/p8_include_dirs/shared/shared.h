/* the record and the prototypes p8_include_dirs shares across its folders */
#ifndef SHARED_H
#define SHARED_H

#define SCALE(x) ((x) * 10)

struct pair {
    int a;
    int b;
};

struct pair make_pair(int a, int b);
int pair_sum(const struct pair *p);

#endif
