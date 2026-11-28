/* clang and gcc disagree on __LINE__ in an argument of a call that spans two lines: clang reads the line of the `)`, gcc the line of the call's name */
#define F(x) x __LINE__
F(__LINE__
)
