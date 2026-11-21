// CodeMirror simple modes for the translator page: C (the input) and Lua (the console). The das
// output uses daScript's own daslang mode (files/cm/daslang-mode.js, copied at build time).
(function () {
  var cKeywords = /(?:auto|break|case|char|const|continue|default|do|double|else|enum|extern|float|for|goto|if|inline|int|long|register|restrict|return|short|signed|sizeof|static|struct|switch|typedef|union|unsigned|void|volatile|while|_Bool|NULL)\b/;
  CodeMirror.defineSimpleMode('c-lite', {
    start: [
      { regex: /\/\/.*/, token: 'comment' },
      { regex: /\/\*/, token: 'comment', next: 'comment' },
      { regex: /#\s*\w+/, token: 'meta' },
      { regex: /"(?:[^\\"]|\\.)*"?/, token: 'string' },
      { regex: /'(?:[^\\']|\\.)*'?/, token: 'string' },
      { regex: cKeywords, token: 'keyword' },
      { regex: /0x[a-f\d]+|[-+]?(?:\.\d+|\d+\.?\d*)(?:e[-+]?\d+)?[uUlLfF]*/i, token: 'number' },
      { regex: /[A-Z_][A-Z0-9_]{2,}\b/, token: 'variable-3' },
      { regex: /[a-z_]\w*(?=\s*\()/i, token: 'def' },
    ],
    comment: [{ regex: /.*?\*\//, token: 'comment', next: 'start' }, { regex: /.*/, token: 'comment' }],
    meta: { lineComment: '//' },
  });
  CodeMirror.defineSimpleMode('lua-lite', {
    start: [
      { regex: /--.*/, token: 'comment' },
      { regex: /"(?:[^\\"]|\\.)*"?|'(?:[^\\']|\\.)*'?/, token: 'string' },
      { regex: /(?:and|break|do|else|elseif|end|false|for|function|goto|if|in|local|nil|not|or|repeat|return|then|true|until|while)\b/, token: 'keyword' },
      { regex: /[-+]?(?:\.\d+|\d+\.?\d*)(?:e[-+]?\d+)?/i, token: 'number' },
      { regex: /[a-z_]\w*(?=\s*\()/i, token: 'def' },
    ],
    meta: { lineComment: '--' },
  });
})();
