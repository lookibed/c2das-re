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
    midi_start(player, synth, song, true)
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
    midi_start(once, synth, song2, false)
    midi_advance(once, synth, 1.0lf)
    t |> success(!once.playing, "a song that does not loop stops at its end")
}

// a format 0 file of one track: `division`, then the track body `body`
def private one_track(division : int; body : array<uint8>) : array<uint8> {
    var b <- [77u8, 84u8, 104u8, 100u8, 0u8, 0u8, 0u8, 6u8, 0u8, 0u8, 0u8, 1u8, uint8(division >> 8), uint8(division & 255),
        77u8, 84u8, 114u8, 107u8, 0u8, 0u8, 0u8, uint8(length(body))]
    b |> push_from(body)
    return <- b
}

def private parsed(var bytes : array<uint8>; var song : MidiSong) : bool => midi_parse(unsafe(addr(bytes[0])), length(bytes), song)

[test(description = "SMPTE time: 25 frames a second of 40 ticks is a millisecond a tick; a division of 0 is refused")]
def test_division(t : T?) {
    var smpte <- one_track(59176, [0u8, 144u8, 60u8, 100u8, 135u8, 104u8, 128u8, 60u8, 0u8, 0u8, 255u8, 47u8, 0u8])
    var song : MidiSong
    t |> success(parsed(smpte, song), "an SMPTE file parses")
    t |> success(abs(song.events[1].at - 1.0lf) < 0.000001lf, "1000 ticks at 1 ms a tick are 1 s")
    var zero <- one_track(0, [0u8, 255u8, 47u8, 0u8])
    t |> success(!parsed(zero, song), "a division of 0 is refused")
}

[test(description = "a tempo change mid-song times what follows; the song lasts to its end of track, a rest included")]
def test_tempo_change_and_end(t : T?) {
    // at 96 ticks a quarter: a note at 0, tempo 1000000 at 96 (0.5 s at the default), a note-off at 192
    // (0.5 + 1.0 s), end of track 96 ticks later (a rest of 1.0 s)
    var bytes <- one_track(96, [0u8, 144u8, 60u8, 100u8, 96u8, 255u8, 81u8, 3u8, 15u8, 66u8, 64u8, 96u8, 128u8, 60u8, 0u8, 96u8, 255u8, 47u8, 0u8])
    var song : MidiSong
    t |> success(parsed(bytes, song), "the file parses")
    t |> equal(length(song.events), 2)
    t |> success(abs(song.events[1].at - 1.5lf) < 0.000001lf, "the note-off falls at 1.5 s")
    t |> success(abs(song.length - 2.5lf) < 0.000001lf, "the song ends at its end of track, 2.5 s")
}

[test(description = "a track length past the lump stops the parse without reading beyond it")]
def test_truncated(t : T?) {
    var bytes <- one_track(96, [0u8, 144u8, 60u8, 100u8])
    bytes[21] = 200u8                              // the track claims 200 bytes, 4 follow
    var song : MidiSong
    t |> success(!parsed(bytes, song), "nothing playable in a truncated file")
}

[test(description = "a loop releases the song's notes; a pause releases them and holds the song; a start resets the channels")]
def test_loop_pause_reset(t : T?) {
    var bytes <- one_track(96, [0u8, 193u8, 7u8, 0u8, 145u8, 60u8, 100u8, 96u8, 255u8, 47u8, 0u8])
    var song : MidiSong
    parsed(bytes, song)
    var synth = make_synth()
    var player = MidiPlayer()
    midi_start(player, synth, song, true)
    midi_advance(player, synth, 0.1lf)
    t |> equal(synth.channels[1].program, 7)
    midi_advance(player, synth, 0.45lf)            // past the 0.5 s end: notes released, the song starts over
    var released = 0
    for (v in synth.voices) {
        if (v.active && v.released) {
            released++
        }
    }
    t |> success(released >= 1, "the first pass's note is released at the loop")
    midi_pause(player, synth, true)
    let at = player.time
    midi_advance(player, synth, 1.0lf)
    t |> equal(player.time, at)
    midi_pause(player, synth, false)
    var again : MidiSong
    parsed(bytes, again)
    synth.channels[1].program = 50
    midi_start(player, synth, again, true)
    t |> equal(synth.channels[1].program, 0)
}

[test(description = "music_block runs the MUS tick 140 times a second of frames, carried across blocks")]
def test_music_block(t : T?) {
    var synth = make_synth()
    var player = MidiPlayer()
    var carry = 0.0
    var ticks = 0
    var out : array<float>
    out |> resize(1024)
    for (_ in range(22)) {                         // 22 blocks of 512 frames: 11264 frames, a little over 1 s
        music_block(synth, player, carry, out, 512, 11025, 140) $(var _s : Synth) {
            ticks++
        }
    }
    t |> success(ticks == 143 || ticks == 144, "{ticks} ticks over 11264 frames at 140 a second")
}

