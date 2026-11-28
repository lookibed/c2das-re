/* a painted (blue) token keeps its paint when an outer macro rescans it */
#define self self
#define pass(x) x
#define pass2(x) pass(x)
pass(self) pass2(self) pass(pass(self))
#define obj obj(1)
#define fn(x) obj x
fn(obj)
