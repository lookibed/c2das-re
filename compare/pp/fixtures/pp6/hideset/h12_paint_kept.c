/* a painted token keeps its paint through an outer rescan: a lost paint expands `self` again */
#define self self tail
#define pass(x) x
#define pass2(x) pass(x)
self pass(self) pass2(self) pass(pass(self))
