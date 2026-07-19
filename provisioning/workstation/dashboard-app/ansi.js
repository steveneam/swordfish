// ansi.js - minimal SGR -> HTML for tmux capture-pane -e output.
// capture-pane emits a FLAT screen dump: SGR color/attr sequences only, never
// cursor addressing - so this stays ~120 lines instead of a VT parser
// (xterm.js was rejected: 280KB plus an input layer we would have to keep
// disconnected; this dashboard's terminals are read-only by construction).
//
// SECURITY (load-bearing): pane text is attacker-influenceable - agents print
// arbitrary text. Everything is HTML-escaped BEFORE wrapping, and style values
// are built only from clamped integers and fixed CSS custom-property names, so
// no raw input ever reaches markup or a style attribute. The dashboard check
// script feeds an XSS probe through here and asserts it comes out escaped.

(function (root) {
  'use strict';

  // non-SGR escapes (OSC titles, charset shifts, cursor/erase) -> dropped
  var STRIP = /\x1b(?:\][^\x07\x1b]*(?:\x07|\x1b\\)?|[()][0B]|\[[0-9;?]*[A-HJKSTfhilnsu]|[=>78])/g;
  var SGR = /\x1b\[([0-9;]*)m/g;

  function esc(s) {
    return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }

  function fresh() {
    return { fg: null, bg: null, bold: false, dim: false, it: false,
             ul: false, rev: false };
  }

  var rgb = function (r, g, b) {
    return 'rgb(' + (Math.max(0, Math.min(255, r | 0))) + ',' +
      (Math.max(0, Math.min(255, g | 0))) + ',' + (Math.max(0, Math.min(255, b | 0))) + ')';
  };

  function pal(i) { return 'var(--t' + (Math.max(0, Math.min(15, i | 0))) + ')'; }

  function xterm256(n) {
    n = Math.max(0, Math.min(255, n | 0));
    if (n < 16) return pal(n);
    if (n < 232) {
      var q = [0, 95, 135, 175, 215, 255], k = n - 16;
      return rgb(q[(k / 36) | 0], q[((k / 6) | 0) % 6], q[k % 6]);
    }
    var g = 8 + (n - 232) * 10;
    return rgb(g, g, g);
  }

  function apply(st, params) {
    var p = (params || '0').split(';').map(Number);
    for (var i = 0; i < p.length; i++) {
      var c = p[i] || 0;
      if (c === 0) { var f = fresh(); for (var k in f) st[k] = f[k]; }
      else if (c === 1) st.bold = true;
      else if (c === 2) st.dim = true;
      else if (c === 3) st.it = true;
      else if (c === 4) st.ul = true;
      else if (c === 7) st.rev = true;
      else if (c === 22) { st.bold = false; st.dim = false; }
      else if (c === 23) st.it = false;
      else if (c === 24) st.ul = false;
      else if (c === 27) st.rev = false;
      else if (c >= 30 && c <= 37) st.fg = pal(c - 30);
      else if (c >= 90 && c <= 97) st.fg = pal(c - 90 + 8);
      else if (c >= 40 && c <= 47) st.bg = pal(c - 40);
      else if (c >= 100 && c <= 107) st.bg = pal(c - 100 + 8);
      else if (c === 39) st.fg = null;
      else if (c === 49) st.bg = null;
      else if (c === 38 || c === 48) {
        var isFg = (c === 38);
        if (p[i + 1] === 5) {
          var v5 = xterm256(p[i + 2]);
          if (isFg) st.fg = v5; else st.bg = v5;
          i += 2;
        } else if (p[i + 1] === 2) {
          var v2 = rgb(p[i + 2], p[i + 3], p[i + 4]);
          if (isFg) st.fg = v2; else st.bg = v2;
          i += 4;
        }
      }
    }
  }

  function span(st, inner) {
    var fg = st.fg, bg = st.bg;
    if (st.rev) { var t = fg; fg = bg || 'var(--term-bg)'; bg = t || 'var(--term-fg)'; }
    var s = [];
    if (fg) s.push('color:' + fg);
    if (bg) s.push('background:' + bg);
    if (st.bold) s.push('font-weight:600');
    if (st.dim) s.push('opacity:.6');
    if (st.ul) s.push('text-decoration:underline');
    if (st.it) s.push('font-style:italic');
    return s.length ? '<span style="' + s.join(';') + '">' + inner + '</span>' : inner;
  }

  function ansiToHtml(raw) {
    var text = String(raw).replace(STRIP, '');
    var st = fresh(), out = '', last = 0, m;
    SGR.lastIndex = 0;
    while ((m = SGR.exec(text))) {
      if (m.index > last) out += span(st, esc(text.slice(last, m.index)));
      apply(st, m[1]);
      last = m.index + m[0].length;
    }
    if (last < text.length) out += span(st, esc(text.slice(last)));
    return out;
  }

  var api = { ansiToHtml: ansiToHtml, escapeHtml: esc };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.Ansi = api;
})(this);
