// main_web.c - the browser host of the C-native PureDOOM baseline (web/ARCHITECTURE.md section 6).
//
// Copyright (C) 2026 the c2das-re authors. This file is part of the web/ subtree of c2das-re,
// which links it with PureDOOM; it is free software under the GNU General Public License version 2,
// as published by the Free Software Foundation, the license of PureDOOM. It is distributed WITHOUT
// ANY WARRANTY; see PureDOOM's LICENSE for the details.
//
// The same host as web/puredoom/main_web.das, statement for statement, in C, so the original
// PureDOOM compiled by emscripten and the daslang conversion run under one harness: the same clocks,
// frame budgets, key table, checksum fold and output lines, which the same page reads.

#include <emscripten.h>
#include <GLES3/gl3.h>
#include <GLFW/glfw3.h>
#include <setjmp.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "DOOM.h"
#include "doomtype.h"
#include "tic_digest.h"

extern int gametic;
extern doom_boolean is_wiping_screen;
void D_Display(void);

#define DOOM_W 320
#define DOOM_H 200
#define TIMEDEMO_BUDGET_USEC 12000
#define MAX_FRAME_USEC 100000
// under -uncapped: 10 ms of renders between tics a frame, at most 60% of the last frame interval
#define UNCAPPED_BUDGET_USEC 10000

static GLFWwindow* window;
static GLuint program, vao, vbo, ebo, screen_tex;

static int timedemo, uncapped, running;
static int64_t virtual_usec, work_usec;
static double clock_base_ms;
static int64_t game_usec = 1000000, last_frame_usec;
static int exit_code;
static jmp_buf leave_frame;
static int frame_jump_ready;

// the fold of every `tic=` checksum line Doom prints (tic_digest.h)
static tic_digest_t tics = TIC_DIGEST_INIT;

static int64_t usec_now(void) { return (int64_t)((emscripten_get_now() - clock_base_ms) * 1000.0); }

static void virtual_gettime(int* sec, int* usec)
{
    *sec = (int)(virtual_usec / 1000000);
    *usec = (int)(virtual_usec % 1000000);
}

static void real_gettime(int* sec, int* usec)
{
    *sec = (int)(game_usec / 1000000);
    *usec = (int)(game_usec % 1000000);
}

static void host_print(const char* str)
{
    if (!tic_digest_piece(&tics, str))
        printf("%s", str);
}

static void report_timedemo(void)
{
    printf("host: timed %d gametics in %.6f s\n", gametic, (double)work_usec / 1000000.0);
    printf("host: %d checksum lines, digest %08x; wall %.3f s\n", tics.lines, tics.hash, (double)usec_now() / 1000000.0);
}

static void host_exit(int code)
{
    if (timedemo)
        report_timedemo();
    printf("host: Doom exited with %d\n", code);
    fflush(stdout);
    exit_code = code;
    running = 0;
    if (frame_jump_ready)
        longjmp(leave_frame, 1);
}

// GLFW key, Doom key: the same table as the das host
static const int KEYMAP[][2] = {
    {GLFW_KEY_LEFT, DOOM_KEY_LEFT_ARROW}, {GLFW_KEY_RIGHT, DOOM_KEY_RIGHT_ARROW},
    {GLFW_KEY_UP, DOOM_KEY_UP_ARROW}, {GLFW_KEY_DOWN, DOOM_KEY_DOWN_ARROW},
    {GLFW_KEY_ENTER, DOOM_KEY_ENTER}, {GLFW_KEY_ESCAPE, DOOM_KEY_ESCAPE},
    {GLFW_KEY_TAB, DOOM_KEY_TAB}, {GLFW_KEY_BACKSPACE, DOOM_KEY_BACKSPACE},
    {GLFW_KEY_SPACE, DOOM_KEY_SPACE}, {GLFW_KEY_PAUSE, DOOM_KEY_PAUSE},
    {GLFW_KEY_LEFT_CONTROL, DOOM_KEY_CTRL}, {GLFW_KEY_RIGHT_CONTROL, DOOM_KEY_CTRL},
    {GLFW_KEY_LEFT_SHIFT, DOOM_KEY_SHIFT}, {GLFW_KEY_RIGHT_SHIFT, DOOM_KEY_SHIFT},
    {GLFW_KEY_LEFT_ALT, DOOM_KEY_ALT}, {GLFW_KEY_RIGHT_ALT, DOOM_KEY_ALT},
    {GLFW_KEY_MINUS, DOOM_KEY_MINUS}, {GLFW_KEY_EQUAL, DOOM_KEY_EQUALS},
    {GLFW_KEY_COMMA, DOOM_KEY_COMMA}, {GLFW_KEY_PERIOD, DOOM_KEY_PERIOD},
    {GLFW_KEY_SLASH, DOOM_KEY_SLASH}, {GLFW_KEY_SEMICOLON, DOOM_KEY_SEMICOLON},
    {GLFW_KEY_APOSTROPHE, DOOM_KEY_APOSTROPHE},
    {GLFW_KEY_LEFT_BRACKET, DOOM_KEY_LEFT_BRACKET}, {GLFW_KEY_RIGHT_BRACKET, DOOM_KEY_RIGHT_BRACKET},
    {GLFW_KEY_F1, DOOM_KEY_F1}, {GLFW_KEY_F2, DOOM_KEY_F2}, {GLFW_KEY_F3, DOOM_KEY_F3},
    {GLFW_KEY_F4, DOOM_KEY_F4}, {GLFW_KEY_F5, DOOM_KEY_F5}, {GLFW_KEY_F6, DOOM_KEY_F6},
    {GLFW_KEY_F7, DOOM_KEY_F7}, {GLFW_KEY_F8, DOOM_KEY_F8}, {GLFW_KEY_F9, DOOM_KEY_F9},
    {GLFW_KEY_F10, DOOM_KEY_F10}, {GLFW_KEY_F11, DOOM_KEY_F11}, {GLFW_KEY_F12, DOOM_KEY_F12},
};

static unsigned char doom_down[256], doom_now[256];
static int mouse_down;

static void poll_keys(void)
{
    memset(doom_now, 0, sizeof doom_now);
    for (size_t i = 0; i < sizeof KEYMAP / sizeof KEYMAP[0]; i++)
        if (glfwGetKey(window, KEYMAP[i][0]) == GLFW_PRESS)
            doom_now[KEYMAP[i][1]] = 1;
    for (int i = 0; i < 26; i++)
        if (glfwGetKey(window, GLFW_KEY_A + i) == GLFW_PRESS)
            doom_now[DOOM_KEY_A + i] = 1;
    for (int i = 0; i < 10; i++)
        if (glfwGetKey(window, GLFW_KEY_0 + i) == GLFW_PRESS)
            doom_now[DOOM_KEY_0 + i] = 1;
    for (int k = 0; k < 256; k++) {
        if (doom_now[k] != doom_down[k]) {
            doom_down[k] = doom_now[k];
            if (doom_now[k])
                doom_key_down((doom_key_t)k);
            else
                doom_key_up((doom_key_t)k);
        }
    }
    int pressed = glfwGetMouseButton(window, GLFW_MOUSE_BUTTON_1) == GLFW_PRESS;
    if (pressed != mouse_down) {
        mouse_down = pressed;
        if (pressed)
            doom_button_down(DOOM_LEFT_BUTTON);
        else
            doom_button_up(DOOM_LEFT_BUTTON);
    }
}

static const char* VS = "#version 300 es\n"
                        "layout(location=0) in vec2 v_position;\n"
                        "layout(location=1) in vec2 v_texcoord;\n"
                        "out vec2 f_texcoord;\n"
                        "void main() { f_texcoord = v_texcoord; gl_Position = vec4(v_position, 0.0, 1.0); }\n";
static const char* FS = "#version 300 es\n"
                        "precision mediump float;\n"
                        "in vec2 f_texcoord;\n"
                        "uniform sampler2D f_tex;\n"
                        "out vec4 f_FragColor;\n"
                        "void main() { f_FragColor = texture(f_tex, f_texcoord); }\n";

static GLuint compile(GLenum type, const char* text)
{
    GLuint s = glCreateShader(type);
    glShaderSource(s, 1, &text, NULL);
    glCompileShader(s);
    return s;
}

static void create_gl_objects(void)
{
    static const float quad[] = {-1, 1, 0, 0, 1, 1, 1, 0, 1, -1, 1, 1, -1, -1, 0, 1};
    static const int indices[] = {0, 1, 2, 2, 3, 0};
    program = glCreateProgram();
    glAttachShader(program, compile(GL_VERTEX_SHADER, VS));
    glAttachShader(program, compile(GL_FRAGMENT_SHADER, FS));
    glLinkProgram(program);
    glGenVertexArrays(1, &vao);
    glBindVertexArray(vao);
    glGenBuffers(1, &vbo);
    glBindBuffer(GL_ARRAY_BUFFER, vbo);
    glBufferData(GL_ARRAY_BUFFER, sizeof quad, quad, GL_STATIC_DRAW);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 16, (void*)0);
    glEnableVertexAttribArray(1);
    glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 16, (void*)8);
    glGenBuffers(1, &ebo);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ebo);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, sizeof indices, indices, GL_STATIC_DRAW);
    glGenTextures(1, &screen_tex);
    glBindTexture(GL_TEXTURE_2D, screen_tex);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, DOOM_W, DOOM_H, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
}

static void draw_frame(void)
{
    const unsigned char* pixels = doom_get_framebuffer(4);
    glBindTexture(GL_TEXTURE_2D, screen_tex);
    glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, DOOM_W, DOOM_H, GL_RGBA, GL_UNSIGNED_BYTE, pixels);
    int fb_w, fb_h;
    glfwGetFramebufferSize(window, &fb_w, &fb_h);
    int w = fb_w, h = fb_w * 3 / 4;
    if (h > fb_h) {
        h = fb_h;
        w = fb_h * 4 / 3;
    }
    glViewport(0, 0, fb_w, fb_h);
    glClearColor(0, 0, 0, 1);
    glClear(GL_COLOR_BUFFER_BIT);
    glViewport((fb_w - w) / 2, (fb_h - h) / 2, w, h);
    glUseProgram(program);
    glActiveTexture(GL_TEXTURE0);
    glUniform1i(glGetUniformLocation(program, "f_tex"), 0);
    glBindVertexArray(vao);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ebo);
    glDrawElements(GL_TRIANGLES, 6, GL_UNSIGNED_INT, 0);
    glfwSwapBuffers(window);
}

static int64_t stats_start;
static int stats_tic, stats_frames, stats_renders;

static void render_between_tics(void)
{
    if (!is_wiping_screen) {
        D_Display();
        stats_renders++;
    }
}

static void report_stats(void)
{
    int64_t now = usec_now();
    if (now - stats_start < 1000000)
        return;
    int tics = gametic - stats_tic;
    printf("host: stats %d %d %d %.3f\n", stats_frames, tics, stats_renders + tics, (double)(now - stats_start) / 1000000.0);
    stats_start = now;
    stats_tic = gametic;
    stats_frames = 0;
    stats_renders = 0;
}

static void update(void)
{
    if (!running) {
        emscripten_cancel_main_loop();
        return;
    }
    glfwPollEvents();
    frame_jump_ready = 1;
    if (setjmp(leave_frame) == 0) {
        if (timedemo) {
            int64_t frame_start = usec_now(), now = frame_start;
            while (running && now - frame_start < TIMEDEMO_BUDGET_USEC) {
                doom_force_update();
                virtual_usec += 1000000 / 35;
                if (uncapped)
                    render_between_tics();
                int64_t after = usec_now();
                work_usec += after - now;
                now = after;
            }
        } else {
            int64_t now = usec_now(), interval = now - last_frame_usec;
            game_usec += interval < MAX_FRAME_USEC ? interval : MAX_FRAME_USEC;
            last_frame_usec = now;
            poll_keys();
            doom_update();
            if (uncapped) {
                int64_t budget = interval * 6 / 10 < UNCAPPED_BUDGET_USEC ? interval * 6 / 10 : UNCAPPED_BUDGET_USEC;
                while (running && usec_now() - now < budget)
                    render_between_tics();
            }
        }
    }
    frame_jump_ready = 0;
    draw_frame();
    stats_frames++;
    report_stats();
    if (!running) {
        emscripten_cancel_main_loop();
        glfwDestroyWindow(window);
        glfwTerminate();
    }
}

int main(int argc, char** argv)
{
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-timedemo") == 0)
            timedemo = 1;
        if (strcmp(argv[i], "-uncapped") == 0)
            uncapped = 1;
    }
    if (!glfwInit()) {
        fprintf(stderr, "can't init glfw\n");
        return 1;
    }
    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 0);
    window = glfwCreateWindow(960, 720, "PureDOOM in C", NULL, NULL);
    if (!window) {
        fprintf(stderr, "can't create window\n");
        return 1;
    }
    glfwMakeContextCurrent(window);
    create_gl_objects();
    doom_set_print(host_print);
    doom_set_exit(host_exit);
    clock_base_ms = emscripten_get_now();
    doom_set_gettime(timedemo ? virtual_gettime : real_gettime);
    running = 1;
    frame_jump_ready = 1;
    if (setjmp(leave_frame) == 0)
        doom_init(argc, argv, 0);
    frame_jump_ready = 0;
    last_frame_usec = usec_now();
    stats_start = last_frame_usec;
    emscripten_set_main_loop(update, 0, 0);
    return exit_code;
}
