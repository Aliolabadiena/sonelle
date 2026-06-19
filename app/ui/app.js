/* sonelle GUI front-end: xterm.js tabs wired to the Python (pywinpty) backend.
   Python->JS push: window.__ptyOutput(tabId, base64) / window.__ptyExit(tabId, code).
   JS->Python: window.pywebview.api.{new_tab,send_input,resize,close_tab,list_projects,win_*}.
   In a plain browser (no pywebview bridge) it falls back to a visual DEMO so the UI previews. */
(function () {
  "use strict";

  const TABS = new Map();      // tabId -> entry {term, fit, pane, tabEl, ro, disposers, dead}
  const PENDING = new Map();   // tabId -> [Uint8Array] buffered before the term is registered
  let active = null;
  let tabCount = 0;
  let tabSeq = 0;              // tab label counter: tabs are named 1, 2, 3, ... in the order opened
  let live = false;            // true once the pywebview bridge is present

  const $ = (id) => document.getElementById(id);

  // Palette tuned to the brand-loop gif (blue / indigo / purple), cooler than the old lilac.
  const THEME = {
    background: "rgba(0,0,0,0)", foreground: "#d3d6ec",
    cursor: "#9aa6ec", cursorAccent: "#0d1024",
    selectionBackground: "rgba(110,124,210,.32)",
    black: "#232a4a", red: "#d98aa0", green: "#9bbf90", yellow: "#dcc58a",
    blue: "#8f9ee6", magenta: "#b0a0e6", cyan: "#8fc6dc", white: "#d3d6ec",
    brightBlack: "#5a5f84", brightRed: "#e7a3b4", brightGreen: "#b2d2a8",
    brightYellow: "#ead7a6", brightBlue: "#a9b6ee", brightMagenta: "#c4b8ee",
    brightCyan: "#aadcdc", brightWhite: "#efeefb"
  };

  // narration colours written straight into the terminal: PINK = sonelle texting you (bold, the
  // "bypass permissions" magenta = --pink #ff79c6); WHITE = the quiet play-by-play of what's happening.
  const PINK_SGR = "\x1b[1;38;2;255;121;198m";
  const STATUS_SGR = "\x1b[38;2;176;182;224m";
  const SGR_RESET = "\x1b[0m";

  // small speaker glyph for the per-tab voice toggle (filled when on, slashed-quiet when off via css)
  const SPK_SVG =
    '<svg viewBox="0 0 24 24" aria-hidden="true">' +
    '<path d="M4 9v6h4l5 4V5L8 9H4z" fill="currentColor"/>' +
    '<path class="wave" d="M15.5 8.5a4.5 4.5 0 0 1 0 7" fill="none" stroke="currentColor" ' +
    'stroke-width="1.8" stroke-linecap="round"/></svg>';

  function b64ToBytes(b64) {
    const bin = atob(b64);
    const buf = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) buf[i] = bin.charCodeAt(i);
    return buf;
  }

  function newTermObj() {
    const term = new Terminal({
      allowTransparency: true,
      disableStdin: true,          // output only - you type in the composer, not the window
      // Cascadia MONO first (no ligatures): xterm forces one glyph per cell, so a ligature font like
      // Cascadia Code makes contextual glyphs overlap into neighbours - that was the "words mashed
      // together" look. Consolas is the always-present Windows monospace fallback.
      fontFamily: '"Cascadia Mono", Consolas, "Cascadia Code", "Courier New", monospace',
      fontSize: 13, lineHeight: 1.2, cursorBlink: true, scrollback: 5000, theme: THEME
    });
    const fit = new FitAddon.FitAddon();   // double name: module.FitAddon
    term.loadAddon(fit);
    return { term, fit };
  }

  // The default DOM renderer GHOSTS and FLICKERS over a transparent (glass) background - old glyphs
  // bleed through because a transparent "space" cell never paints over them, which is what mashed the
  // text and made it flutter. The WebGL renderer composites on the GPU and clears every cell each
  // frame, so it stays crisp. If a WebGL context can't be created (driver/blocklist) we dispose it
  // and silently keep the DOM renderer. MUST be loaded AFTER term.open().
  function mountWebgl(term) {
    try {
      if (!(window.WebglAddon && window.WebglAddon.WebglAddon)) return null;
      const addon = new WebglAddon.WebglAddon();
      addon.onContextLoss(() => { try { addon.dispose(); } catch (e) {} });
      term.loadAddon(addon);
      return addon;
    } catch (e) { return null; }
  }

  // Coalesce a burst of ResizeObserver callbacks (window drag/animation fires many per second) into a
  // single fit per frame - refitting on every pixel is what made the terminal churn/flutter on resize.
  function scheduleFit(entry) {
    if (entry._fitRaf) return;
    entry._fitRaf = requestAnimationFrame(() => { entry._fitRaf = 0; safeFit(entry); });
  }

  function safeFit(entry) {
    const p = entry.pane;
    if (!p || p.clientWidth === 0 || p.clientHeight === 0) return;  // hidden/zero-size -> skip
    try { entry.fit.fit(); } catch (e) {}
  }

  // ---------- Python -> JS push sinks (installed immediately) ----------
  // While sonelle is typing a narration line straight into the terminal, hold back claude's own
  // bytes so the two never interleave mid-line; the held output is flushed the instant she finishes.
  function writeOrHold(t, data) {
    if (t.narrating) {
      if (!t.holdback) t.holdback = [];
      if (t.holdback.length < 4000) t.holdback.push(data);   // capped so a long burst can't grow unbounded
      return;
    }
    try { t.term.write(data); } catch (e) {}
  }
  window.__ptyOutput = function (tabId, b64) {
    const buf = b64ToBytes(b64);
    const t = TABS.get(tabId);
    if (t) { writeOrHold(t, buf); return; }   // Uint8Array -> xterm stitches partial UTF-8
    let q = PENDING.get(tabId);
    if (!q) { q = []; PENDING.set(tabId, q); }
    if (q.length < 4000) q.push(buf);         // buffer pre-register output (capped so a never-registered id can't grow unbounded)
  };
  window.__ptyExit = function (tabId, code) {
    const t = TABS.get(tabId);
    if (!t) return;
    t.dead = true;
    const c = (code === null || code === undefined) ? "" : " (" + code + ")";
    writeOrHold(t, "\r\n\x1b[2m[process exited" + c + "]\x1b[0m\r\n");
    if (t.tabEl) t.tabEl.classList.add("dead");
  };

  // ---------- narrator push: a humanised line typed straight INTO the terminal (+ optional audio) ----
  // Python (narrator.py) calls this when a tab's voice is on. kind "voice" = sonelle texting you
  // (bold pink, with a chat caret) - openers, check-ins, milestones, her answers; kind "status" =
  // the quiet play-by-play (soft white). The line is typed word-by-word into the xterm itself so it
  // reads like she's messaging you live; audio (if any) plays in the page (WebView2 HTML5 audio).
  window.__narrate = function (tabId, text, kind, mime, b64) {
    const t = TABS.get(tabId);
    if (!t) return;
    pushNarration(t, text, kind, mime, b64);
  };
  function pushNarration(entry, text, kind, mime, b64) {
    if (b64 && mime) playNarrationAudio(mime, b64);
    if (!text) return;
    if (!entry.narrq) entry.narrq = [];
    entry.narrq.push({ text: String(text), kind: kind === "voice" ? "voice" : "status" });
    if (!entry.narrating) runNarrQueue(entry);
  }
  function runNarrQueue(entry) {
    if (!entry.narrq || !entry.narrq.length) {
      entry.narrating = false;                          // burst done: release any held claude output
      const hb = entry.holdback || []; entry.holdback = [];
      for (let i = 0; i < hb.length; i++) { try { entry.term.write(hb[i]); } catch (e) {} }
      return;
    }
    entry.narrating = true;
    const item = entry.narrq.shift();
    typeNarration(entry, item.text, item.kind, () => runNarrQueue(entry));
  }
  // type one line word-by-word: pink + a "> " caret for her voice, soft white + indent for status
  function typeNarration(entry, text, kind, done) {
    const term = entry.term;
    const color = (kind === "voice") ? PINK_SGR : STATUS_SGR;
    const prefix = (kind === "voice") ? "> " : "  ";
    const tokens = text.split(/(\s+)/);                 // keep the whitespace as its own tokens
    let i = 0;
    try { term.write("\r\n" + color + prefix); } catch (e) {}
    const tick = () => {
      if (i >= tokens.length) {
        try { term.write(SGR_RESET + "\r\n", done); } catch (e) { done(); }
        return;
      }
      const tok = tokens[i++];
      try { term.write(tok, () => setTimeout(tick, 34)); } catch (e) { setTimeout(tick, 34); }
    };
    tick();
  }
  function playNarrationAudio(mime, b64) {
    try {
      const a = new Audio("data:" + mime + ";base64," + b64);
      a.play().catch(() => {});       // autoplay can reject silently; the typed line still shows
    } catch (e) {}
  }

  // ---------- tab naming ----------
  // Tabs are labelled with a plain incrementing number (1, 2, 3, ...) in the order they were opened.
  // The counter only ever climbs, so closing a tab never renumbers the rest - the next new tab keeps
  // counting up rather than reusing a freed number.
  function nextTabName() { return String(++tabSeq); }

  // ---------- tab pills ----------
  function makeTabEl(tabId, label) {
    const el = document.createElement("div");
    el.className = "tab";
    el.dataset.id = tabId;
    const lab = document.createElement("span");
    lab.className = "label";
    lab.textContent = label;
    // per-tab voice toggle, right on the pill: mute the boring research sessions, keep the
    // important ones talking. Independent per tab (you can mute tab 2 while tab 1 still speaks).
    const spk = document.createElement("span");
    spk.className = "spk";
    spk.title = "voice: off";
    spk.setAttribute("aria-label", "toggle voice for this tab");
    spk.innerHTML = SPK_SVG;
    const x = document.createElement("span");
    x.className = "x";
    x.textContent = "×";
    x.title = "close";
    el.appendChild(lab);
    el.appendChild(spk);
    el.appendChild(x);
    el.addEventListener("click", (e) => {
      if (x.contains(e.target)) closeTab(tabId);
      else if (spk.contains(e.target)) toggleTabVoice(tabId);
      else activateTab(tabId);
    });
    $("tabs").appendChild(el);
    return el;
  }

  function activateTab(tabId) {
    active = tabId;
    for (const [id, e] of TABS) {
      const on = (id === tabId);
      e.pane.style.display = on ? "block" : "none";
      if (e.tabEl) e.tabEl.classList.toggle("active", on);
    }
    const e = TABS.get(tabId);
    if (e) {
      if (e.tabEl) { try { e.tabEl.scrollIntoView({ block: "nearest", inline: "nearest" }); } catch (x) {} }
      requestAnimationFrame(() => {
        safeFit(e);
        if (live && !e.dead) { try { window.pywebview.api.resize(tabId, e.term.cols, e.term.rows); } catch (x) {} }
        const inp = $("cmd"); if (inp) inp.focus();   // focus the composer, not the (read-only) terminal
      });
    }
    updateWelcome();
  }

  function closeTab(tabId) {
    const e = TABS.get(tabId);
    if (!e) return;
    if (live) { try { window.pywebview.api.close_tab(tabId); } catch (x) {} }
    try { if (e.ro) e.ro.disconnect(); } catch (x) {}
    try { (e.disposers || []).forEach((d) => d && d.dispose && d.dispose()); } catch (x) {}
    try { if (e.webgl) e.webgl.dispose(); } catch (x) {}   // free the GL context before the term goes
    try { e.term.dispose(); } catch (x) {}
    try { e.pane.remove(); } catch (x) {}
    try { if (e.tabEl) e.tabEl.remove(); } catch (x) {}
    TABS.delete(tabId);
    PENDING.delete(tabId);
    if (active === tabId) {
      active = null;
      const ids = Array.from(TABS.keys());
      if (ids.length) activateTab(ids[ids.length - 1]);
      else updateWelcome();
    }
  }

  function updateWelcome() {
    $("welcome").hidden = TABS.size > 0;
  }

  function buildPane() {
    const pane = document.createElement("div");
    pane.className = "pane";
    $("stack").appendChild(pane);
    const { term, fit } = newTermObj();
    term.open(pane);
    const webgl = mountWebgl(term);   // GPU renderer (after open): crisp, no flutter over the glass
    // Scroll fix: this pane is OUTPUT-ONLY (disableStdin), but claude's TUI turns ON mouse tracking,
    // which makes xterm hand the wheel to the app instead of scrolling its own scrollback - so the
    // wheel "sticks" (you scroll up but can't come back down). Intercept the wheel in the CAPTURE
    // phase and drive xterm's scrollback directly, so the wheel always scrolls history, both ways.
    pane.addEventListener("wheel", (e) => {
      try {
        let lines;
        if (e.deltaMode === 1) lines = e.deltaY;                          // already line units
        else if (e.deltaMode === 2) lines = e.deltaY * (term.rows || 24); // page units
        else lines = e.deltaY / 24;                                       // pixels -> ~lines
        lines = lines < 0 ? Math.floor(lines) : Math.ceil(lines);
        if (lines) term.scrollLines(lines);
      } catch (x) {}
      e.preventDefault();
      e.stopPropagation();        // keep it from reaching xterm's mouse-report path
    }, { passive: false, capture: true });
    return { term, fit, pane, webgl, tabEl: null, ro: null, disposers: [], dead: false,
             voice: false, narration: false, narrating: false, narrq: [], holdback: [] };
  }

  // ---------- live tab (real backend) ----------
  async function createLiveTab(project) {
    const entry = buildPane();
    for (const [, e] of TABS) e.pane.style.display = "none";
    await new Promise((r) => requestAnimationFrame(() => r()));
    safeFit(entry);
    const cols = entry.term.cols || 80;
    const rows = entry.term.rows || 24;
    let res;
    try { res = await window.pywebview.api.new_tab(project || null, cols, rows); }
    catch (err) { res = { ok: false, error: String(err) }; }
    if (!res || !res.ok) {
      // if Python actually created a session but we still treat this as an error, reclaim it
      if (res && res.tabId) { try { window.pywebview.api.close_tab(res.tabId); } catch (x) {} }
      entry.term.write("\r\n\x1b[31m[failed to start: " + ((res && res.error) || "unknown") + "]\x1b[0m\r\n");
      const did = "x" + (++tabCount);
      entry.tabEl = makeTabEl(did, "error");
      entry.dead = true;
      TABS.set(did, entry);
      activateTab(did);
      return;
    }
    const tabId = res.tabId;
    tabCount++;
    entry.narration = !!(res && res.narration);   // backend wired claude's hooks for this tab -> voice can speak
    entry.name = project || nextTabName();   // a routed project keeps its name; otherwise a plain number
    entry.tabEl = makeTabEl(tabId, entry.name);
    updateTabVoiceEl(entry);                  // reflect this tab's (off-by-default) voice state on its pill
    TABS.set(tabId, entry);
    const q = PENDING.get(tabId);
    if (q) { q.forEach((b) => entry.term.write(b)); PENDING.delete(tabId); }
    entry.disposers.push(entry.term.onData((d) => {
      try { window.pywebview.api.send_input(tabId, d); } catch (x) {}
    }));
    entry.disposers.push(entry.term.onResize(({ cols, rows }) => {
      try { window.pywebview.api.resize(tabId, cols, rows); } catch (x) {}
    }));
    entry.ro = new ResizeObserver(() => scheduleFit(entry));
    entry.ro.observe(entry.pane);
    activateTab(tabId);
    try { window.pywebview.api.resize(tabId, entry.term.cols, entry.term.rows); } catch (x) {}
  }

  // ---------- composer (the one input; forwards to the active tab's PTY) ----------
  function sendRaw(data) {
    if (!active) return;
    if (live) { try { window.pywebview.api.send_input(active, data); } catch (x) {} }
    else { const e = TABS.get(active); if (e) e.term.write(data === "\r" ? "\r\n" : data); }  // demo echo
  }
  function sendLine() {
    const inp = $("cmd");
    if (!active || !inp) return;
    if (live) { try { window.pywebview.api.send_input(active, inp.value + "\r"); } catch (x) {} }
    else { const e = TABS.get(active); if (e) e.term.write(inp.value + "\r\n"); }
    inp.value = "";
  }
  // forward the keys an interactive TUI (claude) needs, since the terminal itself can't be typed in
  function composerKey(e) {
    if (e.key === "Enter") { e.preventDefault(); sendLine(); return; }
    if (e.key === "ArrowUp") { e.preventDefault(); sendRaw("\x1b[A"); return; }     // menu / history (no-op in a 1-line input)
    if (e.key === "ArrowDown") { e.preventDefault(); sendRaw("\x1b[B"); return; }
    if (e.key === "Tab") { e.preventDefault(); sendRaw("\t"); return; }
    if (e.key === "Escape") { e.preventDefault(); sendRaw("\x1b"); return; }
    if (e.ctrlKey && (e.key === "c" || e.key === "C")) {
      // interrupt only when NOTHING is selected. A selection in the read-only terminal lives in
      // window.getSelection(); a selection inside the composer input does NOT (inputs have their own
      // selection model) - check both so Ctrl+C copies composer text instead of killing the agent.
      const sel = (window.getSelection && window.getSelection().toString()) || "";
      const inp = $("cmd");
      const inpSel = !!(inp && document.activeElement === inp && inp.selectionStart !== inp.selectionEnd);
      if (!sel && !inpSel) { e.preventDefault(); sendRaw("\x03"); }
      return;
    }
  }

  // ---------- Ctrl+V image paste -> temp file -> @"path" token (enters claude's context) ----------
  // The clipboard image is saved by Python to a temp file; we drop an @"<path>" token into the
  // composer. When you send a routed prompt, the terminal extracts that path and tells claude to
  // read it - same mechanism as :attach / @path, just sourced from the clipboard.
  async function attachPastedImage(b64, ext) {
    if (!live) return;                       // demo preview has no backend to save to
    let res = null;
    try { res = await window.pywebview.api.save_paste_image(b64, ext); } catch (x) { res = null; }
    if (!res || !res.ok || !res.path) return;
    const inp = $("cmd");
    if (!inp) return;
    const token = '@"' + res.path + '"';
    const cur = inp.value.replace(/\s+$/, "");
    inp.value = (cur ? cur + " " : "") + token + " ";
    inp.focus();
    try { inp.setSelectionRange(inp.value.length, inp.value.length); } catch (x) {}
  }
  function onComposerPaste(e) {
    const items = (e.clipboardData && e.clipboardData.items) || [];
    for (let i = 0; i < items.length; i++) {
      const it = items[i];
      if (it.kind === "file" && it.type && it.type.indexOf("image/") === 0) {
        const file = it.getAsFile();
        if (!file) continue;
        e.preventDefault();                  // don't let the raw blob land as junk text
        const ext = "." + ((it.type.split("/")[1] || "png"));
        const reader = new FileReader();
        reader.onload = () => {
          const b64 = String(reader.result || "").split(",")[1] || "";
          if (b64) attachPastedImage(b64, ext);
        };
        reader.readAsDataURL(file);
        return;                              // first image only
      }
    }
  }

  // ---------- per-tab voice narration toggle (each tab has its own speaker on its pill) ----------
  function updateTabVoiceEl(entry) {
    if (!entry || !entry.tabEl) return;
    const spk = entry.tabEl.querySelector(".spk");
    if (!spk) return;
    const on = !!entry.voice;
    spk.classList.toggle("on", on);
    spk.title = on ? "voice: on (sonelle speaks in this tab)" : "voice: off (muted)";
  }
  function toggleTabVoice(tabId) {
    const e = TABS.get(tabId);
    if (!e) return;
    // turning ON but the backend never wired claude's hooks for this tab -> say so, stay off
    if (live && !e.narration && !e.voice) {
      pushNarration(e, "voice needs a claude build with --settings hooks - staying muted.", "voice");
      return;
    }
    e.voice = !e.voice;
    if (live) { try { window.pywebview.api.set_narration(tabId, e.voice); } catch (x) {} }
    updateTabVoiceEl(e);
    pushNarration(e, e.voice ? "voice on - i'll talk you through it." : "voice off - going quiet here.", "voice");
  }

  // ---------- brand-loop gif: drag with throw + edge-bounce, then drift home after idle ----------
  // The mascot floats free (transparent, no box). Grab it; release while moving and it keeps going,
  // BOUNCING off the window edges until friction stops it. 30s after it settles it returns to its
  // home corner on two straight, eased, axis-aligned moves (horizontal, then vertical) - never a tp.
  let loopRAF = 0, loopReturnTimer = 0;
  function loopHome(el) {
    const w = el.offsetWidth || 120, h = el.offsetHeight || 120;
    return [Math.max(0, window.innerWidth - w - 30), Math.max(0, window.innerHeight - h - 8)];  // matches the CSS corner
  }
  function loopMaxX(el) { return Math.max(0, window.innerWidth - (el.offsetWidth || 120)); }
  function loopMaxY(el) { return Math.max(0, window.innerHeight - (el.offsetHeight || 120)); }
  function setLoopPos(el, x, y) { el.style.right = "auto"; el.style.bottom = "auto"; el.style.left = x + "px"; el.style.top = y + "px"; }
  function cancelLoopMotion() {
    if (loopRAF) { cancelAnimationFrame(loopRAF); loopRAF = 0; }
    if (loopReturnTimer) { clearTimeout(loopReturnTimer); loopReturnTimer = 0; }
  }
  function wireBrandloopDrag() {
    const el = $("brandloop");
    if (!el) return;
    el.style.cursor = "grab";
    let dragging = false, sx = 0, sy = 0, ox = 0, oy = 0;
    let lastX = 0, lastY = 0, lastT = 0, vx = 0, vy = 0;
    el.addEventListener("mousedown", (e) => {
      cancelLoopMotion();                 // grabbing it interrupts any throw/return in progress
      dragging = true;
      el.style.cursor = "grabbing";
      const r = el.getBoundingClientRect();
      setLoopPos(el, r.left, r.top);      // pin its current spot before we start moving it
      ox = r.left; oy = r.top; sx = e.clientX; sy = e.clientY;
      lastX = r.left; lastY = r.top; lastT = performance.now(); vx = 0; vy = 0;
      e.preventDefault(); e.stopPropagation();
    });
    window.addEventListener("mousemove", (e) => {
      if (!dragging) return;
      const nx = Math.max(0, Math.min(loopMaxX(el), ox + (e.clientX - sx)));
      const ny = Math.max(0, Math.min(loopMaxY(el), oy + (e.clientY - sy)));
      setLoopPos(el, nx, ny);
      const t = performance.now(), dt = t - lastT;
      if (dt > 0) { vx = (nx - lastX) / dt; vy = (ny - lastY) / dt; }   // px per ms
      lastX = nx; lastY = ny; lastT = t;
    });
    window.addEventListener("mouseup", () => {
      if (!dragging) return;
      dragging = false;
      el.style.cursor = "grab";
      if (performance.now() - lastT > 80) { vx = 0; vy = 0; }   // paused before letting go -> no throw
      if (Math.hypot(vx, vy) > 0.05) throwLoop(el, vx, vy);     // released mid-motion -> fling + bounce
      else scheduleLoopReturn(el);                              // dropped still -> head home after 30s
    });
    window.addEventListener("resize", () => {
      if (loopRAF || dragging) return;
      if (el.style.left === "" || el.style.left === "auto") return;
      setLoopPos(el, Math.min(loopMaxX(el), parseFloat(el.style.left) || 0),
                     Math.min(loopMaxY(el), parseFloat(el.style.top) || 0));
    });
  }
  // inertia: integrate velocity with friction, bounce off the 4 walls, until it slows to rest
  function throwLoop(el, vx, vy) {
    let x = parseFloat(el.style.left) || 0, y = parseFloat(el.style.top) || 0;
    let prev = performance.now();
    const FRICTION = 0.0026, RESTITUTION = 0.72;   // damping per ms; energy kept per wall bounce
    const SLOW = 0.5;                              // play the whole throw at HALF speed (2x slower bounce + decel)
    const step = (now) => {
      const dt = Math.min(40, now - prev) * SLOW; prev = now;
      x += vx * dt; y += vy * dt;
      const mx = loopMaxX(el), my = loopMaxY(el);
      if (x < 0) { x = 0; vx = -vx * RESTITUTION; } else if (x > mx) { x = mx; vx = -vx * RESTITUTION; }
      if (y < 0) { y = 0; vy = -vy * RESTITUTION; } else if (y > my) { y = my; vy = -vy * RESTITUTION; }
      const damp = Math.exp(-FRICTION * dt); vx *= damp; vy *= damp;
      setLoopPos(el, x, y);
      if (Math.hypot(vx, vy) > 0.015) { loopRAF = requestAnimationFrame(step); }
      else { loopRAF = 0; scheduleLoopReturn(el); }
    };
    loopRAF = requestAnimationFrame(step);
  }
  // 30s after it settles, drift home on TWO straight axis-aligned moves (horizontal, then vertical)
  function scheduleLoopReturn(el) {
    if (loopReturnTimer) clearTimeout(loopReturnTimer);
    loopReturnTimer = setTimeout(() => { loopReturnTimer = 0; returnLoopHome(el); }, 30000);
  }
  function easeInOut(t) { return t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2; }
  function animLoopAxis(el, axis, from, to, dur, done) {
    const start = performance.now();
    const step = (now) => {
      const p = Math.min(1, (now - start) / dur);
      const v = from + (to - from) * easeInOut(p);   // accelerate then slow down
      if (axis === "x") el.style.left = v + "px"; else el.style.top = v + "px";
      if (p < 1) { loopRAF = requestAnimationFrame(step); }
      else { loopRAF = 0; if (done) done(); }
    };
    loopRAF = requestAnimationFrame(step);
  }
  function returnLoopHome(el) {
    const home = loopHome(el);
    const x0 = parseFloat(el.style.left) || 0, y0 = parseFloat(el.style.top) || 0;
    animLoopAxis(el, "x", x0, home[0], 950, () => {        // move 1: slide across to home X...
      animLoopAxis(el, "y", y0, home[1], 950, () => { loopRAF = 0; });   // move 2: ...then down to home Y
    });
  }

  // ---------- chrome wiring (safe with or without the bridge) ----------
  function wireChrome() {
    const openTab = () => { if (live) createLiveTab(null); else createDemoTab(); };
    $("btn-new").addEventListener("click", openTab);
    $("w-open").addEventListener("click", openTab);
    wireBrandloopDrag();          // the mascot gif is grab-and-drop, and remembers where you leave it
    // Ctrl+T opens a new terminal (the + button advertises this shortcut; WebView2 has no default for it)
    document.addEventListener("keydown", (e) => {
      if (e.ctrlKey && !e.altKey && !e.shiftKey && (e.key === "t" || e.key === "T")) { e.preventDefault(); openTab(); }
    });
    $("send").addEventListener("click", sendLine);
    $("cmd").addEventListener("keydown", composerKey);
    $("cmd").addEventListener("paste", onComposerPaste);   // Ctrl+V an image -> attach it for claude
    // window drag: pywebview drags from '.pywebview-drag-region' (#titlebar); stop it over the
    // interactive '.nodrag' controls so buttons/tabs/the input still click instead of moving the window.
    const tb = $("titlebar");
    if (tb) tb.addEventListener("mousedown", (e) => {
      if (e.target.closest(".nodrag")) e.stopPropagation();
    });
    // clicking the read-only terminal shouldn't strand keyboard focus: refocus the composer
    // unless the user just selected text (so copy still works)
    $("stack").addEventListener("mouseup", () => {
      setTimeout(() => {
        const sel = (window.getSelection && window.getSelection().toString()) || "";
        const inp = $("cmd");
        if (!sel && inp) inp.focus();
      }, 0);
    });
    $("btn-min").addEventListener("click", () => { if (live) { try { window.pywebview.api.win_minimize(); } catch (x) {} } });
    $("btn-close").addEventListener("click", () => { if (live) { try { window.pywebview.api.win_close(); } catch (x) {} } });
    $("btn-max").addEventListener("click", () => { if (live) { try { window.pywebview.api.win_toggle_max(); } catch (x) {} } });
  }

  function initLive() {
    if (live) return;
    live = true;
    createLiveTab(null);
  }

  // ---------- demo (plain-browser preview only; no backend) ----------
  function createDemoTab() {
    const entry = buildPane();
    for (const [, e] of TABS) e.pane.style.display = "none";
    const did = "demo" + (++tabCount);
    entry.name = nextTabName();
    entry.tabEl = makeTabEl(did, entry.name);
    updateTabVoiceEl(entry);
    TABS.set(did, entry);
    entry.ro = new ResizeObserver(() => scheduleFit(entry));
    entry.ro.observe(entry.pane);
    activateTab(did);
    requestAnimationFrame(() => {
      safeFit(entry);
      entry.term.write("  \x1b[38;2;138;150;230m▸\x1b[0m ");   // bare prompt - matches the real -Bare mode
    });
  }

  function initDemo() {
    if (live) return;
    createDemoTab();
  }

  // ---------- boot ----------
  document.addEventListener("DOMContentLoaded", () => {
    wireChrome();
    updateWelcome();
    window.addEventListener("pywebviewready", initLive);
    if (window.pywebview && window.pywebview.api) initLive();
    // browser-preview fallback ONLY: if the pywebview bridge object never appears, show the demo.
    // In the real app window.pywebview exists (even before 'ready'), so the demo never races live.
    setTimeout(() => { if (!live && typeof window.pywebview === "undefined") initDemo(); }, 1500);
    // dead-state guard: bridge object present but api/ready never arrived -> retry, else surface it
    setTimeout(() => {
      if (live) return;
      if (window.pywebview && window.pywebview.api) { initLive(); return; }
      if (typeof window.pywebview !== "undefined") {
        const w = $("welcome");
        if (w) { w.hidden = false; const p = w.querySelector("p"); if (p) p.textContent = "the app bridge did not initialize - try reopening sonelle"; }
      }
    }, 4000);
  });
})();
