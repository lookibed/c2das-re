/* # and ##: the spelling of a stringified argument, placemarkers, pastes that form every kind */
#define str(s) #s
#define xstr(s) str(s)
str( a  +  "b\n" 'c' '"' L"\\" ) str() str(  ) str(a
b) xstr(__LINE__) str(__LINE__)
#define cat(a,b) a##b
#define xcat(a,b) cat(a,b)
cat(1,) cat(,2) cat(,) cat(x,y) cat(+,+) cat(<<,=) cat(-,>) cat(%:,%:) cat(<,:)
cat(L, "s") cat(u8,"t") cat(L,'c') cat(.,5) cat(1,e) cat(1e,+) cat(0x,1F) cat(1.,e5)
#define xy 42
cat(x,y) xcat(x,y) cat(x y,z) cat(a,b c)
#define EMPTY
xstr(EMPTY) str(EMPTY) xstr(cat(x,)y)
