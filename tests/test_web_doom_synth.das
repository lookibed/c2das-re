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
