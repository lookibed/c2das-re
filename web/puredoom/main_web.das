options gen2
options indenting = 4
options stack = 8388608
options strict_aliasing = false

//! PureDOOM's browser host: the converted port (puredoom-readable/processed) driven the way daslang's
//! web lifecycle drives a cross-compiled program. The browser calls `init` once, then `update` on every
//! animation frame until it returns false; `main` is the desktop driver of the same three functions.
//! Each frame draws Doom's 320x200 palettized framebuffer, expanded to RGBA by `doom_get_framebuffer`,
//! as one texture on a quad; the keyboard and the left mouse button are polled through GLFW and
//! posted as Doom key and button events.
//!
//! Two modes, chosen by the program arguments:
//! - play (no `-timedemo`): Doom runs on the real clock, `doom_update` catches up to 35 tics a second.
//! - timedemo (`-timedemo demoN`): Doom runs on a virtual clock that advances one tic per
//!   `doom_force_update`, exactly as the native host `doom_main.das` does, so the tic checksums are
//!   the native ones; each frame runs updates for a fixed budget of milliseconds and then draws once.
//!   When the demo ends Doom exits; the host prints the tics, the seconds spent inside the updates and
//!   a digest of the checksum lines, and stops.

require DOOM_cluster
require DOOM_h
require crt
require c_runtime/c_args
require c_runtime/cstr
require c_runtime/enum_from_int
require c_runtime/printf
require c_runtime/setjmp
require tic_digest
require doom_synth
require doom_midi
require sounds
require sounds_h
require audio/audio_boost
require daslib/jobque_boost
require glfw/glfw_boost
require opengl/opengl_boost
require glsl/glsl_opengl
require daslib/safe_addr
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

let private DOOM_W = 320
let private DOOM_H = 200
// the timedemo's share of a 60 Hz frame spent in updates before the frame is drawn
let private TIMEDEMO_BUDGET_USEC = 12000l
// play mode's game clock advances by the frame's real time, at most this much: a tab the browser
// hid stops its animation frames, and on return Doom catches up 1/10 s, not every tic it missed
let private MAX_FRAME_USEC = 100000l
// under `-uncapped`, the time an animation frame spends rendering frames beyond the tics' own: 10 ms,
// at most 60% of the last frame interval (a display above 100 Hz has shorter frames)
let private UNCAPPED_BUDGET_USEC = 10000l

var private window : GLFWwindow?
var private program : uint
var private vao : uint
var private vbo : uint
var private ebo : uint
var private screen_tex : uint

var private timedemo = false
// `-uncapped`: frames rendered as fast as the frame budget allows, tics still 35 a second (section 3)
var private uncapped = false
var private running = false
var private virtual_usec : int64 = 0l
var private work_usec : int64 = 0l
var private clock_base : int64 = 0l
// play mode's clock; it starts at 1 s because I_GetTime takes its base second from the first
// nonzero second it reads
var private game_usec : int64 = 1000000l
var private last_frame_usec : int64 = 0l
var private exit_code = 0
var private leave_frame : CJmpBuf

// the fold of every `tic=` checksum line Doom prints (tic_digest.das)
var private tics = TicDigest()

// GLFW key, Doom key: the keys Doom's defaults and menus read
let private KEYMAP = [
    (GLFW_KEY_LEFT, int(doom_key_t.DOOM_KEY_LEFT_ARROW)), (GLFW_KEY_RIGHT, int(doom_key_t.DOOM_KEY_RIGHT_ARROW)),
    (GLFW_KEY_UP, int(doom_key_t.DOOM_KEY_UP_ARROW)), (GLFW_KEY_DOWN, int(doom_key_t.DOOM_KEY_DOWN_ARROW)),
    (GLFW_KEY_ENTER, int(doom_key_t.DOOM_KEY_ENTER)), (GLFW_KEY_ESCAPE, int(doom_key_t.DOOM_KEY_ESCAPE)),
    (GLFW_KEY_TAB, int(doom_key_t.DOOM_KEY_TAB)), (GLFW_KEY_BACKSPACE, int(doom_key_t.DOOM_KEY_BACKSPACE)),
    (GLFW_KEY_SPACE, int(doom_key_t.DOOM_KEY_SPACE)), (GLFW_KEY_PAUSE, int(doom_key_t.DOOM_KEY_PAUSE)),
    (GLFW_KEY_LEFT_CONTROL, int(doom_key_t.DOOM_KEY_CTRL)), (GLFW_KEY_RIGHT_CONTROL, int(doom_key_t.DOOM_KEY_CTRL)),
    (GLFW_KEY_LEFT_SHIFT, int(doom_key_t.DOOM_KEY_SHIFT)), (GLFW_KEY_RIGHT_SHIFT, int(doom_key_t.DOOM_KEY_SHIFT)),
    (GLFW_KEY_LEFT_ALT, int(doom_key_t.DOOM_KEY_ALT)), (GLFW_KEY_RIGHT_ALT, int(doom_key_t.DOOM_KEY_ALT)),
    (GLFW_KEY_MINUS, int(doom_key_t.DOOM_KEY_MINUS)), (GLFW_KEY_EQUAL, int(doom_key_t.DOOM_KEY_EQUALS)),
    (GLFW_KEY_COMMA, int(doom_key_t.DOOM_KEY_COMMA)), (GLFW_KEY_PERIOD, int(doom_key_t.DOOM_KEY_PERIOD)),
    (GLFW_KEY_SLASH, int(doom_key_t.DOOM_KEY_SLASH)), (GLFW_KEY_SEMICOLON, int(doom_key_t.DOOM_KEY_SEMICOLON)),
    (GLFW_KEY_APOSTROPHE, int(doom_key_t.DOOM_KEY_APOSTROPHE)),
    (GLFW_KEY_LEFT_BRACKET, int(doom_key_t.DOOM_KEY_LEFT_BRACKET)),
    (GLFW_KEY_RIGHT_BRACKET, int(doom_key_t.DOOM_KEY_RIGHT_BRACKET)),
    (GLFW_KEY_F1, int(doom_key_t.DOOM_KEY_F1)), (GLFW_KEY_F2, int(doom_key_t.DOOM_KEY_F2)),
    (GLFW_KEY_F3, int(doom_key_t.DOOM_KEY_F3)), (GLFW_KEY_F4, int(doom_key_t.DOOM_KEY_F4)),
    (GLFW_KEY_F5, int(doom_key_t.DOOM_KEY_F5)), (GLFW_KEY_F6, int(doom_key_t.DOOM_KEY_F6)),
    (GLFW_KEY_F7, int(doom_key_t.DOOM_KEY_F7)), (GLFW_KEY_F8, int(doom_key_t.DOOM_KEY_F8)),
    (GLFW_KEY_F9, int(doom_key_t.DOOM_KEY_F9)), (GLFW_KEY_F10, int(doom_key_t.DOOM_KEY_F10)),
    (GLFW_KEY_F11, int(doom_key_t.DOOM_KEY_F11)), (GLFW_KEY_F12, int(doom_key_t.DOOM_KEY_F12))
]

// the pressed state of each KEYMAP row, plus letters, digits and the left mouse button
var private doom_down : bool[256]
var private doom_now : bool[256]
var private mouse_down = false

def private virtual_gettime(var sec : int?; var usec : int?) {
    *sec = int(virtual_usec / 1000000l)
    *usec = int(virtual_usec % 1000000l)
}

// play mode's clock, Doom's only time source (PureDOOM's default reads 0): `game_usec`
def private real_gettime(var sec : int?; var usec : int?) {
    *sec = int(game_usec / 1000000l)
    *usec = int(game_usec % 1000000l)
}

// Doom's print: checksum lines fold into the digest, everything else goes to stdout
def private host_print(var str : uint8?) {
    if (!tic_digest_piece(tics, str)) {
        printf(cstr("%s"), str)
    }
}

def private report_timedemo {
    let wall = double(usec_now()) / 1000000.0lf
    printf(cstr("host: timed %d gametics in %.6f s\n"), gametic, double(work_usec) / 1000000.0lf)
    printf(cstr("host: %d checksum lines, digest %08x; wall %.3f s\n"), tics.lines, tics.hash, wall)
}

def private host_exit(code : int) {
    if (timedemo) {
        report_timedemo()
    }
    printf(cstr("host: Doom exited with %d\n"), code)
    var stdout_file = unsafe(crt::c_stdout())
    unsafe(crt::fflush(stdout_file))
    exit_code = code
    running = false
    c_longjmp(unsafe(addr(leave_frame)), 1)
}

// runs `step` with Doom's exit callback able to leave it; false once Doom has exited
def private guarded(step : block) : bool {
    try {
        invoke(step)
    } recover {
        if (c_jmp_target != unsafe(addr(leave_frame))) {
            c_jmp_rethrow()
        }
        c_jmp_target = null
    }
    return running
}

def private usec_now : int64 => get_time_nsec(clock_base) / 1000l

// Doom's key state from GLFW's: a Doom key two keys map to (left and right Ctrl) is down while either
// is. A key held while the page loses focus reads up: emscripten's GLFW releases every key on blur
def private poll_keys {
    for (k in range(256)) {
        doom_now[k] = false
    }
    for (row in KEYMAP) {
        if (glfwGetKey(window, row._0) == GLFW_PRESS) {
            doom_now[row._1] = true
        }
    }
    for (i in range(26)) {
        if (glfwGetKey(window, GLFW_KEY_A + i) == GLFW_PRESS) {
            doom_now[int(doom_key_t.DOOM_KEY_A) + i] = true
        }
    }
    for (i in range(10)) {
        if (glfwGetKey(window, GLFW_KEY_0 + i) == GLFW_PRESS) {
            doom_now[int(doom_key_t.DOOM_KEY_0) + i] = true
        }
    }
    for (k in range(256)) {
        if (doom_now[k] != doom_down[k]) {
            doom_down[k] = doom_now[k]
            if (doom_now[k]) {
                doom_key_down(enum_from_int(type<doom_key_t>, k))
            } else {
                doom_key_up(enum_from_int(type<doom_key_t>, k))
            }
        }
    }
    let pressed = glfwGetMouseButton(window, GLFW_MOUSE_BUTTON_1) == GLFW_PRESS
    if (pressed != mouse_down) {
        mouse_down = pressed
        if (pressed) {
            doom_button_down(doom_button_t.DOOM_LEFT_BUTTON)
        } else {
            doom_button_up(doom_button_t.DOOM_LEFT_BUTTON)
        }
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
    glTexImage2D(GL_TEXTURE_2D, 0, int(GL_RGBA), DOOM_W, DOOM_H, 0, GL_RGBA, GL_UNSIGNED_BYTE, null)
}

// Doom's frame, letterboxed to 4:3 (the 320x200 screen was shown on 4:3 monitors)
def private draw_frame {
    let pixels = doom_get_framebuffer(4)
    glBindTexture(GL_TEXTURE_2D, screen_tex)
    glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, DOOM_W, DOOM_H, GL_RGBA, GL_UNSIGNED_BYTE, pixels)
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

[export]
def init {
    c_runtime_init("doom_web")
    let argc = c_argc()
    var argv = c_argv()
    for (i in range(1, argc)) {
        unsafe {
            if (crt::strcmp(argv[i], cstr("-timedemo")) == 0) {
                timedemo = true
            }
            if (crt::strcmp(argv[i], cstr("-uncapped")) == 0) {
                uncapped = true
            }
        }
    }
    if (glfwInit() == 0) {
        panic("can't init glfw")
    }
    glfwInitOpenGL(3, 3)
    window = glfwCreateWindow(960, 720, "PureDOOM in daslang", null, null)
    if (window == null) {
        panic("can't create window")
    }
    glfwMakeContextCurrent(window)
    create_gl_objects()
    doom_set_print(@@host_print)
    doom_set_exit(@@host_exit)
    clock_base = ref_time_ticks()
    if (timedemo) {
        doom_set_gettime(@@virtual_gettime)
    } else {
        doom_set_gettime(@@real_gettime)
    }
    running = true
    if (!timedemo) {
        start_audio()
    }
    guarded() {
        doom_init(argc, argv, 0)
    }
    last_frame_usec = usec_now()
    stats_start = last_frame_usec
}

// sound (section 5): Doom's sfx mix, 512 stereo int16 frames at 11025 a second per
// `doom_get_sound_buffer`, plus the music synthesizer, streamed to dasAudio; the host keeps the
// stream's own queue (dasAudio publishes it) about 2048 frames deep, so the sound never lags further,
// a stall or a hidden tab only leaves a gap, and a suspended page queues nothing. Not in a timedemo.
// Music: a MUS lump plays through `doom_tick_midi` (140 ticks a second), a MIDI lump (all of
// Freedoom's) through the host's own player
let private SFX_RATE = 11025
let private SFX_FRAMES = 512
let private AUDIO_LEAD_FRAMES = 2048
let private MIDI_RATE = 140

var private audio_on = false
var private audio_channels : AudioSystemChannels
var private audio_sid : SID = INVALID_SID
var private audio_status : SeqBox?
var private midi_carry = 0.0
var private synth = make_synth()
var private song_player = MidiPlayer()
var private song_index = -1

def private start_audio {
    audio_channels = audio_system_create()
    audio_sid = play_sound_from_pcm_stream(SFX_RATE, 2)
    audio_status = seq_box_create()
    set_status_update(audio_sid, audio_status)
    audio_on = true
}

// one MUS tick: every message Doom's music player has for it (it returns 0 when the tick is done).
// While a MIDI song plays, the engine's volume messages (CC7) are dropped: the song's own mix keeps
// its channel volumes and the synthesizer's gain carries Doom's music volume
def private tick_music(var s : Synth) {
    var m = doom_tick_midi()
    while (m != 0ul) {
        let volume = (m & 0xf0ul) == 0xb0ul && ((m >> 8ul) & 0x7ful) == 7ul
        if (!(volume && song_player.playing)) {
            synth_message(s, m)
        }
        m = doom_tick_midi()
    }
}

// the song Doom plays: the S_music entry holding data (S_ChangeMusic loads it, S_StopMusic clears it);
// a MIDI lump starts the host's player, anything else stops it and is left to doom_tick_midi
def private follow_song {
    var playing = -1
    for (i in range(1, int(musicenum_t.NUMMUSIC))) {
        if (S_music[i].data != null) {
            playing = i
            break
        }
    }
    midi_pause(song_player, synth, int(paused) != 0)
    if (playing == song_index) {
        return
    }
    song_index = playing
    midi_stop(song_player, synth)
    // the engine's own messages for the change (its notes off) go first
    tick_music(synth)
    if (playing < 0) {
        return
    }
    let data = unsafe(reinterpret<uint8?>(S_music[playing].data))
    let size = W_LumpLength(S_music[playing].lumpnum)
    var song : MidiSong
    if (midi_parse(data, size, song)) {
        midi_start(song_player, synth, song, true)
    }
}

// the frames appended since the stream's consumed position last moved, and that position: while
// the device pulls nothing (a suspended page) the mixer publishes no new status, and these keep the
// host from appending past the lead
var private appended_since = 0
var private last_consumed : uint64 = 0xfffffffffffffffful

// the frames the stream holds: as the mixer last published them, plus what the host appended since
def private queued_frames : int {
    var queued = 0
    var consumed = last_consumed
    audio_status |> read() $(st : AudioChannelStatus) {
        queued = int(st.stream_queued_frames)
        consumed = st.consumed_position
    }
    if (consumed != last_consumed) {
        last_consumed = consumed
        appended_since = 0
    }
    return queued + appended_since
}

// blocks until the stream holds about the lead
def private feed_audio {
    follow_song()
    synth.gain = song_player.playing ? float(snd_MusicVolume) / 15.0 : 1.0
    var queued = queued_frames()
    while (queued < AUDIO_LEAD_FRAMES) {
        var chunk : array<float>
        chunk |> resize(SFX_FRAMES * 2)
        let pcm = doom_get_sound_buffer()
        for (i in range(SFX_FRAMES * 2)) {
            chunk[i] = float(unsafe(pcm[i])) / 32768.0
        }
        music_block(synth, song_player, midi_carry, chunk, SFX_FRAMES, SFX_RATE, MIDI_RATE) $(var s : Synth) {
            tick_music(s)
        }
        for (x in chunk) {
            x = clamp(x, -1.0, 1.0)
        }
        append_to_pcm(audio_sid, chunk)
        appended_since += SFX_FRAMES
        queued += SFX_FRAMES
    }
}

// the counters of the page's fps line, over the second since `stats_start`: animation frames
// presented, tics run, and frames Doom rendered (one per tic, plus the uncapped ones)
var private stats_start : int64 = 0l
var private stats_tic = 0
var private stats_frames = 0
var private stats_renders = 0

// one more render of the current state, no tic: PureDOOM has no render interpolation and processes
// input only in tics, so the frame shows the state the last tic left; skipped during a wipe, which
// the tics themselves draw
def private render_between_tics {
    if (int(is_wiping_screen) == 0) {
        D_Display()
        stats_renders++
    }
}

// once a second, the page's fps line: `host: stats <frames> <tics> <renders> <seconds>`
def private report_stats {
    let now = usec_now()
    if (now - stats_start < 1000000l) {
        return
    }
    let tics = gametic - stats_tic
    printf(cstr("host: stats %d %d %d %.3f\n"), stats_frames, tics, stats_renders + tics, double(now - stats_start) / 1000000.0lf)
    stats_start = now
    stats_tic = gametic
    stats_frames = 0
    stats_renders = 0
}

[export]
def update : bool {
    if (!running) {
        return false
    }
    glfwPollEvents()
    if (timedemo) {
        let frame_start = usec_now()
        var now = frame_start
        while (running && now - frame_start < TIMEDEMO_BUDGET_USEC) {
            guarded() {
                doom_force_update()
                virtual_usec += int64(1000000 / 35)
                if (uncapped) {
                    render_between_tics()
                }
            }
            let after = usec_now()
            work_usec += after - now
            now = after
        }
    } else {
        let now = usec_now()
        let interval = now - last_frame_usec
        game_usec += min(interval, MAX_FRAME_USEC)
        last_frame_usec = now
        poll_keys()
        guarded() {
            doom_update()
        }
        if (audio_on) {
            feed_audio()
        }
        if (uncapped) {
            let budget = min(UNCAPPED_BUDGET_USEC, interval * 6l / 10l)
            while (running && usec_now() - now < budget) {
                guarded() {
                    render_between_tics()
                }
            }
        }
    }
    draw_frame()
    stats_frames++
    report_stats()
    return running
}

[export]
def shutdown {
    if (audio_on) {
        unset_status_update(audio_sid)
        audio_system_finalize(audio_channels.command, audio_channels.next_sid)
        audio_status |> seq_box_release
        audio_on = false
    }

    if (window != null) {
        glfwDestroyWindow(window)
        window = null
    }
    glfwTerminate()
}

// the desktop driver: the same lifecycle in a loop, for a native run of this host
[export]
def main : int {
    init()
    while (update() && glfwWindowShouldClose(window) == 0) {
        pass
    }
    shutdown()
    return exit_code
}
