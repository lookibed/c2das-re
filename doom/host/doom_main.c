// doom_main.c - the headless host of the native PureDOOM build.
//
// Copyright (C) 2026 the c2das-re authors. This file is part of the doom/ subtree of
// c2das-re, which links it with PureDOOM; it is free software under the GNU General Public
// License version 2, as published by the Free Software Foundation, the license of PureDOOM.
// It is distributed WITHOUT ANY WARRANTY; see PureDOOM's LICENSE for the details.
//
// main drives doom_init, then doom_force_update in a loop, one game tic per update outside a
// screen wipe, under a virtual clock that advances one tic (1/35 s) per update, so a run reads
// no wall time and repeats tic for tic. The program ends where Doom calls its exit callback:
// `-timedemo demoN` ends in I_Error's "timed N gametics in M realtics" and exit code -1.
// `-tics N` (the host's argument; Doom ignores it) ends the run with exit code 0 once Doom has
// run N game tics.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../fetch/PureDOOM/src/DOOM/DOOM.h"

// the most updates a run takes before the host gives up on Doom ever exiting
#define MAX_UPDATES 2000000

// the game tics Doom has run, g_game.c's
extern int gametic;

static long long virtual_usec = 0;

static void virtual_gettime(int* sec, int* usec)
{
    *sec = (int)(virtual_usec / 1000000);
    *usec = (int)(virtual_usec % 1000000);
}

static void flush_and_exit(int code)
{
    fflush(stdout);
    exit(code);
}

int main(int argc, char** argv)
{
    long long update;
    int tic_cap = 0;
    int i;

    for (i = 1; i < argc - 1; i++)
        if (strcmp(argv[i], "-tics") == 0)
            tic_cap = atoi(argv[i + 1]);
    doom_set_gettime(virtual_gettime);
    doom_set_exit(flush_and_exit);
    doom_init(argc, argv, 0);
    for (update = 0; update < MAX_UPDATES; update++)
    {
        doom_force_update();
        virtual_usec += 1000000 / 35;
        if (tic_cap > 0 && gametic >= tic_cap)
        {
            printf("host: stopped after %d tics\n", gametic);
            flush_and_exit(0);
        }
    }
    printf("host: Doom did not exit within %d updates\n", MAX_UPDATES);
    return 2;
}
