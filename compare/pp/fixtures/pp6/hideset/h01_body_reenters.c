/* the invocation's hide set (macro name ∩ ')') must reach the body: k's name stays painted inside h's body */
#define k h(z)
#define h(x) x k
k
