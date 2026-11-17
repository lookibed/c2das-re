options gen2
require dastest/testing_boost public
require math
require ../web/puredoom/doom_synth.das

//! The PureDOOM page's music synthesizer (web/ARCHITECTURE.md section 5), driven with MIDI messages
//! packed the way `doom_tick_midi` packs them.

def private msg(status : uint; d1, d2 : int) : uint64 => uint64(status) | (uint64(d1) << 8ul) | (uint64(d2) << 16ul)

// the largest absolute sample of `frames` rendered frames
def private loudness(var synth : Synth; frames : int) : float {
    var out : array<float>
    out |> resize(frames * 2)
    synth_render(synth, out, 0, frames)
    var peak = 0.0
    for (s in out) {
        peak = max(peak, abs(s))
    }
    return peak
}

[test(description = "a melodic note sounds, pans by the channel, and dies after its note-off")]
def test_note(t : T?) {
    var synth = make_synth()
    t |> equal(loudness(synth, 100), 0.0)
    synth_message(synth, msg(0xb0 | 2, 10, 0))      // channel 2 panned hard left
    synth_message(synth, msg(0x90 | 2, 60, 127))
    t |> equal(synth_active_voices(synth), 1)
    var out : array<float>
    out |> resize(2000)
    synth_render(synth, out, 0, 1000)
    var left, right = 0.0
    for (f in range(1000)) {
        left = max(left, abs(out[f * 2]))
        right = max(right, abs(out[f * 2 + 1]))
    }
    t |> success(left > 0.01, "the note sounds on the left")
    t |> equal(right, 0.0)
    synth_message(synth, msg(0x80 | 2, 60, 0))
    loudness(synth, 11025)
    t |> equal(synth_active_voices(synth), 0)
}

[test(description = "note-on with velocity 0 is a note-off; all-notes-off releases the channel")]
def test_note_off_forms(t : T?) {
    var synth = make_synth()
    synth_message(synth, msg(0x90, 64, 100))
    synth_message(synth, msg(0x90, 64, 0))
    loudness(synth, 11025)
    t |> equal(synth_active_voices(synth), 0)
    synth_message(synth, msg(0x91, 60, 100))
    synth_message(synth, msg(0x91, 64, 100))
    synth_message(synth, msg(0xb1, 123, 0))
    loudness(synth, 11025)
    t |> equal(synth_active_voices(synth), 0)
}

[test(description = "a drum on channel 9 sounds and ends by itself, with no note-off")]
def test_drum(t : T?) {
    var synth = make_synth()
    synth_message(synth, msg(0x99, 36, 120))
    synth_message(synth, msg(0x99, 42, 120))
    t |> success(loudness(synth, 200) > 0.01, "the drums sound")
    loudness(synth, 22050)
    t |> equal(synth_active_voices(synth), 0)
}

[test(description = "more notes than voices steal one, never more than MAX_VOICES sound")]
def test_voice_stealing(t : T?) {
    var synth = make_synth()
    for (n in range(MAX_VOICES + 8)) {
        synth_message(synth, msg(0x90, 40 + n, 100))
    }
    t |> equal(synth_active_voices(synth), MAX_VOICES)
}

[test(description = "a pitch bend up raises the channel's ratio, the centre restores it, a reset clears it")]
def test_pitch_bend(t : T?) {
    var synth = make_synth()
    synth_message(synth, msg(0xe0, 127, 127))
    t |> success(synth.channels[0].bend > 1.1, "bent up about two semitones")
    synth_message(synth, msg(0xe0, 0, 64))
    t |> equal(synth.channels[0].bend, 1.0)
    synth_message(synth, msg(0xe0, 0, 0))
    synth_message(synth, msg(0xb0, 121, 0))
    t |> equal(synth.channels[0].bend, 1.0)
}

[test(description = "CC7 scales a channel's new notes; CC120 releases the channel; a reset restores the defaults")]
def test_controllers(t : T?) {
    var loud = make_synth()
    synth_message(loud, msg(0x90, 60, 127))
    let full = loudness(loud, 400)
    var quiet = make_synth()
    synth_message(quiet, msg(0xb0, 7, 32))
    synth_message(quiet, msg(0x90, 60, 127))
    let low = loudness(quiet, 400)
    t |> success(low > 0.0 && low < full * 0.5, "a channel at volume 32 plays below half of one at 100")
    synth_message(quiet, msg(0xb0, 120, 0))
    loudness(quiet, 11025)
    t |> equal(synth_active_voices(quiet), 0)
    synth_message(quiet, msg(0xc0, 30, 0))
    synth_reset_channels(quiet)
    t |> equal(quiet.channels[0].program, 0)
    t |> success(quiet.channels[0].volume > 0.78 && quiet.channels[0].volume < 0.79, "volume back to 100")
}

[test(description = "the instrument family picks the sound: a piano and a distortion guitar give different waves")]
def test_families(t : T?) {
    var piano = make_synth()
    synth_message(piano, msg(0x90, 60, 100))
    var guitar = make_synth()
    synth_message(guitar, msg(0xc0, 30, 0))
    synth_message(guitar, msg(0x90, 60, 100))
    var a, b : array<float>
    a |> resize(400)
    b |> resize(400)
    synth_render(piano, a, 0, 200)
    synth_render(guitar, b, 0, 200)
    var differ = false
    for (i in range(400)) {
        differ = differ || abs(a[i] - b[i]) > 0.001
    }
    t |> success(differ, "program 30 does not sound like program 0")
}

[test(description = "drums sound out their own decay: a note-off on channel 9 is ignored, a cymbal outlasts a hi-hat")]
def test_drum_decay(t : T?) {
    var synth = make_synth()
    synth_message(synth, msg(0x99, 42, 120))
    synth_message(synth, msg(0x99, 49, 120))
    synth_message(synth, msg(0x89, 49, 0))
    loudness(synth, 2205)                         // 0.2 s: the hi-hat (40 ms) is gone, the cymbal (0.8 s) is not
    t |> equal(synth_active_voices(synth), 1)
}

[test(description = "a full synthesizer steals a released voice before one still sounding, and never a rising one")]
def test_steal_order(t : T?) {
    var synth = make_synth()
    for (n in range(MAX_VOICES)) {
        synth_message(synth, msg(0x90, 40 + n, 100))
    }
    loudness(synth, 2000)                          // every voice past its attack
    synth_message(synth, msg(0x80, 45, 0))         // one released
    synth_message(synth, msg(0x90, 100, 100))
    var stolen_released = true
    for (v in synth.voices) {
        if (v.note == 45 && v.active) {
            stolen_released = false
        }
    }
    t |> success(stolen_released, "the released note 45 gave its voice")
    synth_message(synth, msg(0x90, 101, 100))      // now every voice sounds; note 100 is rising
    var rising_kept = false
    for (v in synth.voices) {
        if (v.note == 100 && v.active) {
            rising_kept = true
        }
    }
    t |> success(rising_kept, "the rising note 100 kept its voice")
}
