/* Records one macro expansion defines share their expansion place: the oracle keys each by its
   spelling place too, so all three below are compared, the packed A2 among them. */

#define TWO struct A1 { char c; int x; }; struct __attribute__((packed)) A2 { char c; int x; };
TWO
struct U { char c; struct A2 a; };
