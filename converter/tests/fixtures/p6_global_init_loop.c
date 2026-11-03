int printf(const char *, ...);
struct Menu { void (*go)(void); struct Menu *prev; int items; };
struct Menu *current;
void go_episode(void);
void go_self(void);
void go_read(void);
void go_sound(void);
void go_help(void);
void go_x(void);
void go_y(void);
/* a function value whose body takes the address of a later menu that points back */
struct Menu main_menu = { go_episode, 0, 3 };
struct Menu episode_menu = { 0, &main_menu, 4 };
void go_episode(void) { current = &episode_menu; }
/* a menu whose function takes its own address */
struct Menu self_menu = { go_self, 0, 1 };
void go_self(void) { current = &self_menu; }
/* a function value that reaches its menu through a call, reading it */
struct Menu read_menu = { go_read, 0, 6 };
static int read_items(void) { return read_menu.items; }
void go_read(void) { current = read_items() == 6 ? &read_menu : 0; }
/* the address link forward, the function link back */
extern struct Menu options_menu_fwd;
struct Menu sound_menu = { 0, &options_menu_fwd, 2 };
struct Menu options_menu_fwd = { go_sound, 0, 5 };
void go_sound(void) { current = &sound_menu; }
/* no cycle: the function reaches a menu that points nowhere */
struct Menu plain = { 0, 0, 7 };
struct Menu help_menu = { go_help, &plain, 8 };
void go_help(void) { current = &plain; }
/* two menus whose functions take each other's address: the first one stored ends the loop */
struct Menu x_menu = { go_x, 0, 10 };
struct Menu y_menu = { go_y, 0, 20 };
void go_x(void) { current = &y_menu; }
void go_y(void) { current = &x_menu; }
int main(void) {
    main_menu.go();
    printf("%d %d\n", current == &episode_menu, current->prev == &main_menu);
    self_menu.go();
    printf("%d %d\n", current == &self_menu, current->items);
    read_menu.go();
    printf("%d\n", current == &read_menu);
    options_menu_fwd.go();
    printf("%d %d\n", current == &sound_menu, current->prev->items);
    help_menu.go();
    printf("%d %d %d\n", current == &plain, help_menu.prev->items, main_menu.items + episode_menu.items);
    x_menu.go();
    y_menu.go();
    printf("%d %d\n", current == &x_menu, current->items + y_menu.items);
    return 0;
}
