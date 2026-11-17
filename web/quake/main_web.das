options gen2
options indenting = 4
options stack = 8388608
options strict_aliasing = false

//! quakegeneric's browser host (web/ARCHITECTURE.md section 7): the converted engine
//! (c2das-ports quakegeneric/readable) driven by daslang's web lifecycle, beside the generated entry
//! `quake_entry.das`, whose platform layer (`qg_platform.das.inc`: frame hashes, the palette, no
//! input) it reuses. Each frame draws the engine's 320x240 8-bit screen (`vid.buffer`) through the
//! palette as one texture; keys go to the engine's own `Key_Event`, which its null input layer never
//! calls. Shareware Quake's `id1/pak0.pak` sits under the base directory `/q`.
//!
//! - play: each frame runs `QG_Tick` with the real time since the last, at most 0.1 s.
//! - timedemo (`-timedemo`): `+timedemo demo1`, each tick 1/64 s as the native entry runs it, as many
//!   ticks a frame as fit in 12 ms. The host prints the frames the demo took and the seconds spent in
//!   the ticks, and once the engine has drawn 100 frames without the console, the digest of their
//!   hashes in the native entry's `frame[i]=v` lines, which the page compares with the native run's.

require ../c_types.das
require ../upstream/quakegeneric/source/chase_cluster.das
require ../upstream/quakegeneric/source/quakegeneric.das
require ../upstream/quakegeneric/source/common_h.das
require ../upstream/quakegeneric/source/client_h.das
require ../upstream/quakegeneric/source/vid_h.das
require crt
require c_runtime/c_args
require c_runtime/cstr
require c_runtime/printf
require glfw/glfw_boost
require opengl/opengl_boost
require glsl/glsl_opengl
require daslib/safe_addr
require daslib/fio
require math

var @in @location v_position : float2
var @in @location v_texcoord : float2
var @inout f_texcoord : float2
var @uniform f_tex : sampler2D
var @out f_FragColor : float4

[vertex_program]
def vs_main {
    f_texcoord = v_texcoord
    gl_Position = float4(v_position, 0.0, 1.0)
}

[fragment_program]
def fs_main {
    f_FragColor = texture(f_tex, f_texcoord)
}

[vertex_buffer]
struct Vertex {
    xy : float2
    uv : float2
}

let private QUAD = [Vertex(
    xy = float2(-1.0, 1.0), uv = float2(0.0, 0.0)), Vertex(
    xy = float2(1.0, 1.0), uv = float2(1.0, 0.0)), Vertex(
    xy = float2(1.0, -1.0), uv = float2(1.0, 1.0)), Vertex(
    xy = float2(-1.0, -1.0), uv = float2(0.0, 1.0)
)]

let private QUAD_INDICES = fixed_array<int>(0, 1, 2, 2, 3, 0)

let private SCREEN_W = 320
let private SCREEN_H = 240
let private TICK_SECONDS = 1.0lf / 64.0lf          // the native entry's tick
let private TIMEDEMO_BUDGET_USEC = 12000l
let private MAX_FRAME_SECONDS = 0.1lf
let private CHECKED_FRAMES = 100                    // the frames the native entry hashes

var private window : GLFWwindow?
var private program : uint
var private vao : uint
var private vbo : uint
var private ebo : uint
var private screen_tex : uint
var private rgba : array<uint8>

var private timedemo = false
var private timedemo_seen = false
var private reported = false
var private hashed = false
var private running = false
var private clock_base : int64 = 0l
var private last_frame_usec : int64 = 0l
var private work_usec : int64 = 0l
var private quake_argv : uint8? [6]

def private usec_now : int64 => get_time_nsec(clock_base) / 1000l

// Quake's key codes (keys.h): the ones its default bindings and menus read
let private KEYMAP = [
    (GLFW_KEY_TAB, 9), (GLFW_KEY_ENTER, 13), (GLFW_KEY_ESCAPE, 27), (GLFW_KEY_SPACE, 32),
    (GLFW_KEY_BACKSPACE, 127), (GLFW_KEY_UP, 128), (GLFW_KEY_DOWN, 129), (GLFW_KEY_LEFT, 130),
    (GLFW_KEY_RIGHT, 131), (GLFW_KEY_LEFT_ALT, 132), (GLFW_KEY_RIGHT_ALT, 132),
    (GLFW_KEY_LEFT_CONTROL, 133), (GLFW_KEY_RIGHT_CONTROL, 133), (GLFW_KEY_LEFT_SHIFT, 134),
    (GLFW_KEY_RIGHT_SHIFT, 134), (GLFW_KEY_F1, 135), (GLFW_KEY_F2, 136), (GLFW_KEY_F3, 137),
    (GLFW_KEY_F4, 138), (GLFW_KEY_F5, 139), (GLFW_KEY_F6, 140), (GLFW_KEY_F7, 141), (GLFW_KEY_F8, 142),
    (GLFW_KEY_F9, 143), (GLFW_KEY_F10, 144), (GLFW_KEY_F11, 145), (GLFW_KEY_F12, 146),
    (GLFW_KEY_INSERT, 147), (GLFW_KEY_DELETE, 148), (GLFW_KEY_PAGE_DOWN, 149), (GLFW_KEY_PAGE_UP, 150),
    (GLFW_KEY_HOME, 151), (GLFW_KEY_END, 152), (GLFW_KEY_PAUSE, 255), (GLFW_KEY_MINUS, 45),
    (GLFW_KEY_EQUAL, 61), (GLFW_KEY_GRAVE_ACCENT, 96), (GLFW_KEY_SLASH, 47), (GLFW_KEY_COMMA, 44),
    (GLFW_KEY_PERIOD, 46)
]

var private quake_down : bool[256]
var private quake_now : bool[256]
var private mouse_down = false

def private post_key(key : int; down : bool) {
    var k = key
    Key_Event(k, down ? qboolean._c_true : qboolean._c_false)
}

// Quake's key state from GLFW's: one state per Quake key (left and right Ctrl are one)
def private poll_keys {
    for (k in range(256)) {
        quake_now[k] = false
    }
    for (row in KEYMAP) {
        if (glfwGetKey(window, row._0) == GLFW_PRESS) {
            quake_now[row._1] = true
        }
    }
    for (i in range(26)) {
        if (glfwGetKey(window, GLFW_KEY_A + i) == GLFW_PRESS) {
            quake_now[97 + i] = true
        }
    }
    for (i in range(10)) {
        if (glfwGetKey(window, GLFW_KEY_0 + i) == GLFW_PRESS) {
            quake_now[48 + i] = true
        }
    }
    for (k in range(256)) {
        if (quake_now[k] != quake_down[k]) {
            quake_down[k] = quake_now[k]
            post_key(k, quake_now[k])
        }
    }
    let pressed = glfwGetMouseButton(window, GLFW_MOUSE_BUTTON_1) == GLFW_PRESS
    if (pressed != mouse_down) {
        mouse_down = pressed
        post_key(200, pressed)                       // K_MOUSE1
    }
}

def private create_gl_objects {
    program = create_shader_program(@@vs_main, @@fs_main)
    glGenVertexArrays(1, safe_addr(vao))
    glBindVertexArray(vao)
    glGenBuffers(1, safe_addr(vbo))
    glBindBuffer(GL_ARRAY_BUFFER, vbo)
    glBufferData(GL_ARRAY_BUFFER, QUAD, GL_STATIC_DRAW)
    bind_vertex_buffer(null, type<Vertex>)
    glGenBuffers(1, safe_addr(ebo))
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ebo)
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, QUAD_INDICES, GL_STATIC_DRAW)
    glGenTextures(1, safe_addr(screen_tex))
    glBindTexture(GL_TEXTURE_2D, screen_tex)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, int(GL_NEAREST))
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, int(GL_NEAREST))
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, int(GL_CLAMP_TO_EDGE))
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, int(GL_CLAMP_TO_EDGE))
    glTexImage2D(GL_TEXTURE_2D, 0, int(GL_RGBA), SCREEN_W, SCREEN_H, 0, GL_RGBA, GL_UNSIGNED_BYTE, null)
}

// the engine's screen through its palette, letterboxed to 4:3
def private draw_frame {
    let pixels = vid.buffer
    if (pixels != null) {
        for (i in range(SCREEN_W * SCREEN_H)) {
            let c = int(unsafe(pixels[i])) * 3
            rgba[i * 4] = qg_palette[c]
            rgba[i * 4 + 1] = qg_palette[c + 1]
            rgba[i * 4 + 2] = qg_palette[c + 2]
            rgba[i * 4 + 3] = 255u8
        }
        glBindTexture(GL_TEXTURE_2D, screen_tex)
        glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, SCREEN_W, SCREEN_H, GL_RGBA, GL_UNSIGNED_BYTE, unsafe(addr(rgba[0])))
    }
    var fb_w, fb_h : int
    glfwGetFramebufferSize(window, fb_w, fb_h)
    var w = fb_w
    var h = fb_w * 3 / 4
    if (h > fb_h) {
        h = fb_h
        w = fb_h * 4 / 3
    }
    glViewport(0, 0, fb_w, fb_h)
    glClearColor(0.0, 0.0, 0.0, 1.0)
    glClear(GL_COLOR_BUFFER_BIT)
    glViewport((fb_w - w) / 2, (fb_h - h) / 2, w, h)
    glUseProgram(program)
    f_tex := screen_tex
    vs_main_bind_uniform(program)
    fs_main_bind_uniform(program)
    glBindVertexArray(vao)
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ebo)
    glDrawElements(GL_TRIANGLES, 6, GL_UNSIGNED_INT, null)
    glfwSwapBuffers(window)
}

// the first 100 frames without the console: their hashes as the native entry prints them, folded
// with FNV-1a 32 over every `frame[i]=v` line, newline included
def private report_hashes {
    var digest = 2166136261u
    for (i in range(CHECKED_FRAMES)) {
        let line = "frame[{i}]={qg_frame_hash[i]}\n"
        for (c in line) {
            digest ^= uint(c)
            digest *= 16777619u
        }
    }
    printf(cstr("host: %d frame hashes, digest %08x\n"), CHECKED_FRAMES, digest)
}

// the counters of the page's fps line, as the PureDOOM host prints them: frames presented, frames
// Quake drew, frames rendered (the same)
var private stats_start : int64 = 0l
var private stats_frames = 0
var private stats_drawn = 0

def private report_stats {
    let now = usec_now()
    if (now - stats_start < 1000000l) {
        return
    }
    let drawn = host_framecount - stats_drawn
    printf(cstr("host: stats %d %d %d %.3f\n"), stats_frames, drawn, drawn, double(now - stats_start) / 1000000.0lf)
    stats_start = now
    stats_drawn = host_framecount
    stats_frames = 0
}

def private timedemo_step {
    let frame_start = usec_now()
    var now = frame_start
    while (running && now - frame_start < TIMEDEMO_BUDGET_USEC) {
        QG_Tick(TICK_SECONDS)
        let after = usec_now()
        work_usec += after - now
        now = after
        if (!hashed && qg_frame_count >= CHECKED_FRAMES) {
            hashed = true
            report_hashes()
        }
        if (cls.timedemo != qboolean._c_false && !timedemo_seen) {
            timedemo_seen = true
            work_usec = 0l
        }
        if (timedemo_seen && cls.timedemo == qboolean._c_false && !reported) {
            reported = true
            // CL_FinishTimeDemo's own count: from its start frame, the first frame not counted
            printf(cstr("host: timed %d frames in %.6f s\n"), host_framecount - cls.td_startframe - 1, double(work_usec) / 1000000.0lf)
            printf(cstr("host: Quake finished the timedemo\n"))
            running = false
        }
    }
}

[export]
def init {
    c_runtime_init("quake_web")
    for (arg in get_command_line_arguments()) {
        if (arg == "-timedemo") {
            timedemo = true
        }
    }
    rgba |> resize(SCREEN_W * SCREEN_H * 4)
    if (glfwInit() == 0) {
        panic("can't init glfw")
    }
    glfwInitOpenGL(3, 3)
    window = glfwCreateWindow(960, 720, "quakegeneric in daslang", null, null)
    if (window == null) {
        panic("can't create window")
    }
    glfwMakeContextCurrent(window)
    create_gl_objects()
    clock_base = ref_time_ticks()
    quake_argv[0] = cstr("quake")
    quake_argv[1] = cstr("-basedir")
    quake_argv[2] = cstr("/q")
    var argc = 3
    if (timedemo) {
        quake_argv[3] = cstr("+timedemo")
        quake_argv[4] = cstr("demo1")
        argc = 5
    }
    quake_argv[argc] = null
    QG_Create(argc, unsafe(addr(quake_argv[0])))
    running = true
    last_frame_usec = usec_now()
    stats_start = last_frame_usec
}

[export]
def update : bool {
    if (!running) {
        return false
    }
    glfwPollEvents()
    if (timedemo) {
        timedemo_step()
    } else {
        let now = usec_now()
        let dt = min(double(now - last_frame_usec) / 1000000.0lf, MAX_FRAME_SECONDS)
        last_frame_usec = now
        poll_keys()
        QG_Tick(dt)
    }
    draw_frame()
    stats_frames++
    report_stats()
    return running
}

[export]
def shutdown {
    if (window != null) {
        glfwDestroyWindow(window)
        window = null
    }
    glfwTerminate()
}

// the desktop driver of the same lifecycle
[export]
def main {
    init()
    while (update() && glfwWindowShouldClose(window) == 0) {
        pass
    }
    shutdown()
}
