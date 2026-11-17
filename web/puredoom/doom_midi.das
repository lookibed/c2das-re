options gen2
options indenting = 4

module doom_midi shared public

require doom_synth
require math
require daslib/cmp

//! A Standard MIDI File player for the PureDOOM page (web/ARCHITECTURE.md section 5). PureDOOM's
//! music player reads only Doom's MUS format, and every music lump of Freedoom is a MIDI file, so the
//! host plays those itself: `midi_parse` reads a format 0 or 1 file into one list of channel messages
//! with their times in seconds (the tempo map applied), and `midi_advance` hands the synthesizer the
//! messages due, looping at the end. Messages are packed as `doom_tick_midi` packs them.

struct MidiEvent {
    at : double             // seconds from the start of the song
    msg : uint64            // status | data1 << 8 | data2 << 16
}

struct MidiSong {
    events : array<MidiEvent>
    length : double
}

struct MidiPlayer {
    song : MidiSong
    pos : int
    time : double
    playing : bool
    loop : bool = true
}

// one event of one track in ticks, before the tempo map: a channel message, or a tempo when `tempo` > 0
struct private TickEvent {
    tick : int64
    order : int             // tempo first among events of one tick, then the file's order
    msg : uint64
    tempo : int
}

def private be16(data : uint8?; at : int) : int => (int(unsafe(data[at])) << 8) | int(unsafe(data[at + 1]))

def private be32(data : uint8?; at : int) : int => (be16(data, at) << 16) | be16(data, at + 2)

// a variable-length quantity at `at`; `at` moves past it
def private vlq(data : uint8?; var at : int&; size : int) : int {
    var value = 0
    for (_ in range(4)) {
        if (at >= size) {
            return value
        }
        let b = int(unsafe(data[at]))
        at++
        value = (value << 7) | (b & 0x7f)
        if ((b & 0x80) == 0) {
            break
        }
    }
    return value
}

// whether the four bytes at `at` are `tag`
def private same4(data : uint8?; at : int; tag : uint8[4]) : bool {
    for (i in range(4)) {
        if (unsafe(data[at + i]) != tag[i]) {
            return false
        }
    }
    return true
}

let private MTHD = fixed_array<uint8>(77u8, 84u8, 104u8, 100u8)
let private MTRK = fixed_array<uint8>(77u8, 84u8, 114u8, 107u8)

//! Whether the lump at `data` (`size` bytes) is a MIDI file.
def midi_is_file(data : uint8?; size : int) : bool => size >= 14 && same4(data, 0, MTHD)

// the events of the track whose body is data[start, end)
def private parse_track(data : uint8?; start, end : int; var events : array<TickEvent>) {
    var at = start
    var tick = 0l
    var status = 0
    while (at < end) {
        tick += int64(vlq(data, at, end))
        if (at >= end) {
            break
        }
        let b = int(unsafe(data[at]))
        if (b == 0xff) {                        // meta: the tempo matters, the rest is skipped
            let kind = int(unsafe(data[at + 1]))
            at += 2
            let len = vlq(data, at, end)
            if (kind == 0x51 && len == 3 && at + 3 <= end) {
                let tempo = (int(unsafe(data[at])) << 16) | be16(data, at + 1)
                events |> push(TickEvent(tick = tick, order = -1, tempo = tempo))
            }
            at += len
            continue
        }
        if (b == 0xf0 || b == 0xf7) {           // sysex: skipped
            at++
            let len = vlq(data, at, end)
            at += len
            continue
        }
        if ((b & 0x80) != 0) {
            status = b
            at++
        } elif (status == 0) {
            break                               // data with no status to run on: a broken track
        }
        let kind = status & 0xf0
        let d1 = at < end ? int(unsafe(data[at])) : 0
        var d2 = 0
        if (kind == 0xc0 || kind == 0xd0) {
            at++
        } else {
            d2 = at + 1 < end ? int(unsafe(data[at + 1])) : 0
            at += 2
        }
        events |> push(TickEvent(tick = tick, order = length(events), msg = uint64(status | (d1 << 8) | (d2 << 16))))
    }
}

//! Reads the MIDI file at `data` into `song`; false when it is not one this player reads.
def midi_parse(data : uint8?; size : int; var song : MidiSong) : bool {
    song.events |> clear()
    song.length = 0.0lf
    if (!midi_is_file(data, size)) {
        return false
    }
    let header = be32(data, 4)
    let tracks = be16(data, 10)
    let division = be16(data, 12)
    var seconds_per_tick = 0.0lf
    var smpte = false
    if ((division & 0x8000) != 0) {             // SMPTE frames a second times ticks a frame
        let fps = 256 - (division >> 8)
        seconds_per_tick = 1.0lf / double(fps * (division & 0xff))
        smpte = true
    } elif (division == 0) {
        return false
    }
    var events : array<TickEvent>
    var at = 8 + header
    for (_ in range(tracks)) {
        if (at + 8 > size) {
            break
        }
        let len = be32(data, at + 4)
        if (same4(data, at, MTRK)) {
            parse_track(data, at + 8, min(at + 8 + len, size), events)
        }
        at += 8 + len
    }
    sort(events, cmp_by(_.tick, _.order))
    var tempo = 500000                          // microseconds a quarter note, the default 120 bpm
    var last_tick = 0l
    var now = 0.0lf
    for (e in events) {
        let per_tick = smpte ? seconds_per_tick : double(tempo) / 1000000.0lf / double(division)
        now += double(e.tick - last_tick) * per_tick
        last_tick = e.tick
        if (e.tempo > 0) {
            tempo = e.tempo
        } else {
            song.events |> push(MidiEvent(at = now, msg = e.msg))
        }
    }
    song.length = now
    return !empty(song.events)
}

//! Starts `song` from its beginning.
def midi_start(var player : MidiPlayer; var song : MidiSong; loop : bool) {
    player.song <- song
    player.pos = 0
    player.time = 0.0lf
    player.playing = true
    player.loop = loop
}

// every channel's notes off, at a stop or a loop
def private all_notes_off(var synth : Synth) {
    for (ch in range(16)) {
        synth_message(synth, uint64(0xb0 | ch | (123 << 8)))
    }
}

//! Stops the song, its notes released.
def midi_stop(var player : MidiPlayer; var synth : Synth) {
    if (player.playing) {
        all_notes_off(synth)
    }
    player.playing = false
}

//! Moves the song on by `seconds`, applying every message that falls due to `synth`.
def midi_advance(var player : MidiPlayer; var synth : Synth; seconds : double) {
    if (!player.playing) {
        return
    }
    player.time += seconds
    while (player.playing) {
        while (player.pos < length(player.song.events) && player.song.events[player.pos].at <= player.time) {
            synth_message(synth, player.song.events[player.pos].msg)
            player.pos++
        }
        if (player.pos < length(player.song.events) || player.time < player.song.length) {
            return
        }
        all_notes_off(synth)
        if (!player.loop || player.song.length <= 0.0lf) {
            player.playing = false
            return
        }
        player.time -= player.song.length
        player.pos = 0
    }
}
