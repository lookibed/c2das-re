#include <stdlib.h>
/* every feature the switch census counts, one function each */
enum color { RED, GREEN, BLUE };

int plain(int x) {
  switch (x) {
  case 1: return 10;
  case 2:
  case 3: return 20;
  case 4: (void)0;
  case 5: return 30;
  default: return 0;
  }
}

int by_enum(enum color c) {
  switch (c) {
  case RED: return 1;
  default: return 9;
  case BLUE: return 3;
  }
}

int by_char(int c) {
  switch (c) {
  case 'a': return 1;
  case 'b': return 2;
  }
  return 0;
}

int by_bool(_Bool b) {
  switch (b) {
  case 0: return 1;
  default: return 2;
  }
}

int dense(unsigned char op) {
  switch (op) {
  case 0: return 1;
  case 1: return 2;
  case 2: return 3;
  case 3: return 4;
  case 4: return 5;
  case 5: return 6;
  case 6: return 7;
  case 9: return 8;
  }
  return 0;
}

int falls(int x) {
  int n = 0;
  switch (x) {
  case 1: n++;
  case 2: n += 2; break;
  case 3: n = 7;
  }
  return n;
}

int breaks(int x) {
  int n = 0;
  switch (x) {
  case 1:
    for (;;) { if (++n > 3) break; }
    break;
  case 2:
    if (n) break;
    n = 5;
    break;
  }
  return n;
}

int cross(int x) {
  int n = 0;
  switch (x) {
  case 1: n = 1; goto shared;
  case 2: n = 2; break;
  case 3: n = 3;
  shared: n *= 3; break;
  }
  return n;
}

int entered(int x) {
  int n = 0;
  if (x > 9) goto inside;
  switch (x) {
  case 1: n = 1; break;
  case 2:
  inside: n = 2; break;
  }
  return n;
}

int leaves(int x) {
  switch (x) {
  case 1: goto out;
  default: return 1;
  }
out:
  return 2;
}

int decl_used(int x) {
  switch (x) {
  case 1:;
    int y = 4;
    return y;
  case 2:
    y = 5;
    return y;
  }
  return 0;
}

int decl_unused(int x) {
  switch (x) {
  case 1:;
    int y = x;
    return y;
  case 2: return 0;
  }
  return 1;
}

int continues(int n) {
  int s = 0;
  for (int i = 0; i < n; i++) {
    switch (i) {
    case 1: continue;
    case 2: s += 2; break;
    }
    s++;
  }
  return s;
}

int duff(int n) {
  int s = 0;
  switch (n & 1) {
  case 0: do { s++;
  case 1: s++;
          } while (--n > 0);
  }
  return s;
}

int stops(int x) {
  switch (x) {
  case 1: abort();
  case 2: for (;;) { x++; }
  case 3: if (x) return 1; else return 2;
  case 4: switch (x) { default: return 3; }
  default: return 0;
  }
}

int nested(int x, int y) {
  switch (x) {
  case 1:
    switch (y) {
    case 1: x++;
    case 2: x++; break;
    }
    break;
  case 2: return 0;
  }
  return x;
}

int to_break(int x) {
  int n = 0;
  switch (x) {
  case 1: n = 1;
  case 2: ;
  default: break;
  }
  return n;
}

int main(void) { return 0; }
