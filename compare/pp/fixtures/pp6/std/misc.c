/* digraphs, line splices, comments, UCNs, pp-numbers, character constants in #if, #elif chains, #error not taken */
%:define DG(x) %:x
DG(a) <: :> <% %> %:%:
#def\
ine SPLICED 1 + \
  2
int s = SPLICED;
int cm = 1 /* a */ + /* b
 c */ 2 // d \
 e
 ;
int pn = 0x1.fp3 + 1e+5 + 1.e-2f + .5L + 0b101 + 1'000 + 12_km + 0x1E+1 + 1.2.3.4e+x;
#if 0
#error not taken
#elif 0
# unknown directive in a skipped group
#elif 1
int elif_ok;
#else
#error not taken either
#endif
#if 0
'unterminated
#endif
#ifndef NOTDEF
int ifndef_ok;
#endif
#define EMPTY
EMPTY # define NOT_A_DIRECTIVE
int u = Ábc + café;
