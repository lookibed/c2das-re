# ports Architecture: PureDOOM

Read `ARCHITECTURE.md` (this folder) first. This companion holds how the publisher writes the
`puredoom/` directory of the ports repository from the `doom/` harness (`doom/ARCHITECTURE.md`).

## 1. File charters

- `puredoom.das` - the texts of PureDOOM's directory: the tiers and demos a publish holds to the
  reference logs (`SYNC_TIERS`, `SYNC_DEMOS`), a run's verdict (`sync_verdict`), the record of the
  verdicts (`sync_record`, `read_sync`), the conversion's verdict (`program_converted`), a patch's note (`patch_note`) and the README
  (`puredoom_readme_text`). It runs and reads nothing.
- `tests/test_puredoom.das` - those functions over fixed harness output, patch text and README
  inputs.

## 2. The publish

`publish.das` publishes PureDOOM last, after Lua and the compare projects, under the name
`puredoom`. Unless `--no-convert`, it runs the harness from the repository root: `doom/fetch.sh`
(the pinned commit, the patches, freedoom), `doom/run.das --convert` (the source layout into
`doom/work/source/`; its log's `program (source): N files` line is the verdict, since its exit code
also fails on the units alone, `program_converted`), then `doom/run.das --run --tier <tier> --demo <N>` for each demo 1 to 3 under
`interp`, `jit` and `exe`. Each run's verdict is its summary line without the seconds (`N tics in
sync`, or `fails: ` and the desync or the exit), so an unchanged tree writes an unchanged README;
the verdicts go to `doom/work/publish_sync.txt`, and the conversion's stamp to
`doom/work/publish.generation`, which `--no-convert` requires as it does for Lua. A demo out of sync
is a cell of the README's table, not a failed publish.

The directory holds:

- `doom/`: the source layout's tree as `doom/work/source/program.modules.txt` lists it, with its
  `program.layout.txt`; the C-IR, the native build and the run folders stay out.
- `doom.c2das`, the sidecar; `patches/`, every `doom/patches/*.patch`; `LICENSE`, the fetched
  commit's `LICENSE` (GPL-2).
- `README.md`: the pin, each patch with its note (its first line and its `- ` items), the
  generating commit, how `doom/fetch.sh` gets freedoom2.wad and how a run links it, the run
  commands under each tier, the sync table and the frame rate.

No WAD is published: the harness's runs read the wad from `doom/fetch/wads/`, and only the files
above are copied. The frame-rate section renders `doom/results_linux.json` (`doom/fps.das`'s
`render_fps`) under the commit the capture names, with the output-changed note when the converter
changed between that commit and the published one; the publish times nothing.
