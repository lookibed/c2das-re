options gen2
require dastest/testing_boost public
require math
require ../web/puredoom/doom_synth.das
require ../web/puredoom/doom_midi.das

//! The PureDOOM page's MIDI file player (web/ARCHITECTURE.md section 5) over a small file built here:
//! format 1, 96 ticks a quarter, a tempo track at 250000 microseconds a quarter (240 bpm) and a note
//! track with running status, a sysex and a program change.

// header; tempo track: tempo 250000 at 0, end; note track: program 5 on channel 1, a sysex, note on 60
// at 0, then the same note's off 96 ticks later in running status (velocity 0), end
def private file_bytes : array<uint8> {
    return <- [77u8, 84u8, 104u8, 100u8, 0u8, 0u8, 0u8, 6u8, 0u8, 1u8, 0u8, 2u8, 0u8, 96u8,
        77u8, 84u8, 114u8, 107u8, 0u8, 0u8, 0u8, 11u8, 0u8, 255u8, 81u8, 3u8, 3u8, 208u8, 144u8, 0u8, 255u8, 47u8, 0u8,
        77u8, 84u8, 114u8, 107u8, 0u8, 0u8, 0u8, 18u8,
        0u8, 193u8, 5u8, 0u8, 240u8, 2u8, 1u8, 247u8, 0u8, 145u8, 60u8, 100u8, 96u8, 60u8, 0u8, 0u8, 255u8, 47u8]
}

[test(description = "a format 1 file: messages in time order, the tempo applied, running status and sysex read")]
def test_parse(t : T?) {
    var bytes <- file_bytes()
    var song : MidiSong
    t |> success(midi_parse(unsafe(addr(bytes[0])), length(bytes), song), "the file parses")
    t |> equal(length(song.events), 3)
    t |> equal(song.events[0].msg, uint64(0xc1 | (5 << 8)))
    t |> equal(song.events[1].msg, uint64(0x91 | (60 << 8) | (100 << 16)))
    t |> equal(song.events[2].msg, uint64(0x91 | (60 << 8)))
    t |> success(abs(song.events[2].at - 0.25lf) < 0.000001lf, "96 ticks at 250000 us a quarter of 96 ticks are 0.25 s")
    t |> success(abs(song.length - 0.25lf) < 0.000001lf, "the song ends at its last event")
}

[test(description = "a lump that is no MIDI file is refused")]
def test_not_midi(t : T?) {
    var mus <- [77u8, 85u8, 83u8, 26u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]
    var song : MidiSong
    t |> success(!midi_parse(unsafe(addr(mus[0])), length(mus), song), "a MUS lump is not a MIDI file")
}

[test(description = "the player applies messages as they fall due, loops with the notes released, and stops")]
def test_player(t : T?) {
    var bytes <- file_bytes()
    var song : MidiSong
    midi_parse(unsafe(addr(bytes[0])), length(bytes), song)
    var synth = make_synth()
    var player = MidiPlayer()
    midi_start(player, song, true)
    midi_advance(player, synth, 0.1lf)
    t |> equal(synth.channels[1].program, 5)
    t |> equal(synth_active_voices(synth), 1)
    midi_advance(player, synth, 0.2lf)            // past the end: the note is released, the song loops
    t |> success(player.playing, "a looping song keeps playing")
    t |> equal(player.pos, 2)                     // past 0.3 - 0.25 = 0.05 s of the second pass, both 0 s events done
    midi_stop(player, synth)
    t |> success(!player.playing, "stopped")
    var once = MidiPlayer()
    var song2 : MidiSong
    midi_parse(unsafe(addr(bytes[0])), length(bytes), song2)
    midi_start(once, song2, false)
    midi_advance(once, synth, 1.0lf)
    t |> success(!once.playing, "a song that does not loop stops at its end")
}
