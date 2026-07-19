// term.js - live read-only terminal mirrors + the hermes journal tail.
// Polls api/term/capture (RELATIVE path - the code-server proxy prefix must
// survive) every 2s while the agents page is visible; the server answers
// {unchanged:true} against the last hash so an idle pane costs ~60 bytes.
// The DOM is swapped only when the hash changes (no flicker), and scroll is
// re-pinned to the bottom only if the reader was already there.

(function (root) {
  'use strict';

  var TICK = 2000, TICK_ERR = 10000, JOURNAL_TICK = 10000;
  var cards = new Map(); // session -> {hash, lines, el, pre, err}
  var timer = null, journalTimer = null, active = false;

  function visible() { return document.visibilityState === 'visible'; }

  function pinned(pre) { return pre.scrollTop + pre.clientHeight >= pre.scrollHeight - 12; }

  function render(card, data) {
    var pre = card.pre;
    var keep = pinned(pre);
    pre.innerHTML = Ansi.ansiToHtml(data.text);
    if (keep) pre.scrollTop = pre.scrollHeight;
    card.hash = data.hash;
  }

  function poll(session) {
    var card = cards.get(session);
    if (!card || !active || !visible()) return;
    var url = 'api/term/capture?session=' + encodeURIComponent(session) +
      '&lines=' + card.lines + (card.hash ? '&h=' + card.hash : '');
    fetch(url, { cache: 'no-store' }).then(function (r) {
      if (!r.ok) throw new Error('http ' + r.status);
      return r.json();
    }).then(function (d) {
      card.err = 0;
      if (d.error) throw new Error(d.error);
      if (!d.unchanged) render(card, d);
      card.status.textContent = 'live';
      card.status.classList.remove('bad');
    }).catch(function (e) {
      card.err = (card.err || 0) + 1;
      card.status.textContent = 'mirror stalled: ' + e.message;
      card.status.classList.add('bad');
    });
  }

  function tickAll() {
    cards.forEach(function (card, session) {
      // per-card backoff: a failing card retries every 5th tick
      if (card.err && (card.errSkip = ((card.errSkip || 0) + 1) % Math.round(TICK_ERR / TICK))) return;
      poll(session);
    });
  }

  function makeCard(agent) {
    var name = agent.name;
    var el = document.createElement('div');
    el.className = 'term-card';
    var head = document.createElement('div');
    head.className = 'term-head';
    var dot = document.createElement('span');
    dot.className = 'term-dot ' + (agent.state || '');
    var title = document.createElement('span');
    title.className = 't-name';
    title.textContent = agent.label || name;
    var meta = document.createElement('span');
    meta.className = 't-meta';
    meta.textContent = agent.label && agent.label !== name ? 'tmux: ' + name : '';
    var status = document.createElement('span');
    status.className = 't-meta';
    status.textContent = '…';
    var actions = document.createElement('span');
    actions.className = 't-actions';
    var expand = document.createElement('button');
    expand.type = 'button';
    expand.textContent = 'expand';
    var open = document.createElement('a');
    open.className = 'lnk-btn';
    open.textContent = 'open in code-server';
    if (agent.cwd) open.href = 'http://localhost:8080/?folder=' + encodeURIComponent(agent.cwd);
    var pre = document.createElement('pre');
    pre.className = 'term';
    pre.textContent = 'connecting…';

    actions.appendChild(status);
    actions.appendChild(expand);
    if (agent.cwd) actions.appendChild(open);
    head.appendChild(dot); head.appendChild(title); head.appendChild(meta); head.appendChild(actions);
    el.appendChild(head); el.appendChild(pre);

    var card = { hash: '', lines: 200, el: el, pre: pre, status: status, dot: dot, err: 0 };
    expand.addEventListener('click', function () {
      var big = el.classList.toggle('expanded');
      expand.textContent = big ? 'collapse' : 'expand';
      card.lines = big ? 2000 : 200;
      card.hash = '';           // force a full refetch at the new depth
      poll(name);
    });
    return card;
  }

  // (re)build the grid from the agents roster; keeps existing cards' scroll
  // state when the same session is still present
  function mount(agents) {
    var grid = document.getElementById('term-grid');
    if (!grid) return;
    var seen = new Set();
    agents.forEach(function (a) {
      if (a.runtime !== 'tmux' || seen.has(a.name)) return;
      seen.add(a.name);
      var card = cards.get(a.name);
      if (!card) {
        card = makeCard(a);
        cards.set(a.name, card);
        grid.appendChild(card.el);
        if (active) poll(a.name);
      }
      card.dot.className = 'term-dot ' + (a.state || '');
    });
    cards.forEach(function (card, name) {
      if (!seen.has(name)) { card.el.remove(); cards.delete(name); }
    });
    if (!cards.size) {
      grid.innerHTML = '<p class="dim">no tmux agent sessions on this box</p>';
    }
  }

  function start() {
    if (active) return;
    active = true;
    tickAll();
    timer = setInterval(tickAll, TICK);
  }
  function stop() {
    active = false;
    if (timer) { clearInterval(timer); timer = null; }
  }

  // ---- hermes journal tail -------------------------------------------------
  function pollJournal() {
    var pre = document.getElementById('journal-pre');
    if (!pre || !visible()) return;
    fetch('api/hermes/journal?lines=150', { cache: 'no-store' }).then(function (r) {
      return r.json();
    }).then(function (d) {
      var head = '';
      if (d.error) head = '⚠ ' + d.error + (d.lines && d.lines.length ? ' — showing the last good tail:' : '') + '\n\n';
      var body = (d.lines || []).join('\n') || '(journal empty)';
      var next = head + body;
      if (pre.dataset.last === next) return;
      pre.dataset.last = next;
      var keep = pre.scrollTop + pre.clientHeight >= pre.scrollHeight - 12;
      pre.textContent = next;                    // escaped-only: journal lines are untrusted
      if (keep || !pre.dataset.scrolled) { pre.scrollTop = pre.scrollHeight; pre.dataset.scrolled = '1'; }
    }).catch(function (e) {
      pre.textContent = 'journal fetch failed: ' + e.message;
    });
  }
  function startJournal() {
    if (journalTimer) return;
    pollJournal();
    journalTimer = setInterval(pollJournal, JOURNAL_TICK);
  }
  function stopJournal() {
    if (journalTimer) { clearInterval(journalTimer); journalTimer = null; }
  }

  document.addEventListener('visibilitychange', function () {
    if (visible()) { if (active) tickAll(); if (journalTimer) pollJournal(); }
  });

  root.Term = { mount: mount, start: start, stop: stop,
                startJournal: startJournal, stopJournal: stopJournal };
})(this);
