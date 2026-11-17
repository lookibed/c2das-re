options gen2
options indenting = 4

module doom_synth shared public

require math

//! A small General MIDI synthesizer for Doom's music (web/ARCHITECTURE.md section 5): Doom's MUS
//! player hands out one MIDI message per `doom_tick_midi` call, packed as `status | data1 << 8 |
//! data2 << 16`; `synth_message` applies it and `synth_render` adds the voices into an interleaved
//! stereo float buffer. No sample data: each General MIDI family is one waveform with one
//! envelope, and the percussion channel (9) is shaped noise and pitch sweeps. It needs nothing but
//! math, so a test on the pin runs it.

let MAX_VOICES = 24
let PERCUSSION = 9

enum Wave {
    sine
    triangle
    square
    saw
    noise
}

struct Voice {
    active : bool
    channel : int
    note : int
    wave : Wave
    freq : float
    sweep : float           // the frequency multiplies by this every sample (a drum's falling pitch)
    phase : float
    level : float           // envelope level, 0..1
    peak : float            // velocity times the channel's volume
    attack : float          // level added per sample while rising
    decay : float           // level kept per sample while falling to `sustain`
    sustain : float
    release : float         // level kept per sample after the note's release
    rising : bool
    released : bool
    pan : float
    noise : uint
}

struct Channel {
    program : int
    volume : float = 100.0 / 127.0
    pan : float = 0.5
    bend : float = 1.0      // the pitch-bend frequency ratio
}

struct Synth {
    rate : float = 11025.0
    @safe_when_uninitialized voices : Voice[MAX_VOICES]
    @safe_when_uninitialized channels : Channel[16]
    noise_seed : uint = 22222u
    gain : float = 1.0      // the master volume, Doom's music volume
}

//! A synthesizer at `rate` frames a second, every channel at its General MIDI defaults.
def make_synth(rate : float = 11025.0) : Synth {
    var synth = Synth(rate = rate)
    for (ch in synth.channels) {
        ch = Channel()
    }
    return <- synth
}

// per-sample factor that takes a level to 1/1000 in `seconds`
def private fall(rate, seconds : float) : float => exp(log(0.001) / (rate * seconds))

def private note_freq(note : int) : float => 440.0 * pow(2.0, float(note - 69) / 12.0)

// the waveform and envelope of a General MIDI program (its family of eight)
def private shape_melodic(var v : Voice; rate : float; program : int) {
    let family = program / 8
    var attack = 0.005
    var decay = 0.3
    v.sustain = 0.6
    var release = 0.15
    if (family == 0 || family == 1) {           // piano, chromatic percussion
        v.wave = Wave.triangle
        decay = 0.8
        v.sustain = 0.0
    } elif (family == 2) {                      // organ
        v.wave = Wave.square
        v.sustain = 0.8
    } elif (family == 3) {                      // guitar: the distorted ones buzz
        v.wave = program == 29 || program == 30 ? Wave.square : Wave.saw
        decay = 1.0
        v.sustain = 0.3
    } elif (family == 4) {                      // bass
        v.wave = Wave.triangle
        decay = 0.5
        v.sustain = 0.5
    } elif (family == 5 || family == 6) {       // strings, ensemble
        v.wave = Wave.saw
        attack = 0.08
        v.sustain = 0.8
        release = 0.3
    } elif (family == 7 || family == 8) {       // brass, reed
        v.wave = Wave.saw
        attack = 0.02
    } elif (family == 9) {                      // pipe
        v.wave = Wave.sine
        attack = 0.03
        v.sustain = 0.8
    } elif (family == 10) {                     // synth lead
        v.wave = Wave.square
    } else {                                    // pads, effects, ethnic and the rest
        v.wave = Wave.saw
        attack = 0.1
        v.sustain = 0.7
        release = 0.4
    }
    v.attack = 1.0 / (rate * attack)
    v.decay = fall(rate, decay)
    v.release = fall(rate, release)
}

// the sound of a General MIDI percussion key
def private shape_drum(var v : Voice; rate : float; note : int) {
    v.sustain = 0.0
    v.attack = 1.0
    v.release = fall(rate, 0.05)
    var decay = 0.15
    if (note == 35 || note == 36) {             // bass drum: a falling sine
        v.wave = Wave.sine
        v.freq = 110.0
        v.sweep = fall(rate, 0.6)
        decay = 0.25
    } elif (note == 41 || note == 43 || note == 45 || note == 47 || note == 48 || note == 50) {
        v.wave = Wave.sine                      // toms: falling sines, higher with the key
        v.freq = 80.0 + float(note - 41) * 18.0
        v.sweep = fall(rate, 1.2)
        decay = 0.3
    } elif (note == 42 || note == 44) {         // closed and pedal hi-hat
        v.wave = Wave.noise
        decay = 0.04
    } elif (note == 46) {                       // open hi-hat
        v.wave = Wave.noise
        decay = 0.25
    } elif (note == 49 || note == 51 || note == 52 || note == 55 || note == 57 || note == 59) {
        v.wave = Wave.noise                     // cymbals
        decay = 0.8
    } else {                                    // snares, claps and the rest: noise
        v.wave = Wave.noise
        decay = 0.12
    }
    v.decay = fall(rate, decay)
}

def private find_voice(synth : Synth) : int {
    for (i in range(MAX_VOICES)) {
        if (!synth.voices[i].active) {
            return i
        }
    }
    // steal the quietest
    var best = 0
    for (i in range(1, MAX_VOICES)) {
        if (synth.voices[i].level * synth.voices[i].peak < synth.voices[best].level * synth.voices[best].peak) {
            best = i
        }
    }
    return best
}

def private note_on(var synth : Synth; channel, note, velocity : int) {
    let i = find_voice(synth)
    var v & = unsafe(synth.voices[i])
    let ch = synth.channels[channel]
    v.active = true
    v.channel = channel
    v.note = note
    v.phase = 0.0
    v.level = 0.0
    v.rising = true
    v.released = false
    v.sweep = 1.0
    v.pan = ch.pan
    v.noise = synth.noise_seed + uint(i) * 7919u
    v.peak = float(velocity) / 127.0 * ch.volume * 0.25
    if (channel == PERCUSSION) {
        shape_drum(v, synth.rate, note)
    } else {
        v.freq = note_freq(note)
        shape_melodic(v, synth.rate, ch.program)
    }
}

def private note_off(var synth : Synth; channel, note : int) {
    for (v in synth.voices) {
        if (v.active && !v.released && v.channel == channel && v.note == note) {
            v.released = true
        }
    }
}

//! Applies one MIDI message as `doom_tick_midi` packs it.
def synth_message(var synth : Synth; msg : uint64) {
    let status = uint(msg & 0xf0ul)
    let channel = int(msg & 0x0ful)
    let d1 = int((msg >> 8ul) & 0x7ful)
    let d2 = int((msg >> 16ul) & 0x7ful)
    if (status == 0x90 && d2 > 0) {
        note_on(synth, channel, d1, d2)
    } elif (status == 0x80 || status == 0x90) {
        note_off(synth, channel, d1)
    } elif (status == 0xc0) {
        synth.channels[channel].program = d1
    } elif (status == 0xb0) {
        if (d1 == 7) {
            synth.channels[channel].volume = float(d2) / 127.0
        } elif (d1 == 10) {
            synth.channels[channel].pan = float(d2) / 127.0
        } elif (d1 == 120 || d1 == 123) {       // all sound off, all notes off
            for (v in synth.voices) {
                if (v.channel == channel) {
                    v.released = true
                }
            }
        } elif (d1 == 121) {                    // reset controllers
            synth.channels[channel].volume = 100.0 / 127.0
            synth.channels[channel].pan = 0.5
            synth.channels[channel].bend = 1.0
        }
    } elif (status == 0xe0) {                   // pitch bend, two semitones either way
        let bend = float(((d2 << 7) | d1) - 8192) / 8192.0
        synth.channels[channel].bend = pow(2.0, bend * 2.0 / 12.0)
    }
}

//! The number of voices sounding.
def synth_active_voices(synth : Synth) : int {
    var n = 0
    for (v in synth.voices) {
        if (v.active) {
            n++
        }
    }
    return n
}

def private sample(var v : Voice; bend : float; rate : float) : float {
    var s = 0.0
    if (v.wave == Wave.noise) {
        v.noise = v.noise * 1103515245u + 12345u
        s = float((v.noise >> 16u) & 0x7fffu) / 16384.0 - 1.0
    } else {
        let p = v.phase
        if (v.wave == Wave.sine) {
            s = sin(p * 2.0 * PI)
        } elif (v.wave == Wave.triangle) {
            s = 4.0 * abs(p - 0.5) - 1.0
        } elif (v.wave == Wave.square) {
            s = p < 0.5 ? 0.6 : -0.6
        } else {
            s = (2.0 * p - 1.0) * 0.7
        }
        v.phase += v.freq * bend / rate
        v.phase -= floor(v.phase)
        v.freq *= v.sweep
    }
    return s
}

def private step_envelope(var v : Voice) {
    if (v.released) {
        v.level *= v.release
        v.rising = false
    } elif (v.rising) {
        v.level += v.attack
        if (v.level >= 1.0) {
            v.level = 1.0
            v.rising = false
        }
    } elif (v.level > v.sustain) {
        v.level = max(v.sustain, v.level * v.decay)
    }
    if ((v.released || v.sustain == 0.0) && !v.rising && v.level < 0.001) {
        v.active = false
    }
}

//! Adds `frames` stereo frames of every sounding voice into `out` (interleaved left, right) from
//! index `at`.
def synth_render(var synth : Synth; var out : array<float>; at, frames : int) {
    for (v in synth.voices) {
        if (!v.active) {
            continue
        }
        let bend = synth.channels[v.channel].bend
        let left = v.peak * synth.gain * sqrt(1.0 - v.pan)
        let right = v.peak * synth.gain * sqrt(v.pan)
        for (f in range(frames)) {
            if (!v.active) {
                break
            }
            let s = sample(v, bend, synth.rate) * v.level
            out[at + f * 2] += s * left
            out[at + f * 2 + 1] += s * right
            step_envelope(v)
        }
    }
}
