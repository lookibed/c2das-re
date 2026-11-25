/* <math.h> of the own libc header set (frontend/include/ARCHITECTURE.md). */
#ifndef _MATH_H
#define _MATH_H

#define HUGE_VAL (__builtin_huge_val ())
#define HUGE_VALF (__builtin_huge_valf ())
#define signbit(x) __builtin_signbit (x)

#define M_E 2.7182818284590452354
#define M_LOG2E 1.4426950408889634074
#define M_LOG10E 0.43429448190325182765
#define M_LN2 0.69314718055994530942
#define M_LN10 2.30258509299404568402
#define M_PI 3.14159265358979323846
#define M_PI_2 1.57079632679489661923
#define M_PI_4 0.78539816339744830962
#define M_1_PI 0.31830988618379067154
#define M_2_PI 0.63661977236758134308
#define M_2_SQRTPI 1.12837916709551257390
#define M_SQRT2 1.41421356237309504880
#define M_SQRT1_2 0.70710678118654752440

double acos(double);
double asin(double);
double atan(double);
double atan2(double, double);
double cos(double);
double sin(double);
double tan(double);
double exp(double);
double expm1(double);
double frexp(double, int *);
double ldexp(double, int);
double log(double);
double log10(double);
double log1p(double);
double log2(double);
double modf(double, double *);
double cbrt(double);
double fabs(double);
double hypot(double, double);
double pow(double, double);
double sqrt(double);
double erf(double);
double erfc(double);
double lgamma(double);
double tgamma(double);
double ceil(double);
double floor(double);
double round(double);
double trunc(double);
double fmod(double, double);
float fmodf(float, float);
double remainder(double, double);
double copysign(double, double);
double nextafter(double, double);
double fma(double, double, double);

#endif
