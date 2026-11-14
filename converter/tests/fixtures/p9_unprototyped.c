#include <stdio.h>

/* unprototyped function pointers (Doom's `actionf_v`, Quake's `void (*procedure)()`): a function
   declared without a prototype and named before its definition has the type `void ()` there,
   which is reinterpreted from the definition's; a call with arguments through a `T (*)()` calls
   the function the promoted argument types spell, the C call ABI */
struct mobj {
    int health;
};

typedef void (*action_v)();
typedef void (*action_p1)(void *);

typedef union {
    action_v acv;
    action_p1 acp1;
} action_t;

typedef struct {
    int sprite;
    action_t action;
} state_t;

void A_Hurt();
void A_Heal();

state_t states[3] = {{0, {A_Hurt}}, {1, {A_Heal}}, {2, {0}}};

void A_Hurt(struct mobj *m) {
    m->health -= 10;
}

void A_Heal(struct mobj *m) {
    m->health += 3;
}

static void add_scaled(int *total, int by, double scale) {
    *total += (int) (by * scale);
}

typedef struct {
    void (*procedure)();
    void *arg;
} poll_t;

int main(void) {
    struct mobj m = {100};
    for (int i = 0; states[i].action.acv; i++) {
        states[i].action.acp1(&m);
    }
    int total = 1;
    void (*step)() = (void (*)()) add_scaled;
    char small = 5;
    float half = 0.5f;
    step(&total, small, half);
    poll_t poll = {(void (*)()) A_Heal, &m};
    poll.procedure(poll.arg);
    printf("%d %d\n", m.health, total);
    return 0;
}
