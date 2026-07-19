// charts.js - hand-rolled SVG small multiples for the cockpit (dataviz-skill
// method: thin marks, recessive grid, one hue per chart, status colors only
// for status, hover tooltip layer by default). Values are numbers from our
// own collectors - nothing user-shaped enters the SVG.
//
// Series data: [{ts, v}] (epoch seconds, number|null). Nulls break the line
// honestly rather than interpolating over a gap.

(function (root) {
  'use strict';

  var registry = new Map(); // chart id -> {pts, fmt, label}
  var seq = 0;

  function fmtVal(kind, v) {
    if (v == null) return '—';
    if (kind === 'pct') return (Math.round(v * 10) / 10) + '%';
    if (kind === 'gib') return (v / 1073741824).toFixed(1) + ' GiB';
    if (kind === 'gb') return Math.round(v / 1e9) + ' GB';
    if (kind === 'bytes') {
      var u = ['B', 'KB', 'MB', 'GB', 'TB'], i = 0, n = v;
      while (n >= 1024 && i < u.length - 1) { n /= 1024; i++; }
      return (i ? n.toFixed(1) : n) + ' ' + u[i];
    }
    if (kind === 'aud') return 'AUD ' + (Math.round(v * 100) / 100);
    return String(Math.round(v * 100) / 100);
  }

  function fmtTime(ts) {
    return new Intl.DateTimeFormat('en-AU', {
      timeZone: 'Australia/Sydney', weekday: 'short',
      hour: '2-digit', minute: '2-digit', hour12: false
    }).format(new Date(ts * 1000));
  }

  // compact date+time for a chart's x-axis ticks ("19/7 22:01")
  function fmtAxis(ts) {
    var parts = new Intl.DateTimeFormat('en-AU', {
      timeZone: 'Australia/Sydney', day: 'numeric', month: 'numeric',
      hour: '2-digit', minute: '2-digit', hour12: false
    }).formatToParts(new Date(ts * 1000));
    var o = {};
    parts.forEach(function (x) { o[x.type] = x.value; });
    return o.day + '/' + o.month + ' ' + o.hour + ':' + o.minute;
  }

  function scale(pts, optMax, optMin) {
    var vs = pts.map(function (p) { return p.v; }).filter(function (v) { return v != null; });
    var hi = optMax != null ? optMax : Math.max.apply(null, vs.concat([1]));
    var lo = optMin != null ? optMin : 0;
    if (hi === lo) hi = lo + 1;
    return { lo: lo, hi: hi };
  }

  function pathFor(pts, w, h, sc, pad) {
    pad = pad || 2;
    var line = '', area = '', started = false, firstX = null, lastX = null;
    var n = Math.max(1, pts.length - 1);
    for (var i = 0; i < pts.length; i++) {
      var v = pts[i].v;
      if (v == null) { started = false; continue; }
      var x = (i / n) * w;
      var y = h - pad - ((v - sc.lo) / (sc.hi - sc.lo)) * (h - pad * 2);
      line += (started ? 'L' : 'M') + x.toFixed(1) + ',' + y.toFixed(1);
      if (!started && firstX == null) firstX = x;
      started = true;
      lastX = x;
    }
    if (line && firstX != null) {
      area = line + 'L' + lastX.toFixed(1) + ',' + h + 'L' + firstX.toFixed(1) + ',' + h + 'Z';
    }
    return { line: line, area: area };
  }

  // small sparkline (tiles, fleet metrics). status: '', 'good', 'warn', 'bad'
  function spark(pts, opts) {
    opts = opts || {};
    if (!pts || !pts.length) return '';
    var w = opts.w || 240, h = opts.h || 40;
    var sc = scale(pts, opts.max, opts.min);
    var p = pathFor(pts, w, h, sc);
    if (!p.line) return '';
    var id = 'c' + (++seq);
    registry.set(id, { pts: pts, fmt: opts.fmt || 'num', label: opts.label || '' });
    return '<svg class="spark ' + (opts.status || '') + '" data-chart="' + id +
      '" viewBox="0 0 ' + w + ' ' + h + '" preserveAspectRatio="none" role="img"' +
      ' aria-label="' + (opts.label || 'trend') + '">' +
      '<path class="fill" d="' + p.area + '"/><path class="line" d="' + p.line + '"/></svg>';
  }

  // larger chart with a time axis, ~3 gridlines, optional dashed cap line.
  // Labels live in an HTML overlay, never inside the stretched SVG - a
  // preserveAspectRatio=none svg distorts any <text> it contains.
  function timeline(pts, opts) {
    opts = opts || {};
    if (!pts || !pts.length) return '<p class="dim">no history yet</p>';
    var w = opts.w || 640, h = opts.h || 120;
    var sc = scale(pts, opts.max, opts.min);
    var p = pathFor(pts, w, h, sc, 3);
    var id = 'c' + (++seq);
    registry.set(id, { pts: pts, fmt: opts.fmt || 'num', label: opts.label || '' });
    var svg = '<svg class="chart" data-chart="' + id + '" viewBox="0 0 ' + w + ' ' + h +
      '" preserveAspectRatio="none" style="height:' + h + 'px" role="img" aria-label="' +
      (opts.label || 'chart') + '">';
    var labels = '';
    for (var g = 1; g <= 3; g++) {
      var gy = (h / 4) * g;
      var gv = sc.hi - ((sc.hi - sc.lo) / 4) * g;
      svg += '<line class="gridline" x1="0" y1="' + gy.toFixed(1) + '" x2="' + w + '" y2="' + gy.toFixed(1) + '"/>';
      labels += '<span class="glabel" style="top:' + ((gy / h) * 100).toFixed(1) + '%">' +
        fmtVal(opts.fmt || 'num', gv) + '</span>';
    }
    if (opts.cap != null && opts.cap >= sc.lo && opts.cap <= sc.hi) {
      var cy = h - 3 - ((opts.cap - sc.lo) / (sc.hi - sc.lo)) * (h - 6);
      svg += '<line class="cap-line" x1="0" y1="' + cy.toFixed(1) + '" x2="' + w + '" y2="' + cy.toFixed(1) + '"/>';
      labels += '<span class="glabel cap" style="top:' + ((cy / h) * 100).toFixed(1) + '%">' +
        (opts.capLabel || 'cap') + '</span>';
    }
    svg += '<path class="fill" d="' + p.area + '"/><path class="line" d="' + p.line + '"/></svg>';
    var t0 = pts[0].ts, tm = pts[(pts.length - 1) >> 1].ts, t1 = pts[pts.length - 1].ts;
    return '<div class="chart-wrap">' + svg + labels +
      '<div class="chart-x"><span>' + fmtAxis(t0) + '</span><span>' + fmtAxis(tm) +
      '</span><span>' + fmtAxis(t1) + '</span></div></div>';
  }

  // bar strip (failed auth per run): right-aligned, fixed slot width, so a
  // young history renders a few thin bars at the right instead of giant blocks
  function bars(pts, opts) {
    opts = opts || {};
    if (!pts || !pts.length) return '<p class="dim">no history yet</p>';
    var w = opts.w || 640, h = opts.h || 44;
    var slots = Math.max(pts.length, opts.slots || 96);
    var step = w / slots, bw = Math.max(1.2, step - 1.5);
    var sc = scale(pts, opts.max, opts.min);
    var id = 'c' + (++seq);
    registry.set(id, { pts: pts, fmt: opts.fmt || 'num', label: opts.label || '' });
    var out = '<svg class="chart bars" data-chart="' + id + '" viewBox="0 0 ' + w + ' ' + h +
      '" preserveAspectRatio="none" style="height:' + h + 'px" role="img" aria-label="' +
      (opts.label || 'bars') + '">';
    for (var i = 0; i < pts.length; i++) {
      var v = pts[i].v;
      if (v == null) continue;
      var bh = Math.max(1.5, ((v - sc.lo) / (sc.hi - sc.lo)) * (h - 4));
      var x = w - (pts.length - i) * step;
      out += '<rect class="bar' + (opts.hot != null && v >= opts.hot ? ' hot' : '') +
        '" x="' + x.toFixed(1) + '" y="' + (h - bh).toFixed(1) +
        '" width="' + bw.toFixed(1) + '" height="' + bh.toFixed(1) + '" rx="1"/>';
    }
    return out + '</svg>';
  }

  // categorical state strip: [{ts, state}] over [t0, t1]; colors are the
  // validated mark triad + neutrals, legend rendered by the caller
  var STATE_FILL = {
    working: 'var(--c-good)', blocked: 'var(--c-warn)', exited: 'var(--c-bad)',
    idle: 'var(--c-neutral)', opaque: 'var(--border)'
  };
  function strip(samples, t0, t1, opts) {
    opts = opts || {};
    if (!samples || !samples.length) return '';
    var w = opts.w || 640, h = 14;
    var out = '<svg class="strip" viewBox="0 0 ' + w + ' ' + h + '" preserveAspectRatio="none">';
    for (var i = 0; i < samples.length; i++) {
      var s = samples[i];
      var x0 = ((s.ts - t0) / (t1 - t0)) * w;
      var x1 = (((samples[i + 1] ? samples[i + 1].ts : t1) - t0) / (t1 - t0)) * w;
      var fill = STATE_FILL[s.state];
      if (!fill || x1 <= x0) continue;
      // <title> = native tooltip; the strip is too dense for the shared layer
      out += '<rect fill="' + fill + '" x="' + x0.toFixed(1) + '" y="0" width="' +
        Math.max(0.8, x1 - x0 - 0.8).toFixed(1) + '" height="' + h + '">' +
        '<title>' + s.state + ' · ' + fmtTime(s.ts) + '</title></rect>';
    }
    return out + '</svg>';
  }

  // ---- shared hover tooltip (delegated) -----------------------------------
  var tip = null;
  function onMove(ev) {
    var svg = ev.target.closest ? ev.target.closest('svg[data-chart]') : null;
    if (!svg) { if (tip) tip.hidden = true; return; }
    var reg = registry.get(svg.getAttribute('data-chart'));
    if (!reg || !reg.pts.length) return;
    if (!tip) tip = document.getElementById('tip');
    if (!tip) return;
    var r = svg.getBoundingClientRect();
    var frac = Math.max(0, Math.min(1, (ev.clientX - r.left) / r.width));
    var i = Math.round(frac * (reg.pts.length - 1));
    var pt = reg.pts[i];
    if (!pt) return;
    tip.textContent = (reg.label ? reg.label + ' · ' : '') +
      fmtTime(pt.ts) + ' · ' + fmtVal(reg.fmt, pt.v);
    tip.hidden = false;
    var tx = Math.min(ev.clientX + 12, window.innerWidth - tip.offsetWidth - 8);
    tip.style.left = tx + 'px';
    tip.style.top = (ev.clientY - 30) + 'px';
  }
  function onLeave() { if (tip) tip.hidden = true; }

  if (typeof document !== 'undefined') {
    document.addEventListener('pointermove', onMove, { passive: true });
    document.addEventListener('pointerdown', onMove, { passive: true });
    document.addEventListener('pointerleave', onLeave, true);
  }

  // renders drop stale registry entries on full page re-render
  function resetRegistry() { registry.clear(); seq = 0; }

  root.Charts = { spark: spark, timeline: timeline, bars: bars, strip: strip,
                  stateFill: STATE_FILL, reset: resetRegistry, fmtVal: fmtVal };
})(this);
