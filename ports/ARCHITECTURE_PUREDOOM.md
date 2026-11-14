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
- `vendor_runtime.das` - the runtime a folder of converted code runs on without a c2das-re
  checkout (the ports repository's `puredoom-readable/`): `c_runtime/` and dasCRuntime's
  descriptor, `CMakeLists.txt` and `src/`, copied as they are into `<into>/`, with the commit in
  `<into>/c2das-re.commit` (`runtime_files`, `vendor_runtime`). The copy builds `crt` with cmake
  against any built daScript, since dasCRuntime's `CMakeLists.txt` takes `DASLANG_ROOT`; it holds
  no built module, so the folder builds its own against the daslang that runs it (a module and its
  daslang share one ABI). A runtime file the copy would not write refuses it before the first
  write; removing it is left to the folder's owner. `tests/test_vendor_runtime.das` covers it.

## 2. The publish

`publish.das` publishes PureDOOM last, after Lua and the compare projects, under the name
`puredoom`. Unless `--no-convert`, it runs the harness from the repository root: `doom/fetch.sh`
(the pinned commit, the patches, freedoom), then per variant (`ARCHITECTURE_VARIANTS.md`), each
run taking `--variant <its file> --layout <its layout>`: `doom/run.das --convert` (the layout into
`doom/work/variants/<v>/<layout>/`; its log's `program (<layout>): N files` line is the verdict,
since its exit code also fails on the units alone, `program_converted`), then `doom/run.das --run
--tier <tier> --demo <N>` for each demo 1 to 3 under `interp`, `jit`, `exe` and `aot`. Each run's verdict is its summary line without the seconds (`N tics in
sync`, or `fails: ` and the desync or the exit), so an unchanged tree writes an unchanged README;
the verdicts go to `doom/work/variants/<v>/publish_sync.txt`, and the conversion's stamp to
`doom/work/publish.generation`, which `--no-convert` requires as it does for Lua. A demo out of sync
is a cell of the README's table, not a failed publish.

The directory holds:

- per variant `<v>/`: `doom/`, the variant's tree as its `program.modules.txt` lists it, with its
  `program.layout.txt` (the C-IR, the native build and the run folders stay out); `doom.c2das`, the
  sidecar it converted under (`published_sidecar`); `variant.json`.
- `patches/`, every `doom/patches/*.patch`; `LICENSE`, the fetched commit's `LICENSE` (GPL-2).
- `README.md`: the variants section (`ARCHITECTURE_VARIANTS.md` section 3), the pin, each patch with
  its note (its first line and its `- ` items), the generating commit, how `doom/fetch.sh` gets
  freedoom2.wad and how a run links it, the run commands under each tier, a sync table per variant
  and the frame rate.

No WAD is published: the harness's runs read the wad from `doom/fetch/wads/`, and only the files
above are copied. The frame-rate section renders `doom/results_linux.json` (`doom/fps.das`'s
`render_fps`) under the commit the capture names, with the output-changed note when the converter
changed between that commit and the published one; the publish times nothing. The variants table
falls back, for `readable`, to that capture (the default conversion's) and, for `fast`, to
`doom/work/variants/fast/results_linux.json`, `doom/run.das --fps --variant`'s capture, when the
search left one there: per tier the geometric mean over the demos of the native frame rate over
the tier's (`slowdown`).
