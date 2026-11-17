// Runs the translator page's examples in its interpreter as the page's Run does (web/ARCHITECTURE.md
// section 9): each example's module under the default knobs at /run/main.das, c2das-re's c_runtime
// module folder from c_runtime.json at /lib/c_runtime, `-load_module /lib/c_runtime /run/main.das`.
// One fresh runtime per example (a child node process), as the page uses one frame per run.
// usage: node run_examples.js <interp dir> <examples.json> <c_runtime.json> [<example id>]
//   without an id it runs every example and prints `<id> ok` or `<id> FAIL ...`; exits 1 on a failure
'use strict';
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
if (parseInt(process.versions.node, 10) < 22) {
  console.error('run_examples: node ' + process.versions.node + ' is older than 22 (VERSIONS.md)');
  process.exit(2);
}
const [interp, examplesPath, libPath, only] = process.argv.slice(2);
if (!interp || !examplesPath || !libPath) {
  console.error('usage: node run_examples.js <interp dir> <examples.json> <c_runtime.json> [<example id>]');
  process.exit(2);
}
const examples = JSON.parse(fs.readFileSync(examplesPath, 'utf8')).examples;
if (only) {
  const e = examples.find(x => x.id === only);
  const lib = JSON.parse(fs.readFileSync(libPath, 'utf8'));
  let out = '';
  globalThis.Module = {
    noInitialRun: true,
    print: t => { out += t + '\n'; },
    printErr: t => { out += t + '\n'; },
    onRuntimeInitialized() {
      const FS = Module.FS;
      FS.mkdirTree('/run');
      FS.writeFile('/run/main.das', e.das);
      for (const p in lib) {
        FS.mkdirTree(path.posix.dirname('/lib/c_runtime/' + p));
        FS.writeFile('/lib/c_runtime/' + p, lib[p]);
      }
      let code;
      try { code = Module.callMain(['-load_module', '/lib/c_runtime', '/run/main.das']) || 0; } catch (x) { code = x && typeof x.status === 'number' ? x.status : String(x); }
      process.stdout.write(JSON.stringify({ code, out }));
      process.exit(0);
    }
  };
  require(path.resolve(interp, 'daslang_static.js'));
} else {
  let failed = 0;
  for (const e of examples) {
    const r = spawnSync(process.execPath, [__filename, interp, examplesPath, libPath, e.id], { encoding: 'utf8', timeout: 300000 });
    let got = null;
    try { got = JSON.parse(r.stdout); } catch (x) { /* reported below */ }
    if (got && got.code === 0 && got.out === e.output) { console.log(e.id + ' ok'); continue; }
    failed++;
    console.log(e.id + ' FAIL ' + JSON.stringify(got || { stdout: r.stdout, stderr: r.stderr }).slice(0, 400));
  }
  process.exit(failed ? 1 : 0);
}
