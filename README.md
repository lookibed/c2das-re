# c2das-re in the browser

The GitHub Pages site of [c2das-re](https://github.com/lookibed/c2das-re): its translator's C-IR-to-daslang
half and c2das-ports' Lua, compiled to WebAssembly. Generated, never hand-edited: c2das-re's
`scripts/build_translator_site.sh --ports <c2das-ports> --interp <dir> --pages <this checkout>` writes every
file here (sources: c2das-re's `web/translator/`), from c2das-re b6381241a5 and c2das-ports 863eef7a32, by daScript
b7d8f6f52f's libc++ wasm host with emscripten 5.0.7. `daslang_static.*` is daScript b7d8f6f52f's playground
interpreter with c2das-re 29c0f671ed's crt, built by `web/translator/interp/build_interp.sh`. `cm/` is
daScript's CodeMirror bundle (MIT) and daslang mode (BSD-3).
