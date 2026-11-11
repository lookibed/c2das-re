/* P9.15: a long line breaks after an argument's comma or a binary operator, inside parentheses */
#include <stdio.h>

static int combine(int first_argument_value_long, int second_argument_value_long, int third_argument_value_long, int fourth_argument_value) {
    return first_argument_value_long * 1000 + second_argument_value_long * 100 + third_argument_value_long * 10 + fourth_argument_value;
}

static const int table_of_values[40] = { 101, 202, 303, 404, 505, 606, 707, 808, 909, 1010, 1111, 1212, 1313, 1414, 1515,
    1616, 1717, 1818, 1919, 2020, 2121, 2222, 2323, 2424, 2525, 2626, 2727, 2828, 2929, 3030, 3131, 3232, 3333, 3434, 3535,
    3636, 3737, 3838, 3939, 4040 };

static int check(int alpha_value, int beta_value, int gamma_value) {
    if (alpha_value > 0 && beta_value > 0 && gamma_value > 0 && alpha_value + beta_value > gamma_value && beta_value + gamma_value > alpha_value && alpha_value - gamma_value < beta_value)
        return combine(alpha_value - beta_value + gamma_value, beta_value * gamma_value - alpha_value, (alpha_value + beta_value) * (gamma_value - 1), table_of_values[alpha_value % 40] + table_of_values[beta_value % 40]);
    return -1;
}

int main(void) {
    printf("first value %d second value %d third value %d fourth value %d fifth value %d\n", check(3, 4, 5), check(5, 5, 5), check(1, 1, 9), combine(1, 2, 3, 4), table_of_values[39] - table_of_values[0] + combine(4, 3, 2, 1));
    return 0;
}
