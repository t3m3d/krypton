// Krypton in-browser runner - mini-interpreter for the lesson subset.
// Built with Krypton | krypton-lang.org
// Strategy: translate a useful subset of Krypton syntax to JS, then eval
// inside a closure with API helpers bound as locals.
//
// Out of scope (gated with a friendly message): match, struct, try/catch,
// k:fs, k:http, k:server, k:json, head:*. These need the real runtime.
(function () {
  function kbToJs(src) {
    var s = src;

    // 1. Mask string literals FIRST - else comment-strip eats // inside a
    //    string (lesson 19 has startsWith(line, "//")).
    var strs = [];
    s = s.replace(/"([^"\\]*(?:\\.[^"\\]*)*)"/g, function (m) {
      strs.push(m);
      return '__KSTR' + (strs.length - 1) + '__';
    });

    // 2. Strip // line comments.
    s = s.replace(/\/\/[^\n]*/g, '');

    // 3. Strip Krypton imports - stdlib modules not available in browser.
    s = s.replace(/^\s*import\s+__KSTR\d+__\s*$/gm, '');
    s = s.replace(/^\s*import\s+"[^"]+"\s*$/gm, '');

    // 4. func / fn declarations - also strip "name: TYPE" annotations
    //    from parameter lists (e.g. "f: closure" -> "f").
    function cleanParams(p) {
      return p.replace(/(\w+)\s*:\s*\w+/g, '$1');
    }
    s = s.replace(/\b(?:func|fn)\s+(\w+)\s*\(([^)]*)\)\s*\{/g,
      function (m, name, p) {
        return 'function ' + name + '(' + cleanParams(p) + ') {';
      });
    s = s.replace(/\b(?:func|fn)\s*\(([^)]*)\)\s*\{/g,
      function (m, p) { return 'function(' + cleanParams(p) + ') {'; });

    // 5. "go LABEL { ... }" -> plain "{ ... }" block. Browser can't do
    //    concurrent so we just run them sequentially.
    s = s.replace(/\bgo\s+\w+\s*\{/g, '{');

    // 6. Control flow. elif before if (else-if vs if branch order).
    s = s.replace(/\belif\s+([^{]+?)\s*\{/g, '} else if ($1) {');
    s = s.replace(/\bif\s+([^{]+?)\s*\{/g, 'if ($1) {');
    s = s.replace(/\belse\s*\{/g, 'else {');
    s = s.replace(/\bwhile\s+([^{]+?)\s*\{/g, 'while ($1) {');
    s = s.replace(/\bfor\s+(\w+)\s+in\s+([^{]+?)\s*\{/g,
                  'for (const $1 of $2) {');

    // 7. emit X -> return X  (Krypton emit returns from a func).
    s = s.replace(/\bemit\s+/g, 'return ');

    // 8. just run { body }  -> top-level block.
    s = s.replace(/\bjust\s+run\s*\{/g, '{');

    // 9. Restore string literals. Apply template-literal upgrade if the
    //    string contained ${...} interpolation.
    s = s.replace(/__KSTR(\d+)__/g, function (m, idx) {
      var orig = strs[+idx];
      if (orig.indexOf('${') !== -1) {
        return '`' + orig.slice(1, -1).replace(/`/g, '\\`') + '`';
      }
      return orig;
    });

    return s;
  }

  function buildApi(output) {
    function fmt(v) {
      if (v === null || v === undefined) return 'null';
      if (v instanceof Map) {
        var parts = [];
        v.forEach(function (val, k) { parts.push(k + ': ' + fmt(val)); });
        return '{' + parts.join(', ') + '}';
      }
      if (Array.isArray(v)) return '[' + v.map(fmt).join(', ') + ']';
      return String(v);
    }
    function emitLine() {
      var parts = [];
      for (var i = 0; i < arguments.length; i++) parts.push(fmt(arguments[i]));
      output.push(parts.join(' '));
    }

    function lenOf(x) {
      if (x === null || x === undefined) return 0;
      if (x instanceof Map || x instanceof Set) return x.size;
      return x.length;
    }

    // Krypton env: a string-encoded key=value list, one per line.
    function envSetStr(e, k, v) {
      e = (e === null || e === undefined) ? '' : String(e);
      if (e === '') return k + '=' + v;
      var lines = e.split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].indexOf(k + '=') === 0) {
          lines[i] = k + '=' + v;
          return lines.join('\n');
        }
      }
      lines.push(k + '=' + v);
      return lines.join('\n');
    }
    function envGetStr(e, k) {
      if (!e) return '';
      var lines = String(e).split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].indexOf(k + '=') === 0) {
          return lines[i].substring(k.length + 1);
        }
      }
      return '';
    }
    function envHasStr(e, k) {
      if (!e) return false;
      var lines = String(e).split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].indexOf(k + '=') === 0) return true;
      }
      return false;
    }

    return {
      // Output (kp = "Krypton print" w/ newline).
      kp: emitLine, pe: emitLine, print: emitLine,
      printLn: emitLine, printErr: emitLine,

      // Numerics / conversions.
      len: lenOf, length: lenOf, count: lenOf, size: lenOf,
      toInt: function (x) { return parseInt(x, 10); },
      toFloat: function (x) { return parseFloat(x); },
      toStr: function (x) { return String(x); },
      abs: Math.abs, min: Math.min, max: Math.max,
      pow: Math.pow, sqrt: Math.sqrt, floor: Math.floor, ceil: Math.ceil,
      round: Math.round,
      fromCharCode: String.fromCharCode,

      // Strings.
      indexOf: function (s, t) { return s.indexOf(t); },
      substring: function (s, i, j) {
        return j === undefined ? s.substring(i) : s.substring(i, j);
      },
      startsWith: function (s, p) { return s.startsWith(p); },
      endsWith: function (s, p) { return s.endsWith(p); },
      split: function (s, d) { return s.split(d); },
      trim: function (s) { return s.trim(); },
      upper: function (s) { return s.toUpperCase(); },
      lower: function (s) { return s.toLowerCase(); },
      toUpper: function (s) { return s.toUpperCase(); },
      toLower: function (s) { return s.toLowerCase(); },
      replaceAll: function (s, a, b) { return s.split(a).join(b); },

      // Booleans.
      isTruthy: function (x) { return !!x; },
      isFalsy: function (x) { return !x; },

      // String builder.
      sbNew: function () { return ''; },
      sbAppend: function (s, x) { return s + String(x); },
      sbToString: function (s) { return s; },

      // Lists (both Krypton naming styles).
      listNew: function () { return []; },
      listAdd: function (l, v) { l.push(v); return l; },
      listAppend: function (l, v) { l.push(v); return l; },
      listGet: function (l, i) { return l[i]; },
      listSet: function (l, i, v) { l[i] = v; return l; },
      listPop: function (l) { return l.pop(); },
      listLen: function (l) { return l.length; },
      listSize: function (l) { return l.length; },
      listSum: function (l) {
        if (typeof l === 'string') l = l.split(',').map(Number);
        var t = 0; for (var i = 0; i < l.length; i++) t += Number(l[i]);
        return t;
      },
      listReverse: function (l) {
        if (typeof l === 'string') return l.split(',').reverse().join(',');
        return l.slice().reverse();
      },

      // Pairs (Krypton: a pair stores value + position).
      pairNew: function (v, p) { return [v, p]; },
      pairVal: function (p) { return p[0]; },
      pairPos: function (p) { return p[1]; },

      // Maps (comma-format builtins).
      mapNew: function () { return new Map(); },
      mapSet: function (m, k, v) { m.set(k, v); return m; },
      mapGet: function (m, k) { return m.get(k); },
      hasKey: function (m, k) { return m.has(k); },
      keys: function (m) { return Array.from(m.keys()); },
      values: function (m) { return Array.from(m.values()); },

      // Environments - Krypton string-encoded key=value bag.
      envNew: function () { return ''; },
      envSet: envSetStr,
      envGet: envGetStr,
      envHas: envHasStr,

      // Line helpers.
      getLine: function (s, i) {
        var parts = String(s).split('\n');
        return i < parts.length ? parts[i] : '';
      },
      lineCount: function (s) {
        if (s === '' || s === null || s === undefined) return 0;
        return String(s).split('\n').length;
      },

      // Math helpers from k:math_utils (lesson 27).
      gcd: function (a, b) {
        a = Math.abs(a); b = Math.abs(b);
        while (b) { var t = b; b = a % b; a = t; }
        return a;
      },
      clamp: function (v, lo, hi) { return Math.max(lo, Math.min(hi, v)); },
      isPrime: function (n) {
        n = Number(n); if (n < 2) return false;
        if (n < 4) return true; if (n % 2 === 0) return false;
        for (var i = 3; i * i <= n; i += 2) if (n % i === 0) return false;
        return true;
      },

      // Range (lesson 23) - returns [start, ..., end-1].
      range: function (a, b) {
        var lo = b === undefined ? 0 : a;
        var hi = b === undefined ? a : b;
        var out = [];
        for (var i = lo; i < hi; i++) out.push(i);
        return out;
      },

      // FP helpers from k:fp (lesson 29 - comma-list higher-order).
      fpMap: function (xs, fn) {
        return xs.split(',').map(function (x) { return fn(x); }).join(',');
      },
      fpFilter: function (xs, fn) {
        return xs.split(',').filter(function (x) { return fn(x); }).join(',');
      },
      fpReduce: function (xs, init, fn) {
        return xs.split(',').reduce(function (a, x) { return fn(a, x); }, init);
      },

      // htmk — HTML emit DSL bindings (mirrors stdlib/htmk.k).
      htEscape: function (s) {
        return String(s).replace(/&/g, '&amp;')
                        .replace(/</g, '&lt;')
                        .replace(/>/g, '&gt;')
                        .replace(/"/g, '&quot;');
      },
      htAttr: function (name, val) {
        return ' ' + name + '="' + String(val)
          .replace(/&/g, '&amp;').replace(/</g, '&lt;')
          .replace(/>/g, '&gt;').replace(/"/g, '&quot;') + '"';
      },
      htEl:   function (tag, content) { return '<' + tag + '>' + content + '</' + tag + '>'; },
      htElA:  function (tag, attrs, content) { return '<' + tag + attrs + '>' + content + '</' + tag + '>'; },
      htVoid: function (tag, attrs) { return '<' + tag + attrs + '>'; },
      htDiv:  function (c) { return '<div>' + c + '</div>'; },
      htSpan: function (c) { return '<span>' + c + '</span>'; },
      htP:    function (c) { return '<p>' + c + '</p>'; },
      htH1:   function (c) { return '<h1>' + c + '</h1>'; },
      htH2:   function (c) { return '<h2>' + c + '</h2>'; },
      htH3:   function (c) { return '<h3>' + c + '</h3>'; },
      htH4:   function (c) { return '<h4>' + c + '</h4>'; },
      htUl:   function (c) { return '<ul>' + c + '</ul>'; },
      htOl:   function (c) { return '<ol>' + c + '</ol>'; },
      htLi:   function (c) { return '<li>' + c + '</li>'; },
      htA:    function (href, c) { return '<a href="' + href + '">' + c + '</a>'; },
      htBr:   function () { return '<br>'; },
      htHr:   function () { return '<hr>'; },
      htStyle: function (s) { return '<style>' + s + '</style>'; },
      htCode: function (c) { return '<code>' + c + '</code>'; },
      htPre:  function (c) { return '<pre>' + c + '</pre>'; },
      htEm:   function (c) { return '<em>' + c + '</em>'; },
      htStrong: function (c) { return '<strong>' + c + '</strong>'; },
      htMetaCharset: function (cs) { return '<meta charset="' + cs + '">'; },
      htMetaViewport: function () { return '<meta name="viewport" content="width=device-width, initial-scale=1.0">'; },
      htPage: function (title, headExtra, body) {
        return '<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8">' +
               '<meta name="viewport" content="width=device-width, initial-scale=1.0">' +
               '<title>' + title + '</title>' + (headExtra || '') +
               '</head><body>' + body + '</body></html>';
      },

      // Composition helpers (htmk additions; funcptr-friendly).
      htEach: function (list, fn) {
        var out = '';
        var lines = String(list).split('\n');
        for (var i = 0; i < lines.length; i++) {
          if (lines[i].length > 0) out += fn(lines[i]);
        }
        return out;
      },
      htWhen:    function (cond, html) { return cond ? html : ''; },
      htUnless:  function (cond, html) { return cond ? '' : html; },
      htEither:  function (cond, ifT, ifF) { return cond ? ifT : ifF; },
      htJoin:    function (list) {
        var out = '';
        var lines = String(list).split('\n');
        for (var i = 0; i < lines.length; i++) {
          if (lines[i].length > 0) out += lines[i];
        }
        return out;
      },
      htJoinSep: function (list, sep) {
        var parts = String(list).split('\n').filter(function (x) { return x.length > 0; });
        return parts.join(sep);
      },
      htWrap: function (list, before, after) {
        var out = '';
        var lines = String(list).split('\n');
        for (var i = 0; i < lines.length; i++) {
          if (lines[i].length > 0) out += before + lines[i] + after;
        }
        return out;
      },

      // kcss — CSS emit DSL bindings (mirrors stdlib/kcss.k).
      kcssDecl:  function (p, v) { return p + ':' + v + ';'; },
      kcssRule:  function (s, b) { return s + '{' + b + '}'; },
      kcssRoot:  function (d) { return ':root{' + d + '}'; },
      kcssVar:   function (n, v) { return '--' + n + ':' + v + ';'; },
      kcssUseVar: function (n) { return 'var(--' + n + ')'; },
      kcssMedia: function (q, b) { return '@media ' + q + '{' + b + '}'; },
      kcssOnMobile:  function (b) { return '@media (max-width:600px){' + b + '}'; },
      kcssOnTablet:  function (b) { return '@media (max-width:900px){' + b + '}'; },
      kcssOnDesktop: function (b) { return '@media (min-width:901px){' + b + '}'; },
      kcssKeyframes: function (n, b) { return '@keyframes ' + n + '{' + b + '}'; },
      kcssFrame: function (a, b) { return a + '{' + b + '}'; },
      kcssStyle: function (r) { return '<style>' + r + '</style>'; },
      kcssHover: function (s) { return s + ':hover'; },
      kcssFocus: function (s) { return s + ':focus'; },
      kcssActive: function (s) { return s + ':active'; },
      kcssBefore: function (s) { return s + '::before'; },
      kcssAfter:  function (s) { return s + '::after'; },
      kcssColor:    function (c) { return 'color:' + c + ';'; },
      kcssBg:       function (c) { return 'background:' + c + ';'; },
      kcssPadding:  function (p) { return 'padding:' + p + ';'; },
      kcssMargin:   function (m) { return 'margin:' + m + ';'; },
      kcssRadius:   function (r) { return 'border-radius:' + r + ';'; },
      kcssFontSize: function (s) { return 'font-size:' + s + ';'; },
      kcssDisplay:  function (d) { return 'display:' + d + ';'; },
      kcssWidth:    function (w) { return 'width:' + w + ';'; },
      kcssHeight:   function (h) { return 'height:' + h + ';'; },
      kcssRgba:     function (r, g, b, a) { return 'rgba(' + r + ',' + g + ',' + b + ',' + a + ')'; },
      kcssLinearGradient: function (deg, colors) { return 'linear-gradient(' + deg + ',' + colors + ')'; },

      // JSON emit (matches stdlib/k:json shape).
      jsonStr: function (s) { return JSON.stringify(String(s)); },
      jsonNum: function (n) { return String(Number(n)); },
      jsonBool: function (b) {
        var v = (b === '1' || b === 1 || b === true);
        return v ? 'true' : 'false';
      },
      jsonNull: function () { return 'null'; },
      jsonArray: function (commaList) {
        if (commaList === '' || commaList == null) return '[]';
        var items = String(commaList).split(',').map(function (x) {
          x = x.trim();
          if (x === '') return '""';
          if (/^-?\d+(\.\d+)?$/.test(x)) return x;
          if (x === 'true' || x === 'false' || x === 'null') return x;
          return JSON.stringify(x);
        });
        return '[' + items.join(',') + ']';
      },
      jsonObject: function (m) {
        if (!(m instanceof Map)) return '{}';
        var parts = [];
        m.forEach(function (v, k) {
          var key = JSON.stringify(String(k));
          var val;
          if (typeof v === 'number') val = String(v);
          else if (v === true || v === false || v === null) val = String(v);
          else val = JSON.stringify(String(v));
          parts.push(key + ':' + val);
        });
        return '{' + parts.join(',') + '}';
      },

      // No-op stubs (browser can't do these).
      argCount: function () { return 0; },
      arg: function () { return ''; },
      environ: function () { return ''; },
      readFile: function () { return ''; }
    };
  }

  function krun(src) {
    // Unsupported-feature gates — friendlier than a stack trace.
    // Detect WHICH feature blocks the runner and surface concrete next steps.
    function gate(featureName, why) {
      return {
        ok: false,
        output:
          '⚠ This lesson uses ' + featureName + ', which the in-browser ' +
          'runner does not support yet.\n\n' +
          why + '\n\n' +
          'Try it locally — install Krypton then run:\n' +
          '  kcc -r tutorial/<lesson>.k\n\n' +
          'Install: https://krypton-lang.org/downloads.html\n' +
          'Want to fund a real in-browser runtime (kcc → WASM)?\n' +
          '  https://krypton-lang.org/sponsor.html'
      };
    }
    if (/\bmatch\s+/.test(src)) {
      return gate('match expressions',
        'match needs real pattern-binding semantics, which the JS bridge ' +
        'cannot fake reliably. The WASM backend (in design) will run this ' +
        'natively.');
    }
    if (/\bstruct\s+/.test(src)) {
      return gate('structs',
        'Krypton structs have field offsets the bridge cannot replicate. ' +
        'Real runtime needed.');
    }
    if (/\btry\s*\{/.test(src)) {
      return gate('try / catch',
        'Krypton\'s exception model needs the runtime\'s unwinder; JS ' +
        'try/catch doesn\'t map cleanly to it.');
    }
    if (/\bk:fs\b/.test(src)) {
      return gate('the k:fs stdlib module',
        'File I/O. Browsers can\'t touch the filesystem.');
    }
    if (/\bk:http\b/.test(src)) {
      return gate('the k:http client',
        'Krypton\'s HTTP client shells out to curl. Run locally to see real ' +
        'network requests.');
    }
    if (/\bk:server\b/.test(src)) {
      return gate('the k:server module',
        'TCP sockets aren\'t available in browser WASM. Server programs ' +
        'need the real runtime + a host OS.');
    }
    // k:json is now supported in the runner (jsonStr/Num/Bool/Null/Array/Object).
    if (/\bhead:/.test(src)) {
      return gate('head: C-header imports',
        'These pull in platform-native C symbols (Win32, POSIX) that have ' +
        'no analog in the browser.');
    }

    var output = [];
    var api = buildApi(output);

    var js;
    try { js = kbToJs(src); }
    catch (e) {
      return { ok: false, output: 'Transpile error: ' + e.message };
    }
    try {
      // Bind every API name as a local var before user code runs. User
      // function declarations later in the source hoist over these, so
      // user-defined wrappers take precedence (lessons 16, 20 etc.).
      var apiKeys = Object.keys(api);
      var prelude = apiKeys.map(function (k) {
        return 'var ' + k + ' = __api__.' + k + ';';
      }).join('\n');
      var runner = new Function('__api__', prelude + '\n' + js);
      runner(api);
      return {
        ok: true,
        output: output.length ? output.join('\n') : '(no output)'
      };
    } catch (e) {
      var msg = output.join('\n');
      if (output.length) msg += '\n';
      return { ok: false, output: msg + 'Runtime error: ' + e.message };
    }
  }

  window.krun = krun;

  window.runK = function (btn) {
    var wrap = btn.parentElement;
    var code = wrap.querySelector('pre code.k');
    var out = wrap.querySelector('.run-out');
    if (!code || !out) return;
    var src = code.innerText || code.textContent;
    var label = btn.textContent;
    btn.disabled = true;
    btn.textContent = 'Running…';
    out.className = 'run-out';
    out.textContent = '';
    setTimeout(function () {
      var r = krun(src);
      out.textContent = r.output;
      out.className = 'run-out ' + (r.ok ? 'ok' : 'err');
      btn.disabled = false;
      btn.textContent = label;
    }, 10);
  };
})();
