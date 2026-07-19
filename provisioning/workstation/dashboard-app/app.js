// app.js - the cockpit application: router, data loop, renderers.
// Ports every rendering rule from the retired render-dashboard.py:
//   - a missing/erroring data file renders a visible UNAVAILABLE badge;
//   - a null metric renders an em-dash, never an invented value;
//   - a failed refetch KEEPS the old data and lets the age pill amber
//     (the emit() philosophy, moved client-side);
//   - no secret ever reaches this page: collectors guarantee token-free JSON
//     and this app renders nothing but what is in that JSON.
// All fetch paths are RELATIVE - the code-server /proxy/8090/ prefix is part
// of the page URL and an absolute path would escape it.

(function () {
  'use strict';

  var esc = Ansi.escapeHtml;
  var now = function () { return Date.now() / 1000; };

  // vault session = walter (founder naming); tmux slug stays authoritative
  var AGENT_ALIAS = { vault: 'walter' };
  var BOX_ROLES = {
    syd1: 'old prod · soak/rollback only',
    syd2: 'production · public edge + workloads',
    syd3: 'cockpit · hermes + founder terminal',
    syd4: 'workspace · repos, vault, agents'
  };
  var AGENT_STATES = { // state -> [badge class, rank, founder gloss]
    blocked: ['warn', 0, 'waiting on YOU'],
    working: ['ok', 1, 'running'],
    idle: ['', 2, 'at the prompt'],
    opaque: ['', 3, 'no pane to read'],
    exited: ['bad', 4, 'agent gone']
  };

  var DOMAINS = ['needs', 'agents', 'projects', 'fleet', 'security', 'money',
                 'calendar', 'hermes', 'migration'];
  var PAGE_DOMAINS = {
    overview: ['needs', 'agents', 'projects', 'fleet', 'security', 'money', 'calendar', 'hermes'],
    agents: ['agents'], fleet: ['fleet'], security: ['security'], money: ['money'],
    hermes: ['hermes'], projects: ['projects'], calendar: ['calendar', 'migration']
  };
  var D = {};   // domain -> last good JSON (or {error})
  var H = {};   // history name -> parsed rows
  var route = 'overview';

  // ---- tiny utils ----------------------------------------------------------

  function rel(epoch) {
    if (!epoch) return 'never';
    var s = Math.max(0, now() - epoch);
    if (s < 3600) return Math.floor(s / 60) + 'm ago';
    if (s < 86400) return Math.floor(s / 3600) + 'h ago';
    return Math.floor(s / 86400) + 'd ago';
  }
  function relAny(v) {
    if (typeof v === 'number') return rel(v);
    var d = Date.parse(v);
    return isNaN(d) ? '?' : rel(d / 1000);
  }
  function humanBytes(n) {
    if (n == null || isNaN(n)) return '—';
    var u = ['B', 'KB', 'MB', 'GB', 'TB'], i = 0;
    while (n >= 1024 && i < u.length - 1) { n /= 1024; i++; }
    return (i ? n.toFixed(1) : Math.round(n)) + ' ' + u[i];
  }
  function dash(v, suffix) { return v == null ? '—' : v + (suffix || ''); }
  function badge(text, cls) { return '<span class="badge ' + (cls || '') + '">' + esc(text) + '</span>'; }
  function uptimeH(s) {
    if (s == null) return '—';
    var d = Math.floor(s / 86400);
    return d ? d + 'd ' + Math.floor((s % 86400) / 3600) + 'h' : Math.floor(s / 3600) + 'h';
  }
  // queue lines carry markdown emphasis the founder wrote - render bold/code
  // AFTER escaping (nothing else; never raw HTML)
  function mdLite(s) {
    return esc(s)
      .replace(/\*\*([^*]+)\*\*/g, '<b>$1</b>')
      .replace(/`([^`]+)`/g, '<span class="mono">$1</span>');
  }
  function unavailable(d) {
    return '<p>' + badge('UNAVAILABLE', 'bad') + ' <span class="dim">' +
      esc((d && d.error) || 'no data') + '</span></p>';
  }
  function el(id) { return document.getElementById(id); }

  // ---- data loop -----------------------------------------------------------

  function loadDomain(name) {
    return fetch('data/' + name + '.json', { cache: 'no-store' })
      .then(function (r) { if (!r.ok) throw new Error('http ' + r.status); return r.json(); })
      .then(function (j) { D[name] = j; })
      .catch(function (e) { if (!D[name]) D[name] = { error: String(e.message || e) }; });
  }
  function loadHistory(name) {
    return fetch('data/history/' + name + '.jsonl', { cache: 'no-store' })
      .then(function (r) { if (!r.ok) throw new Error('http ' + r.status); return r.text(); })
      .then(function (t) {
        H[name] = t.trim().split('\n').filter(Boolean).map(function (l) {
          try { return JSON.parse(l); } catch (e) { return null; }
        }).filter(Boolean);
      })
      .catch(function () { if (!H[name]) H[name] = []; });
  }
  function refreshAll() {
    if (document.visibilityState !== 'visible') return Promise.resolve();
    var jobs = DOMAINS.map(loadDomain)
      .concat(['fleet', 'money', 'agents', 'security'].map(loadHistory));
    return Promise.all(jobs).then(function () {
      renderCurrent();
      renderBadges();
      renderRailFoot();
    });
  }

  // history series helper: H.fleet rows -> [{ts, v}] for one box+field
  function series(hist, pick) {
    return (hist || []).map(function (r) {
      var v = pick(r);
      return { ts: r.ts, v: (v == null || isNaN(v)) ? null : v };
    });
  }
  function last24h(rows) {
    var cut = now() - 24 * 3600;
    return (rows || []).filter(function (r) { return r.ts >= cut; });
  }

  // ---- needs feed (port of needs_items) ------------------------------------

  function needsItems() {
    var items = []; // [epoch, html, crit]
    var agents = (D.agents && D.agents.agents) || [];
    agents.forEach(function (a) {
      if (a.state === 'blocked') {
        items.push([now(), '<span class="tag">agent blocked</span>🖐 <b>' +
          esc(alias(a.name)) + '</b> is stopped on a question/permission prompt - ' +
          'it waits until you answer', true]);
      }
    });
    var needs = D.needs || {};
    if (needs.error) items.push([now(), badge('queue files unreadable', 'bad') + ' ' + esc(needs.error), true]);
    if (needs.missing_swordfish_queue) items.push([now(), badge('queue file missing', 'bad') + ' swordfish queue missing', true]);
    (needs.items || []).forEach(function (it) {
      var tag = it.project === 'swordfish' ? 'queue' : 'queue · ' + it.project;
      items.push([it.epoch, '<span class="tag">' + esc(tag) + '</span>' + mdLite(it.text) +
        '<span class="when">' + rel(it.epoch) + '</span>', false]);
    });
    ((D.projects || {}).asks || []).forEach(function (a) {
      items.push([now(), '<span class="tag">agent ask</span><b>' + esc(a.project) + '</b>: ' + esc(a.text), true]);
    });
    var sec = D.security || {};
    (sec.tls || []).forEach(function (t) {
      if (t.days_left != null && t.days_left < 30) {
        items.push([now(), '<span class="tag">tls</span>cert for <b>' + esc(t.host) +
          '</b> expires in ' + t.days_left + ' days', true]);
      }
    });
    (sec.domains || []).forEach(function (d) {
      if (d.days_left != null && d.days_left < 30) {
        items.push([now(), '<span class="tag">domain</span><b>' + esc(d.domain) +
          '</b> expires in ' + d.days_left + ' days', true]);
      }
    });
    var b2 = ((D.money || {}).api || {}).b2 || {};
    if (typeof b2.pct_of_cap === 'number' && b2.pct_of_cap >= 85) {
      var word = b2.pct_of_cap >= 100 ? 'OVER the free cap - backups are failing'
        : b2.pct_of_cap + '% of the free cap';
      items.push([now(), '<span class="tag">backups</span>Backblaze B2 storage is <b>' + word +
        '</b> - shrink the backup set or raise the cap before it blocks uploads', true]);
    }
    ((D.money || {}).subscriptions || []).forEach(function (s) {
      if (s.days_until != null && s.days_until <= 7) {
        var w = s.days_until < 0 ? 'OVERDUE' : 'due in ' + s.days_until + 'd';
        items.push([now(), '<span class="tag">money</span><b>' + esc(s.name) + '</b> ' +
          esc(s.currency || '') + ' ' + esc(String(s.amount)) + ' ' + w, true]);
      }
    });
    items.sort(function (a, b) { return b[0] - a[0]; });
    return items;
  }

  function renderNeeds() {
    var items = needsItems();
    el('needs-body').innerHTML = items.length
      ? '<ul class="needs">' + items.map(function (i) {
          return '<li class="' + (i[2] ? 'crit' : '') + '">' + i[1] + '</li>';
        }).join('') + '</ul>'
      : '<p class="allclear">Nothing needs you. ✓</p>';
  }

  // ---- overview tiles ------------------------------------------------------

  function tile(href, label, value, sub, mood, sparkHtml) {
    var cls = 'tile' + (mood === 'bad' ? ' alert' : mood === 'warn' ? ' watch' : '');
    var inner = '<div class="t-label">' + label + '</div><div class="t-value">' + value + '</div>' +
      (sub ? '<div class="t-sub">' + sub + '</div>' : '') + (sparkHtml || '');
    return href ? '<a class="' + cls + '" href="' + href + '">' + inner + '</a>'
                : '<div class="' + cls + '">' + inner + '</div>';
  }

  function renderTiles() {
    var t = [];
    var needs = needsItems();
    var crit = needs.filter(function (i) { return i[2]; }).length;
    t.push(tile(null, 'Needs Steven', String(needs.length),
      crit ? crit + ' urgent' : 'queue items', needs.length ? (crit ? 'bad' : 'warn') : ''));

    var ag = (D.agents && D.agents.agents) || [];
    var per = {}; // session -> best rank state
    ag.forEach(function (a) {
      var r = (AGENT_STATES[a.state] || ['', 9])[1];
      if (!(a.name in per) || r < (AGENT_STATES[per[a.name]] || ['', 9])[1]) per[a.name] = a.state;
    });
    var working = 0, blocked = 0;
    Object.keys(per).forEach(function (k) {
      if (per[k] === 'working') working++;
      if (per[k] === 'blocked') blocked++;
    });
    t.push(tile('#/agents', 'Agents', working + '<small> working</small>' +
      (blocked ? ' · ' + blocked + '<small> blocked</small>' : ''),
      Object.keys(per).length + ' sessions on syd4', blocked ? 'bad' : ''));

    var boxes = (D.fleet && D.fleet.boxes) || [];
    var up = boxes.filter(function (b) { return b.up; }).length;
    var worst = null;
    boxes.forEach(function (b) {
      if (b.disk_pct != null && (!worst || b.disk_pct > worst.disk_pct)) worst = b;
    });
    t.push(tile('#/fleet', 'Fleet', up + '<small> / ' + boxes.length + ' up</small>',
      worst ? 'worst disk ' + Math.round(worst.disk_pct) + '% · ' + esc(worst.name) : '',
      up < boxes.length ? 'bad' : (worst && worst.disk_pct >= 80 ? 'warn' : '')));

    var bak = boxes.map(function (b) { return backupOk(b.backup); });
    var bokn = bak.filter(function (x) { return x === true; }).length;
    t.push(tile('#/fleet', 'Backups', bokn + '<small> / ' + boxes.length + ' ok</small>',
      'restic + dead-man', bokn < boxes.length ? 'bad' : ''));

    var b2 = ((D.money || {}).api || {}).b2 || {};
    var b2spark = Charts.spark(series(H.money, function (r) { return r.b2_pct; }).slice(-96),
      { h: 26, max: 100, fmt: 'pct', label: 'B2 % of cap',
        status: b2.pct_of_cap >= 100 ? 'bad' : b2.pct_of_cap >= 85 ? 'warn' : 'good' });
    t.push(tile('#/money', 'B2 storage', dash(b2.pct_of_cap, '%<small> of cap</small>'),
      humanBytes(b2.total_bytes) + ' of ' + humanBytes(b2.cap_bytes),
      b2.pct_of_cap >= 100 ? 'bad' : b2.pct_of_cap >= 85 ? 'warn' : '', b2spark));

    var sec = D.security || {};
    var fails = 0;
    (sec.auth || []).forEach(function (a) { if (a.fails_24h) fails += a.fails_24h; });
    var sus = (sec.logins || []).filter(function (l) { return l.suspicious; }).length;
    t.push(tile('#/security', 'Security', sus ? sus + '<small> unrecognized login' + (sus === 1 ? '' : 's') + '</small>'
      : 'keys ok', fails + ' failed auth / 24h', sus ? 'bad' : ''));

    var h = D.hermes || {};
    var g = h.gateway || {};
    var hOk = h.service === 'active' && g.state === 'running' && g.telegram === 'connected';
    t.push(tile('#/hermes', 'Hermes', hOk ? 'connected' : esc(h.service || '?'),
      'gateway ' + esc(g.state || '?') + ' · telegram ' + esc(g.telegram || '?'),
      hOk ? '' : 'bad'));

    var ev = ((D.calendar || {}).events || [])[0];
    t.push(tile('#/calendar', 'Next event', ev
      ? esc((ev.summary || '').slice(0, 22)) : 'nothing<small> 60d</small>',
      ev ? esc(fmtEvent(ev)) : 'calendar clear', ''));

    el('tiles').innerHTML = t.join('');
  }

  function backupOk(b) {
    if (!b) return null;
    if (b.kind === 'restic-unit') {
      return b.result === 'success' && b.last_run != null && (now() - b.last_run) < 36 * 3600;
    }
    return b.ok == null ? null : !!b.ok;
  }
  function fmtEvent(e) {
    var d = new Date(e.start);
    if (isNaN(d)) return '?';
    var o = { timeZone: 'Australia/Sydney', weekday: 'short', day: 'numeric', month: 'short' };
    if (!e.all_day) { o.hour = '2-digit'; o.minute = '2-digit'; o.hour12 = false; }
    return new Intl.DateTimeFormat('en-AU', o).format(d);
  }

  // ---- agents page ---------------------------------------------------------

  function alias(name) { return AGENT_ALIAS[name] || name; }

  function renderAgents() {
    var a = D.agents || {};
    var body = el('agents-body');
    if (a.error) { body.innerHTML = unavailable(a); return; }
    var rows = (a.agents || []).slice().sort(function (x, y) {
      return (AGENT_STATES[x.state] || ['', 9])[1] - (AGENT_STATES[y.state] || ['', 9])[1];
    });
    var html = '';
    if (rows.length) {
      html += '<table><thead><tr><th>agent</th><th>state</th><th>evidence</th><th>basis</th></tr></thead><tbody>';
      rows.forEach(function (ag) {
        var st = AGENT_STATES[ag.state] || ['', 9, 'unknown'];
        var stateCell = (st[0] ? badge(ag.state, st[0]) : '<span class="dim">' + esc(ag.state || '?') + '</span>') +
          ' <span class="dim">' + esc(st[2]) + '</span>';
        var how = ag.runtime === 'tmux'
          ? 'tmux · output ' + rel(ag.last_activity)
          : 'pty · cpu ' + dash(ag.cpu_pct, '%') + ' · up ' + uptimeH(ag.uptime_s);
        html += '<tr><td class="agent-alias"><b>' + esc(alias(ag.name)) + '</b>' +
          (alias(ag.name) !== ag.name ? '<small>' + esc(ag.name) + '</small>' : '') + '</td>' +
          '<td>' + stateCell + '</td><td class="dim">' + esc(how) + '</td>' +
          '<td class="dim">' + esc(ag.basis || '') + '</td></tr>';
      });
      html += '</tbody></table>';
      html += '<p class="dim">blocked = a question/permission prompt is on screen — work is stopped ' +
        'until you answer it (also raised under Needs Steven). opaque = the agent runs outside tmux, ' +
        'so blocked is invisible there.</p>';
    } else {
      html += '<p class="dim">no agent sessions on this box</p>';
    }

    // 24h state strip from history
    var hist = last24h(H.agents);
    if (hist.length > 1) {
      var names = {};
      hist.forEach(function (r) { Object.keys(r.states || {}).forEach(function (n) { names[n] = 1; }); });
      var t0 = hist[0].ts, t1 = now();
      html += '<h3>last 24h</h3>';
      Object.keys(names).sort().forEach(function (n) {
        var samples = hist.map(function (r) { return { ts: r.ts, state: (r.states || {})[n] }; })
          .filter(function (s) { return s.state; });
        html += '<div class="strip-row"><span class="s-name">' + esc(alias(n)) + '</span>' +
          Charts.strip(samples, t0, t1) + '</div>';
      });
      html += '<div class="strip-legend">' +
        ['working', 'blocked', 'idle', 'exited', 'opaque'].map(function (s) {
          return '<span><i style="background:' + Charts.stateFill[s] + '"></i>' + s + '</span>';
        }).join('') + '</div>';
    }

    // controls: reset button + live-comm compose (ports - same ids, same
    // relative endpoints; the server refuses anything unsafe)
    html += '<p style="margin-top:12px"><button class="ghost-btn" id="reset-btn" type="button">↺ reset stale terminals</button> ' +
      '<span class="dim">kills empty panel shells only — live agents are refused server-side</span> ' +
      '<span id="reset-out" class="dim"></span></p>';
    html += '<details id="live-comm"><summary>📡 live message / coordination (composer inject — parked drafts are refused)</summary>' +
      '<div class="lc-row"><label class="dim">to <select id="lc-target"><option>loading…</option></select></label> ' +
      '<label class="dim">coordinate with (optional, ctrl-click for more) <select id="lc-with" multiple size="3"></select></label></div>' +
      '<textarea id="lc-text" maxlength="1800" rows="5" placeholder="what should happen — sent as [Steven via dashboard] …; ' +
      'newlines are collapsed to one line; picking partners appends the coordinate-live-via-agent-comm clause automatically"></textarea>' +
      '<p><button class="action-btn" id="lc-send-btn" type="button">send</button> <span id="lc-out" class="dim"></span></p>' +
      '<pre id="lc-ledger" class="snip" style="display:none"></pre>' +
      '<p class="dim"><a href="#" id="lc-ledger-lnk">recent sends</a> · mid-turn messages queue politely; ' +
      'the agent sees them at its next boundary · scope changes still go through the agent\'s own queue</p></details>';

    body.innerHTML = html;
    el('reset-btn').addEventListener('click', resetTerminals);
    el('lc-send-btn').addEventListener('click', lcSend);
    el('lc-ledger-lnk').addEventListener('click', function (e) { e.preventDefault(); lcLedger(); });
    var lc = el('live-comm');
    lc.addEventListener('toggle', function () { if (lc.open) lcRoster(); });

    // live terminal mirrors
    Term.mount((a.agents || []).map(function (ag) {
      return { name: ag.name, state: ag.state, cwd: ag.cwd, runtime: ag.runtime, label: alias(ag.name) };
    }));
  }

  // ---- fleet page ----------------------------------------------------------

  function metricSpark(name, field, fmt, warn, bad, cur) {
    var pts = series(H.fleet, function (r) {
      return ((r.boxes || {})[name] || {})[field];
    }).slice(-192);
    var status = cur == null ? '' : cur >= bad ? 'bad' : cur >= warn ? 'warn' : 'good';
    return Charts.spark(pts, { h: 30, fmt: fmt, label: name + ' ' + field.replace('_pct', ' %'),
      max: fmt === 'pct' ? 100 : null, status: status });
  }

  function backupCell(b) {
    if (!b) return '—';
    if (b.kind === 'restic-unit') {
      var stale = b.last_run == null || (now() - b.last_run) > 36 * 3600;
      var cls = (stale || b.result !== 'success') ? 'bad' : 'ok';
      return '<span class="' + cls + '">' + esc(b.result || '?') + ' · ' + rel(b.last_run) + '</span>';
    }
    if (b.ok == null) return 'dead-man: —';
    return '<span class="' + (b.ok ? 'ok' : 'bad') + '">dead-man ' + (b.ok ? 'OK' : 'LATE') + '</span>';
  }

  function renderFleet() {
    var f = D.fleet || {};
    var body = el('fleet-body');
    if (f.error) { body.innerHTML = unavailable(f); return; }
    var html = '<div class="box-grid">';
    (f.boxes || []).forEach(function (b) {
      var upb = b.up ? badge('UP', 'ok') : (b.up == null ? badge('?', 'warn') : badge('DOWN', 'bad'));
      var cpuVal = b.cpu_pct != null ? b.cpu_pct : b.load1;
      var cpuIsLoad = b.cpu_pct == null && b.load1 != null;
      var cpuTxt = b.cpu_pct != null ? b.cpu_pct.toFixed(1) + '%' : (b.load1 != null ? String(b.load1) : '—');
      function vcls(v, w, x) { return v == null ? '' : v >= x ? 'bad' : v >= w ? 'warn' : ''; }
      html += '<div class="box-card"><div class="b-head"><b>' + esc(b.name) + '</b>' + upb +
        (b.reboot_required ? ' <span class="chip warn">reboot pending</span>' : '') +
        '<span class="dim" style="margin-left:auto">' + uptimeH(b.uptime_s) + ' up</span></div>' +
        '<div class="b-role">' + esc(BOX_ROLES[b.name] || '') + ' · via ' + esc(b.source || '?') + '</div>' +
        '<div class="metric-row">' +
        '<div class="metric"><div class="m-label"><span>' + (cpuIsLoad ? 'load' : 'cpu') + '</span><b>' +
          esc(cpuTxt) + '</b></div>' +
          metricSpark(b.name, cpuIsLoad ? 'load1' : 'cpu_pct', cpuIsLoad ? 'num' : 'pct', 70, 90, cpuIsLoad ? null : b.cpu_pct) + '</div>' +
        '<div class="metric"><div class="m-label"><span>mem</span><b class="' + vcls(b.mem_pct, 80, 92) + '">' +
          dash(b.mem_pct != null ? Math.round(b.mem_pct) : null, '%') + '</b></div>' +
          metricSpark(b.name, 'mem_pct', 'pct', 80, 92, b.mem_pct) + '</div>' +
        '<div class="metric"><div class="m-label"><span>disk</span><b class="' + vcls(b.disk_pct, 80, 92) + '">' +
          dash(b.disk_pct != null ? Math.round(b.disk_pct) : null, '%') + '</b></div>' +
          metricSpark(b.name, 'disk_pct', 'pct', 80, 92, b.disk_pct) + '</div></div>' +
        '<div class="b-foot"><span>backup: ' + backupCell(b.backup) + '</span></div>' +
        '<div class="b-foot" style="margin-top:6px">' + ((b.services || []).map(function (s) {
          var good = s.state === 'active' || s.state === 'up';
          return '<span class="chip ' + (good ? 'ok' : 'bad') + '">' + esc(s.name) + '</span>';
        }).join('') || '—') + '</div></div>';
    });
    body.innerHTML = html + '</div>';
  }

  // ---- security page -------------------------------------------------------

  function renderSecurity() {
    var s = D.security || {};
    var body = el('security-body');
    if (s.error) { body.innerHTML = unavailable(s); return; }
    var parts = [];

    var post = (s.auth || []).map(function (a) {
      if (a.unreachable) {
        return '<tr><td><b>' + esc(a.box) + '</b></td><td colspan="4">' + badge('unreachable', 'bad') + '</td></tr>';
      }
      var ufwOk = a.ufw === 'active', pwOk = a.sshd_password_auth === 'no';
      return '<tr><td><b>' + esc(a.box) + '</b></td>' +
        '<td>' + badge('ufw ' + (a.ufw || '?'), ufwOk ? 'ok' : 'bad') + '</td>' +
        '<td>' + badge(pwOk ? 'key-only ssh' : 'PASSWORD AUTH ON', pwOk ? 'ok' : 'bad') + '</td>' +
        '<td class="' + ((a.fails_24h || 0) > 50 ? 'warn' : '') + '">' + dash(a.fails_24h) + ' failed auth / 24h</td>' +
        '<td>' + dash(a.bans_24h) + ' bans / 24h</td></tr>';
    }).join('');
    parts.push('<table><tbody>' + post + '</tbody></table>');

    var boxesInHist = {};
    (H.security || []).forEach(function (r) {
      Object.keys(r.fails_24h || {}).forEach(function (b) { boxesInHist[b] = 1; });
    });
    var histBoxes = Object.keys(boxesInHist).sort();
    if (histBoxes.length) {
      parts.push('<h3>failed auth / 24h — trend <span class="dim h2-note">internet background noise; ' +
        'watch the shape, not the number</span></h3>');
      histBoxes.forEach(function (b) {
        var pts = series(H.security, function (r) { return (r.fails_24h || {})[b]; }).slice(-96);
        parts.push('<p class="dim" style="margin:6px 0 2px">' + esc(b) + '</p>' +
          Charts.bars(pts, { h: 38, label: b + ' failed auth' }));
      });
    }

    var rt = s.relay_tag || {};
    if (rt.status) {
      var cls = { ok: 'ok', drift: 'bad' }[rt.status] || 'warn';
      var label = {
        ok: 'relay founder-id gate OK (' + (rt.checked || '?') + ' msgs, no tag drift)',
        drift: 'relay founder-id gate DRIFT (' + (rt.drift || '?') + '/' + (rt.checked || '?') + ' - founder may be unheard)',
        unreachable: 'relay founder-id gate: hermes unreachable'
      }[rt.status] || ('relay founder-id gate: ' + rt.status);
      parts.push('<h3>relay ' + badge(label, cls) + '</h3>');
      if (rt.status === 'drift' && rt.sample) parts.push('<p class="mono bad">' + esc(rt.sample) + '</p>');
    }

    // suspicious entries surface ALWAYS, even when they fall outside the
    // last-10 window - a hidden unrecognized key is the worst kind of quiet
    var allLogins = (s.logins || []).slice().sort(function (a, b) {
      return (b.line || '').localeCompare(a.line || '');
    });
    var susAll = allLogins.filter(function (e) { return e.suspicious; });
    var shown = allLogins.slice(0, 10);
    susAll.forEach(function (e) { if (shown.indexOf(e) < 0) shown.push(e); });
    parts.push('<h3>ssh logins (last 10' + (shown.length > 10 ? ' + flagged' : '') + ') ' +
      (susAll.length ? badge(susAll.length + ' unrecognized in the journal window', 'bad')
                     : badge('all keys recognized', 'ok')) + '</h3>' +
      '<ul class="mono plain">' + (shown.map(function (e) {
        return '<li class="' + (e.suspicious ? 'bad' : '') + '">' + esc(e.line || '') + '</li>';
      }).join('') || '<li>no logins in the journal window</li>') + '</ul>' +
      '<p class="dim">' + esc(s.note || '') + '</p>');

    var tlsRows = (s.tls || []).map(function (t) {
      var d = t.days_left;
      var cls = (d == null || d < 14) ? 'bad' : d < 30 ? 'warn' : '';
      return '<tr><td>' + esc(t.host) + '</td><td class="' + cls + ' num">' + dash(d, ' days') + '</td></tr>';
    }).join('');
    var domRows = (s.domains || []).map(function (t) {
      var d = t.days_left;
      var cls = (d == null || d < 30) ? 'bad' : d < 60 ? 'warn' : '';
      return '<tr><td><b>' + esc(t.domain) + '</b></td><td class="' + cls + ' num">' + dash(d, ' days') + '</td></tr>';
    }).join('');
    parts.push('<div class="cols"><div><h3>TLS certs</h3><table><tbody>' + tlsRows +
      '</tbody></table></div><div><h3>domains</h3><table><tbody>' + domRows + '</tbody></table></div></div>');
    body.innerHTML = parts.join('');
  }

  // ---- money page ----------------------------------------------------------

  function renderMoney() {
    var m = D.money || {};
    var body = el('money-body');
    if (m.error) { body.innerHTML = unavailable(m); return; }
    var parts = [];

    var b2 = (m.api || {}).b2 || {};
    if (b2.total_bytes != null && (H.money || []).length > 1) {
      parts.push('<h3>B2 storage vs free cap</h3>' +
        Charts.timeline(series(H.money, function (r) { return r.b2_bytes; }),
          { fmt: 'bytes', label: 'B2 stored', cap: b2.cap_bytes, capLabel: 'free cap',
            max: b2.cap_bytes ? b2.cap_bytes * 1.15 : null }));
    }

    var rows = [];
    var bl = (m.api || {}).binarylane || {};
    rows.push(bl.error
      ? '<tr><td>BinaryLane</td><td colspan="2">' + badge(bl.error, 'bad') + '</td></tr>'
      : '<tr><td>BinaryLane</td><td>unbilled AUD <b>' + esc(String(bl.unbilled_total != null ? bl.unbilled_total : '?')) +
        '</b></td><td>' + ((bl.servers || []).map(function (s) {
          return '<span class="chip">' + esc(s.name || '?') + ' ' + esc(String(s.total != null ? s.total : '?')) + '</span>';
        }).join(' ')) + '</td></tr>');
    var vu = (m.api || {}).vultr || {};
    rows.push(vu.error
      ? '<tr><td>Vultr</td><td colspan="2">' + badge(vu.error, 'bad') + '</td></tr>'
      : '<tr><td>Vultr</td><td>' + (typeof vu.balance === 'number' && vu.balance < 0
          ? 'credit USD <b>' + (-vu.balance).toFixed(2) + '</b>' : 'balance USD ' + esc(String(vu.balance))) +
        '</td><td>pending ' + esc(String(vu.pending_charges != null ? vu.pending_charges : '?')) + '</td></tr>');
    if (b2.error) {
      rows.push('<tr><td>Backblaze B2</td><td colspan="2">' + badge(b2.error, 'bad') + '</td></tr>');
    } else if (b2.total_bytes != null) {
      var pct = b2.pct_of_cap;
      var cls = pct >= 100 ? 'bad' : pct >= 85 ? 'warn' : 'ok';
      var buckets = b2.buckets || [];
      var biggest = buckets.length ? buckets.reduce(function (a, b) { return (b.bytes || 0) > (a.bytes || 0) ? b : a; }) : {};
      rows.push('<tr><td>Backblaze B2</td><td>' + humanBytes(b2.total_bytes) + ' of ' + humanBytes(b2.cap_bytes) +
        ' free cap ' + badge(pct + '%', cls) + '</td><td class="dim">biggest: ' + esc(biggest.bucket || '?') + ' ' +
        humanBytes(biggest.bytes) + ' — at cap B2 rejects uploads and every nightly backup fails</td></tr>');
    }
    var pb = (m.api || {}).porkbun || {};
    if (pb.error) {
      rows.push('<tr><td>Porkbun</td><td colspan="2">' + badge(pb.error, 'bad') + '</td></tr>');
    } else {
      var doms = pb.domains || [];
      var auto = doms.length && doms.every(function (d) { return d.auto_renew; });
      var near = doms.length ? 'nearest <b>' + esc(doms[0].domain) + '</b> in ' + dash(doms[0].days_left, 'd') : 'no domains';
      rows.push('<tr><td>Porkbun</td><td>' + doms.length + ' domains' + (auto ? ' · all auto-renew' : '') +
        '</td><td>' + near + '</td></tr>');
    }
    if (b2.note) rows.push('<tr><td>Backblaze B2</td><td colspan="2" class="dim">' + esc(b2.note) + '</td></tr>');
    parts.push('<table><tbody>' + rows.join('') + '</tbody></table>');

    if (m.subscriptions_missing) {
      parts.push('<p class="dim">subscriptions.yml missing — SaaS spend not tracked</p>');
    } else {
      var srows = (m.subscriptions || []).map(function (s) {
        var du = s.days_until;
        var cls = du != null && du <= 3 ? 'bad' : du != null && du <= 7 ? 'warn' : '';
        return '<tr><td>' + esc(s.name || '') + '</td><td>' + esc(s.currency || '') + ' ' + esc(String(s.amount != null ? s.amount : '?')) +
          '</td><td>' + esc(s.cycle || '') + '</td><td class="' + cls + '">' + esc(s.next_charge || '—') +
          (du != null ? ' (' + du + 'd)' : '') + '</td><td class="dim">' + esc(s.card || '') + '</td></tr>';
      }).join('');
      parts.push('<h3>SaaS (founder-maintained)</h3><table><thead><tr><th>what</th><th>amount</th><th>cycle</th>' +
        '<th>next charge</th><th>note</th></tr></thead><tbody>' + srows + '</tbody></table>' +
        '<p class="dim">SaaS monthly run-rate ≈ ' + esc(String(m.monthly_run_rate != null ? m.monthly_run_rate : '?')) +
        ' (placeholder amounts until the one-time correction pass)</p>');
    }
    body.innerHTML = parts.join('');
  }

  // ---- hermes page ---------------------------------------------------------

  function renderHermes() {
    var h = D.hermes || {};
    var body = el('hermes-body');
    if (h.error) { body.innerHTML = unavailable(h); return; }
    var g = h.gateway || {};
    var parts = ['<p>' +
      badge('service ' + (h.service || '?'), h.service === 'active' ? 'ok' : 'bad') + ' ' +
      badge('gateway ' + (g.state || '?'), g.state === 'running' ? 'ok' : 'bad') + ' ' +
      badge('telegram ' + (g.telegram || '?'), g.telegram === 'connected' ? 'ok' : 'bad') +
      ' <span class="dim">' + esc(h.note || '') + '</span></p>'];

    if (h.jobs == null) {
      parts.push('<p>' + badge('jobs unreadable', 'bad') + ' ' + esc(h.jobs_error || '') + '</p>');
    } else {
      var rows = h.jobs.map(function (j) {
        var st = j.state || '?';
        var ok = j.last_status;
        return '<tr><td>' + esc(j.name || '') + '</td><td class="mono">' + esc(j.schedule_display || '') + '</td>' +
          '<td>' + badge(st.toUpperCase(), (st === 'scheduled' || j.enabled) ? 'ok' : 'warn') + '</td>' +
          '<td>' + relAny(j.last_run_at) + ' · <span class="' + (ok === 'ok' ? 'ok' : 'bad') + '">' + esc(ok || '—') + '</span></td>' +
          '<td>' + esc((j.next_run_at || '—').slice(0, 16)) + '</td></tr>';
      }).join('');
      parts.push('<table><thead><tr><th>cron job</th><th>schedule</th><th>state</th><th>last run</th><th>next run</th></tr></thead>' +
        '<tbody>' + rows + '</tbody></table>' +
        '<p class="dim">read from cron/jobs.json — `hermes cron list` hides paused jobs</p>');
    }

    var relay = (h.relay || []).slice().sort(function (a, b) { return (b.ts || 0) - (a.ts || 0); });
    if (relay.length) {
      parts.push('<h3>last relay per project</h3><ul class="plain">' + relay.map(function (r) {
        return '<li><b>' + esc(r.project || '?') + '</b> <span class="tag">' + esc(r.dir || '?') + '</span>' +
          esc(r.head || '') + '<span class="when">' + rel(r.ts) + '</span></li>';
      }).join('') + '</ul>');
    }

    [['last_in', 'founder → hermes'], ['last_out', 'hermes → founder']].forEach(function (pair) {
      var msg = h[pair[0]];
      if (msg) {
        parts.push('<p><b>' + pair[1] + '</b> <span class="dim">' + relAny(msg.ts) + '</span><br>' +
          '<span class="mono">' + esc(msg.snippet || '') + '</span></p>');
      }
    });
    var o = h.last_cron_output;
    if (o) {
      parts.push('<h3>last cron output <span class="dim">' + esc(o.file || '') + ' · ' + rel(o.mtime) + '</span></h3>' +
        '<pre class="snip">' + esc(o.head || '') + '</pre>' +
        '<p class="dim">delivery-green ≠ content-true: check this against what Telegram showed</p>');
    }
    body.innerHTML = parts.join('');
  }

  // ---- projects / calendar / migration -------------------------------------

  function renderProjects() {
    var p = D.projects || {};
    var body = el('projects-body');
    if (p.error) { body.innerHTML = unavailable(p); return; }
    var out = (p.projects || []).map(function (prj) {
      var g = prj.git || {};
      var state;
      if (!g.is_repo) state = 'not a git repo';
      else if ((g.dirty || 0) === 0 && (g.unpushed || 0) === 0) state = '<span class="ok">clean · all pushed</span>';
      else {
        var unp = g.unpushed;
        state = '<span class="warn">' + dash(g.dirty, '') + ' uncommitted · ' +
          ((unp == null || unp < 0) ? '?' : unp) + ' unpushed</span>';
      }
      var gitline = g.is_repo
        ? 'branch ' + esc(g.branch || '?') + ' · last commit ' + esc(g.last_commit_rel || '?') + '<br>' + state
        : state;
      var extra = prj.kind === 'vault' ? ' · ' + prj.notes + ' notes' : '';
      return '<a class="btn" href="http://localhost:8080/?folder=' + encodeURIComponent(prj.path) + '">' +
        '<div class="name">' + esc(alias(prj.name)) + '</div>' +
        '<div class="sub">files touched ' + rel(prj.touched) + ' · agent session ' + rel(prj.session) + extra +
        '<br>' + gitline + '</div></a>';
    }).join('');
    body.innerHTML = '<div class="btns">' + out + '</div>';
  }

  function renderCalendar() {
    var c = D.calendar || {};
    var body = el('calendar-body');
    if (c.error) { body.innerHTML = unavailable(c); return; }
    var items = (c.events || []).slice(0, 5).map(function (e) {
      return '<li><span class="when">' + esc(fmtEvent(e)) + '</span>' + esc(e.summary || '') + '</li>';
    });
    body.innerHTML = '<ul class="cal">' + (items.join('') ||
      '<li>nothing in the next 60 days' + (c.vevents ? ' (' + c.vevents + ' events in the feed, all in the past)' : '') + '</li>') + '</ul>';

    var m = D.migration || {};
    var mbody = el('migration-body');
    if (m.error) { mbody.innerHTML = unavailable(m); return; }
    var rows = (m.areas || []).map(function (a) {
      return '<tr><td>' + esc(a.name) + '</td><td class="num">' + a.files + '</td><td class="num">' + humanBytes(a.bytes) + '</td></tr>';
    }).join('');
    var placed = (m.placed || []).map(function (p2) { return '<span class="chip ok">' + esc(p2) + '</span>'; }).join(' ');
    mbody.innerHTML = '<table><thead><tr><th>staging area</th><th>files</th><th>size</th></tr></thead><tbody>' + rows + '</tbody></table>' +
      (placed ? '<p>placed by the box agent: ' + placed + '</p>' : '') +
      '<p class="dim">census: ' + dash(m.census_rows) + ' rows · ' + esc(m.note || '') + '</p>';
  }

  // ---- actions: reset terminals + live-comm (ports) ------------------------

  function resetTerminals() {
    var out = el('reset-out');
    fetch('api/reset-terminals/preview').then(function (r) { return r.json(); }).then(function (p) {
      if (!p.stale.length && !p.refused_live.length) { out.textContent = 'nothing to reset — no panel shells at all'; return; }
      if (!p.stale.length) { out.textContent = 'nothing stale — ' + p.refused_live.length + ' live panel(s) left alone'; return; }
      if (!confirm('Reset ' + p.stale.length + ' stale terminal(s)? (' + p.refused_live.length + ' live panel(s) will be refused)')) return;
      fetch('api/reset-terminals', { method: 'POST' }).then(function (r) { return r.json(); }).then(function (res) {
        out.textContent = 'reset ' + res.hupped.length + ' · refused (live) ' + res.refused_live.length;
      });
    }).catch(function (e) { out.textContent = 'reset failed: ' + e; });
  }

  function lcRoster() {
    var sel = el('lc-target'), withSel = el('lc-with');
    fetch('api/agent-roster').then(function (r) { return r.json(); }).then(function (r) {
      var live = (r.agents || []).filter(function (a) { return a.claude; });
      var opts = live.map(function (a) {
        return '<option value="' + esc(a.session) + '">' + esc(alias(a.session)) + ' (' + esc(a.state) + ')</option>';
      }).join('');
      sel.innerHTML = opts || '<option value="">no live agents</option>';
      withSel.innerHTML = opts;
    }).catch(function () { sel.innerHTML = '<option value="">roster failed</option>'; });
  }

  function lcSend() {
    var out = el('lc-out');
    var target = el('lc-target').value;
    var text = el('lc-text').value.trim();
    var partners = Array.prototype.slice.call(el('lc-with').selectedOptions)
      .map(function (o) { return o.value; }).filter(function (v) { return v && v !== target; });
    if (!target || !text) { out.textContent = 'pick an agent and type a message'; return; }
    out.textContent = 'sending…';
    fetch('api/agent-send', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ target: target, text: text, with: partners })
    }).then(function (r) { return r.json(); }).then(function (r) {
      out.textContent = (r.human || r.status) + (r.detail ? ' — ' + r.detail : '');
      if (r.status === 'ok') el('lc-text').value = '';
    }).catch(function (e) { out.textContent = 'send failed: ' + e; });
  }

  function lcLedger() {
    var pre = el('lc-ledger');
    fetch('api/agent-ledger').then(function (r) { return r.json(); }).then(function (r) {
      pre.textContent = (r.rows || []).join('\n') || 'no sends yet';
      pre.style.display = 'block';
    }).catch(function (e) { pre.textContent = 'ledger failed: ' + e; pre.style.display = 'block'; });
  }

  // ---- rail badges + footer ------------------------------------------------

  function setBadge(id, n, cls) {
    var b = el(id);
    if (!b) return;
    b.hidden = !n;
    b.textContent = n || '';
    b.className = 'rail-badge' + (cls ? ' ' + cls : '');
  }
  function renderBadges() {
    var needs = needsItems();
    var crit = needs.filter(function (i) { return i[2]; }).length;
    setBadge('badge-needs', needs.length, crit ? '' : 'quiet');
    var ag = (D.agents && D.agents.agents) || [];
    var blockedSessions = {};
    ag.forEach(function (a) { if (a.state === 'blocked') blockedSessions[a.name] = 1; });
    setBadge('badge-agents', Object.keys(blockedSessions).length);
    var boxes = (D.fleet && D.fleet.boxes) || [];
    setBadge('badge-fleet', boxes.filter(function (b) { return b.up === false; }).length);
    var sus = ((D.security || {}).logins || []).filter(function (l) { return l.suspicious; }).length;
    setBadge('badge-security', sus);
    var h = D.hermes || {}, g = h.gateway || {};
    var hBad = (h.service && h.service !== 'active') || (g.state && g.state !== 'running') ? 1 : 0;
    setBadge('badge-hermes', hBad);
  }
  function renderRailFoot() {
    var boxes = (D.fleet && D.fleet.boxes) || [];
    var syd4 = boxes.filter(function (b) { return b.name === 'syd4'; })[0];
    el('rail-uptime').textContent = syd4 ? 'syd4 up ' + uptimeH(syd4.uptime_s) : '';
  }

  // ---- ages ----------------------------------------------------------------

  function renderAges() {
    var oldest = null;
    document.querySelectorAll('.sec-age[data-domain]').forEach(function (span) {
      var d = D[span.dataset.domain];
      if (!d) return;
      if (d.error) { span.innerHTML = badge('UNAVAILABLE', 'bad') + ' <span class="dim">' + esc(d.error) + '</span>'; return; }
      var ts = d.generated_at;
      if (!ts) { span.textContent = ''; return; }
      var s = now() - ts;
      span.textContent = 'data ' + (s < 90 ? 'live' : s < 3600 ? Math.round(s / 60) + 'm old'
        : s < 172800 ? Math.round(s / 360) / 10 + 'h old' : Math.round(s / 86400) + 'd old');
      span.classList.toggle('stale', s > 2400);
    });
    (PAGE_DOMAINS[route] || []).forEach(function (dm) {
      var d = D[dm];
      if (d && d.generated_at && (oldest == null || d.generated_at < oldest)) oldest = d.generated_at;
    });
    var pill = el('page-age');
    if (oldest) {
      var age = now() - oldest;
      pill.hidden = false;
      pill.textContent = age < 90 ? 'data live' : 'oldest data ' + Math.round(age / 60) + 'm';
      pill.classList.toggle('stale', age > 2400);
    } else pill.hidden = true;
  }

  // ---- clock ---------------------------------------------------------------

  function tick() {
    var d = new Date();
    var f = function (tz) {
      return new Intl.DateTimeFormat('en-AU', { timeZone: tz, hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false }).format(d);
    };
    var day = new Intl.DateTimeFormat('en-AU', { timeZone: 'Australia/Sydney', weekday: 'short', day: 'numeric', month: 'short' }).format(d);
    el('clk').innerHTML = esc(day) + ' · <b>' + f('Australia/Sydney') + '</b> syd · <span>' + f('UTC') + ' utc</span>';
  }

  // ---- router --------------------------------------------------------------

  var TITLES = { overview: 'Overview', agents: 'Agents', fleet: 'Fleet', security: 'Security',
                 money: 'Money', hermes: 'Hermes', projects: 'Projects', calendar: 'Calendar' };

  function renderCurrent() {
    Charts.reset();
    if (route === 'overview') { renderTiles(); renderNeeds(); }
    else if (route === 'agents') renderAgents();
    else if (route === 'fleet') renderFleet();
    else if (route === 'security') renderSecurity();
    else if (route === 'money') renderMoney();
    else if (route === 'hermes') renderHermes();
    else if (route === 'projects') renderProjects();
    else if (route === 'calendar') renderCalendar();
    renderAges();
  }

  function setRoute() {
    var r = (location.hash || '#/overview').replace(/^#\//, '');
    if (!TITLES[r]) r = 'overview';
    route = r;
    document.querySelectorAll('.page').forEach(function (p) { p.hidden = p.dataset.page !== r; });
    document.querySelectorAll('#rail-nav a').forEach(function (a2) {
      a2.classList.toggle('active', a2.dataset.route === r);
    });
    el('page-title').textContent = TITLES[r];
    if (r === 'agents') Term.start(); else Term.stop();
    if (r === 'hermes') Term.startJournal(); else Term.stopJournal();
    renderCurrent();
  }

  // ---- boot ----------------------------------------------------------------

  window.addEventListener('hashchange', setRoute);
  document.addEventListener('visibilitychange', function () {
    el('paused-pill').hidden = document.visibilityState === 'visible';
    if (document.visibilityState === 'visible') refreshAll();
  });

  setInterval(tick, 1000); tick();
  setInterval(renderAges, 30000);
  setInterval(refreshAll, 60000);
  refreshAll().then(setRoute);
  setRoute();
})();
