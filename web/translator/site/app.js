// The translator page (c2das-re web/ARCHITECTURE.md section 8). examples.json holds each example's C,
// the C-IR clang gave at build time, the module under the defaults and the converted program's
// output; translator.wasm (c2das-re's converter/cir_emit.das, compiled to wasm64) spells the module
// again for the knobs, and lua.wasm (c2das-ports' Lua, compiled to wasm64) runs the console's Lua.
// Both programs poll a request file in their in-memory file system each animation frame. A request
// unanswered within DEADLINE_MS of visible time (a hidden tab runs no frames) is reported and frees
// the controls for the next one; only a program that aborts stops the page.
(function () {
  'use strict';
  var $ = function (id) { return document.getElementById(id); };
  var KNOBS = ['switch_dispatch', 'checks', 'loops', 'param_writes', 'first_member', 'past_end', 'fn_macros', 'inline_helpers', 'solid_context'];
  var DEFAULTS = { switch_dispatch: 'chain', checks: 'safe', loops: 'range', param_writes: 'in-place', first_member: 'addr', past_end: 'call', fn_macros: 'fold', inline_helpers: false, solid_context: true };
  var PRESETS = { readable: {}, fast: { checks: 'off' } };
  var DEADLINE_MS = 20000;
  var data = null, current = null, translator = null, busy = false, pending = false, dead = null;

  var cEditor = CodeMirror($('csrc'), { mode: 'c-lite', theme: 'forge', readOnly: true, lineNumbers: true });
  var dasView = CodeMirror($('tab-das'), { mode: 'daslang', theme: 'forge', readOnly: true, lineNumbers: true });
  var luaEditor = CodeMirror($('lua-src'), { mode: 'lua-lite', theme: 'forge', lineNumbers: true, indentUnit: 4 });

  function status(text, err) { var s = $('status'); s.textContent = text; s.className = 'status' + (err ? ' err' : ''); }
  function knobEls(name) { return document.querySelectorAll('[data-knob="' + name + '"]'); }
  function knobValue(name) {
    var el = knobEls(name)[0];
    return el.type === 'checkbox' ? el.checked : el.value;
  }
  function setKnob(name, value) {
    var el = knobEls(name)[0];
    if (el.type === 'checkbox') el.checked = !!value; else el.value = value;
  }

  // the example's own sidecar with every knob written over it
  function sidecar() {
    var side = JSON.parse(JSON.stringify(current.sidecar || {}));
    KNOBS.forEach(function (k) { side[k] = knobValue(k); });
    return JSON.stringify(side);
  }
  function atDefaults() { return KNOBS.every(function (k) { return knobValue(k) === DEFAULTS[k]; }); }

  // a line diff of a against b, the lines LCS keeps as context
  function diffLines(a, b) {
    var x = a.split('\n'), y = b.split('\n'), n = x.length, m = y.length;
    var t = new Array((n + 1) * (m + 1)).fill(0);
    for (var i = n - 1; i >= 0; i--) for (var j = m - 1; j >= 0; j--)
      t[i * (m + 1) + j] = x[i] === y[j] ? t[(i + 1) * (m + 1) + j + 1] + 1 : Math.max(t[(i + 1) * (m + 1) + j], t[i * (m + 1) + j + 1]);
    var out = [], ii = 0, jj = 0, changed = 0;
    while (ii < n || jj < m) {
      if (ii < n && jj < m && x[ii] === y[jj]) { out.push(['ctx', '  ' + x[ii]]); ii++; jj++; }
      else if (jj < m && (ii >= n || t[ii * (m + 1) + jj + 1] >= t[(ii + 1) * (m + 1) + jj])) { out.push(['add', '+ ' + y[jj]]); jj++; changed++; }
      else { out.push(['del', '- ' + x[ii]]); ii++; changed++; }
    }
    return { lines: out, changed: changed };
  }
  function showDiff(text) {
    var pre = $('tab-diff');
    pre.textContent = '';
    if (atDefaults()) { pre.textContent = 'The knobs are at their defaults: this is the module c2das-re writes by default.'; return; }
    var d = diffLines(current.das, text);
    var head = document.createElement('span');
    head.className = 'ctx';
    head.textContent = d.changed + ' lines differ from the defaults\n\n';
    pre.appendChild(head);
    d.lines.forEach(function (l) {
      var s = document.createElement('span');
      s.className = l[0];
      s.textContent = l[1] + '\n';
      pre.appendChild(s);
    });
  }

  // the module shown: a fresh one, or none with the reason in the diff tab
  function showModule(text, note) {
    dasView.setValue(text);
    if (note) { $('tab-diff').textContent = note; } else { showDiff(text); }
  }

  // one request to translator.wasm: the C-IR and the sidecar into /io, the module or the error back
  function convert() {
    if (dead) { status(dead, true); return; }
    if (!translator || !current) return;
    if (busy) { pending = true; return; }
    busy = true;
    var FS = translator.FS, t0 = performance.now();
    ['done', 'out.das', 'out.err'].forEach(function (f) { try { FS.unlink('/io/' + f); } catch (e) {} });
    FS.writeFile('/io/in.cir.json', current.cir);
    FS.writeFile('/io/sidecar.c2das', sidecar());
    FS.writeFile('/io/go', '');
    status('translating...');
    (function poll() {
      if (dead) { busy = false; return; }
      var done = null;
      try { done = FS.readFile('/io/done', { encoding: 'utf8' }); } catch (e) {
        if (document.hidden) t0 = performance.now();
        if (performance.now() - t0 > DEADLINE_MS) {
          busy = false;
          pending = false;
          status('the translator did not answer in ' + DEADLINE_MS / 1000 + ' s; change a knob to try again', true);
          return;
        }
        return void setTimeout(poll, 4);
      }
      var ms = performance.now() - t0, err = null, text = null;
      try { err = FS.readFile('/io/out.err', { encoding: 'utf8' }); } catch (e) {}
      try { text = FS.readFile('/io/out.das', { encoding: 'utf8' }); } catch (e) {}
      busy = false;
      // a newer request waits: this answer is for knobs or an example no longer shown
      if (pending) { pending = false; convert(); return; }
      if (err) {
        status(err, true);
        showModule('', 'No module: ' + err);
        $('timing').textContent = '';
      } else {
        showModule(text);
        status('ready');
        $('timing').textContent = 'translated in ' + ms.toFixed(0) + ' ms (' + (parseInt(done, 10) / 1000).toFixed(0) +
          ' ms in the translator), ' + text.split('\n').length + ' lines';
      }
    })();
  }

  function selectExample(id) {
    current = data.examples.filter(function (e) { return e.id === id; })[0];
    cEditor.setValue(current.c);
    $('cfile').textContent = '(' + current.file + ')';
    $('about').textContent = current.about;
    $('tab-cir').textContent = JSON.stringify(JSON.parse(current.cir), null, 1);
    $('tab-output').textContent = 'The converted program, run by daslang\'s interpreter when the page was built:\n\n' + current.output;
    if (!busy) showModule(current.das);
    convert();
  }

  function applyPreset(name) {
    var p = PRESETS[name] || {};
    KNOBS.forEach(function (k) { setKnob(k, k in p ? p[k] : DEFAULTS[k]); });
    convert();
  }

  // tabs
  Array.prototype.forEach.call(document.querySelectorAll('#tabs button'), function (b) {
    b.addEventListener('click', function () {
      Array.prototype.forEach.call(document.querySelectorAll('#tabs button'), function (o) { o.classList.toggle('on', o === b); });
      ['das', 'diff', 'cir', 'output'].forEach(function (t) { $('tab-' + t).hidden = t !== b.dataset.tab; });
      if (b.dataset.tab === 'das') dasView.refresh();
    });
  });
  KNOBS.forEach(function (k) { knobEls(k)[0].addEventListener('change', convert); });
  $('preset').addEventListener('change', function () { applyPreset(this.value); });
  $('example').addEventListener('change', function () { selectExample(this.value); });

  // the Lua console: lua.wasm is loaded on its first run; a failed load is tried again on the next
  var luaLoading = null, luaDead = null;
  function luaOut(line) { $('lua-out').textContent += line + '\n'; }
  function loadLua() {
    if (luaLoading) return luaLoading;
    $('lua-status').textContent = 'loading Lua (wasm64)...';
    luaLoading = new Promise(function (resolve, reject) {
      var s = document.createElement('script');
      s.src = 'lua.js';
      s.onload = function () {
        createLua({ print: luaOut, printErr: luaOut, onAbort: function (what) { luaDead = 'Lua stopped: ' + what + '; reload the page'; } })
          .then(function (m) { m.FS.mkdirTree('/io'); resolve(m); }, reject);
      };
      s.onerror = function () { reject(new Error('lua.js did not load')); };
      document.head.appendChild(s);
    });
    luaLoading.catch(function () { luaLoading = null; });
    return luaLoading;
  }
  $('lua-run').addEventListener('click', function () {
    var btn = this;
    btn.disabled = true;
    loadLua().then(function (m) {
      $('lua-out').textContent = '';
      var t0 = performance.now();
      try { m.FS.unlink('/io/lua.done'); } catch (e) {}
      m.FS.writeFile('/io/script.lua', luaEditor.getValue());
      m.FS.writeFile('/io/lua.go', '');
      (function poll() {
        try { m.FS.stat('/io/lua.done'); } catch (e) {
          if (document.hidden) t0 = performance.now();
          if (luaDead) { $('lua-status').textContent = luaDead; return; }
          if (performance.now() - t0 <= DEADLINE_MS) return void setTimeout(poll, 4);
          $('lua-status').textContent = 'Lua did not answer in ' + DEADLINE_MS / 1000 + ' s (a loop without end?)';
          btn.disabled = false;
          return;
        }
        $('lua-status').textContent = 'ran in ' + (performance.now() - t0).toFixed(0) + ' ms';
        btn.disabled = false;
      })();
    }, function (e) { $('lua-status').textContent = 'Lua did not load: ' + e; btn.disabled = false; });
  });
  $('lua-example').addEventListener('change', function () {
    var id = this.value;
    luaEditor.setValue(data.lua.filter(function (e) { return e.id === id; })[0].code);
  });

  // the page's data, the build's commits and the translator
  Promise.all([
    fetch('examples.json').then(function (r) { return r.json(); }).catch(function (e) { throw new Error('the examples did not load: ' + e); }),
    fetch('build.json').then(function (r) { return r.json(); }).catch(function () { return null; })])
    .then(function (res) {
      data = res[0];
      data.examples.forEach(function (e) { $('example').add(new Option(e.title, e.id)); });
      data.lua.forEach(function (e) { $('lua-example').add(new Option(e.title, e.id)); });
      luaEditor.setValue(data.lua[0].code);
      if (res[1]) {
        var b = res[1];
        $('footer').insertBefore(document.createTextNode('Built from c2das-re ' + b.c2das_re + ' with daScript ' + b.daslang +
          ' and emscripten ' + b.emscripten + '; Lua from c2das-ports ' + b.ports + '. '), $('footer').firstChild);
      }
      selectExample(data.examples[0].id);
      return createTranslator({
        print: function (l) { console.log('[translator] ' + l); },
        printErr: function (l) { console.warn('[translator] ' + l); },
        onAbort: function (what) { dead = 'the translator stopped: ' + what + '; reload the page'; status(dead, true); }
      }).catch(function (e) { throw new Error('the translator did not load: ' + e); });
    })
    .then(function (m) {
      m.FS.mkdirTree('/io');
      translator = m;
      window.translator = m;
      status('ready');
      convert();
    }, function (e) { status(String(e.message || e), true); });
})();
