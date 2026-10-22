/* the declarations p5_project_header.c takes from a header of its own folder: a header under the
   main file's directory belongs to the program, so each of these converts with the file */
#ifndef P5_PROJECT_HEADER_H
#define P5_PROJECT_HEADER_H

#define SCALE 3
#define SCALED(x) ((x) * SCALE)

enum shape { CIRCLE, SQUARE = 4, TRIANGLE };

struct point {
    int x;
    int y;
};

typedef struct point point_t;

typedef struct {
    enum shape kind;
    point_t corner;
    const char *name;
} figure;

int area(const figure *f);
extern int figures_made;

static int clamp(int v, int lo, int hi) {
    return v < lo ? lo : v > hi ? hi : v;
}

static const int weights[4] = {1, 2, 4, 8};

#endif
