# doom Architecture - the patches

Companion to `ARCHITECTURE.md` in this folder, its section 3.

## 3. The patches

`0001-per-tic-checksum.patch`: hunks in five files against the pin. `g_game.c` and `d_main.c`, under `-DDOOM_TIC_CHECKSUM`:
`G_Ticker` ends by storing `gametic`, the tic just run (the caller increments it after), and the
tic's checksum; `D_DoomLoop`, once `D_Display` has drawn that tic, prints one line through
`doom_print`, `tic=<gametic> cs=<8 hex digits> fb=<8 hex digits>`; without the define the build
prints nothing more. The line is printed whole after the frame, so no other output can split it
and `tic_lines` stays the one reader; a run that dies drawing a tic prints no line for it. Both
checksums are the 32-bit FNV-1a (offset basis 2166136261, prime 16777619; per byte
`cs = (cs ^ b) * prime` modulo 2^32). `cs` runs over the little-endian bytes of six 32-bit values
in order: `players[0].mo->x`, `y`, `z`, `angle` (each 0 while `players[0].mo` is null),
`players[0].health` and `prndindex`, the index `P_Random` steps (PureDOOM's `rndindex` is
`M_Random`'s, which the menus and the screen melt step, so it stays out). `fb` runs over the
`SCREENWIDTH * SCREENHEIGHT` bytes of `screens[0]` as `D_Display` leaves it: the frame of the tic,
or, on a tic that starts a screen melt, the screen the melt starts from (`wipe_EndScreen` puts it
back); the melt's own steps run no tic and print nothing. Every tic of a timedemo has its line.

Under `-DDOOM_FINAL_CHECKSUM`, the speed build's define (`ARCHITECTURE_RUN.md` section 9), the same
code builds without the per-tic hunks: `G_CheckDemoStatus`, as a `-timedemo` run reaches the end of
its demo (in `G_Ticker` of the tic past the last, as it reads that tic's command), prints one line,
`final tic=<gametic - 1> cs=<8 hex digits> fb=<8 hex digits>`, `cs` of the player's state and the
random index and `fb` of `screens[0]` as they stand then. That is the state the last tic left and the
screen `D_Display` drew for it unless something ran between: `G_Ticker` runs a reborn and a pending
level change (`G_DoReborn`, `G_DoCompleted`, `G_DoLoadLevel`) before it reads the command, and a
screen melt `D_Display` started steps `wipe_ScreenWipe` over `screens[0]` before the next
`G_Ticker`. A demo whose last tic sets one of these ends with another `cs` or `fb` than the
reference's last line, a desync and no fps, never a false pass. For the three freedoom2 demos the
line is the reference log's last line after `final `, the same bytes natively. That build hashes nothing else, one frame and 24 bytes of
state for the whole run, inside the host's timed window.

`w_wad.c`, `r_data.c` and `i_video.c` make the frame a function of the game alone, so the
reference frames are the patched source's, not vanilla's, at the pixels below. A column
drawer reads `dc_source[(frac >> FRACBITS) & 127]`, up to 127 bytes past a column's start: a wall
taller than its texture (freedoom2's 16-row `CRATINY` as a bottom texture) or a sprite post whose
first row rounds to row -1, which `& 127` wraps to 127. Past the end of a lump that read the
zone's next block header, its pointers among them, so the frame of such a tic changed with the
heap's addresses from run to run (3 of demo1's 2664 tics over four runs). So `W_CacheLumpNum`
allocates each lump with 128 zero bytes past its end, `R_GenerateComposite` zeroes a composite
texture with the same slack, and `I_InitGraphics` zeroes the screen, which tic 0 does not draw.
The game state does not read those bytes: `cs` is the same with and without the hunks.

`d_main.c`, unconditionally: `-playdemo` and `-timedemo` return from `D_DoomMain` after
`I_InitGraphics`. PureDOOM's `D_DoomLoop` runs one tic and returns where vanilla's never returns,
so `D_DoomMain` went on into the title loop (a single-player demo) or `G_InitNew` (a multiplayer
one, `demo2` of freedoom2), which replaced the demo; with the return the host's loop plays the
demo from its first tic. The fix is unconditional, since a timedemo is P6.7's benchmark too.

`0002-tic-trace.patch`, `p_tick.c`: under `-DDOOM_TIC_TRACE`, `P_Ticker` ends by printing
`trace=<gametic> x=<hex> y=<hex> z=<hex> ang=<hex> hp=<d> prnd=<d>`, the six values `cs` hashes, so
a desync names the value that differs; `tic_lines` skips the line and no reference log is
recorded with the define.

`0003-signed-ticcmd.patch`, `d_ticcmd.h`: `ticcmd_t`'s `forwardmove` and `sidemove` are `signed
char`, as in Chocolate Doom. A demo stores a backward move or a strafe left as a negative byte;
read back through a plain `char` it stays negative only where `char` is signed, and the
converter's dialect makes plain `char` unsigned (`docs/probe-findings.md` F17), under which a
plain field reads a strafe of -40 as 216. The native build at `-O2` with or without
`-funsigned-char` prints the reference lines of all three demos with the patch.

`0004-fine-table-overruns.patch`, `r_main.c` and `r_segs.c`: `R_ScaleFromGlobalAngle` indexes
`finesine` by an `int` angle shifted right, negative past `ANG180` (demo1's tic 255 reaches
-4096), and `R_RenderSegLoop` indexes `finetangent[angle]` with `angle` up to 8191, past its 4096
entries. `tables.c` defines `finetangent` right before `finesine`, so the native build reads the
other table; das range-checks both reads and panics. The patch spells the neighbouring read out,
`finetangent[FINEANGLES / 2 + i]` for a negative `i` and `finesine[angle - FINEANGLES / 2]` past
`finetangent`'s end, the values the native build reads: its lines, frames included, are the same.

`0005-doomu-wad-path.patch`, `d_main.c`: `IdentifyVersion` gives the path `$DOOMWADDIR/doomu.wad`
`strlen(DOOMWADDIR) + 1 + 8 + 1` bytes, one short of the ten characters of `/doomu.wad` and the
NUL, so the NUL lands one byte past the block in every build. glibc rounds a request of `R` bytes
up to `((R + 8 + 15) & ~15) - 8` usable ones, so the byte falls into the block's own slack unless
`strlen(DOOMWADDIR) % 16` is 14; then it clears the low byte of the next chunk's size, and malloc
aborts (`corrupted size vs. prev_size`): natively on every run, converted only when the neighbour,
a chunk of daslang's own, is later split or merged. The harness's own wad folder is 38
characters long and never met it. The patch budgets `1 + 9 + 1`, as `doom2.wad`'s path.
