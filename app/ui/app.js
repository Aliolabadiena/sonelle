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
  let live = false;            // true once the pywebview bridge is present

  const $ = (id) => document.getElementById(id);

  const THEME = {
    background: "rgba(0,0,0,0)", foreground: "#d7d0e6",
    cursor: "#b9a6dc", cursorAccent: "#140f22",
    selectionBackground: "rgba(150,120,200,.30)",
    black: "#2a2140", red: "#d98aa0", green: "#9bbf90", yellow: "#dcc58a",
    blue: "#8fa6d6", magenta: "#b59ad6", cyan: "#8fcaca", white: "#d7d0e6",
    brightBlack: "#5a4f74", brightRed: "#e7a3b4", brightGreen: "#b2d2a8",
    brightYellow: "#ead7a6", brightBlue: "#a9bce4", brightMagenta: "#cbb4e6",
    brightCyan: "#aadcdc", brightWhite: "#efe9f8"
  };

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
  window.__ptyOutput = function (tabId, b64) {
    const bin = atob(b64);
    const buf = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) buf[i] = bin.charCodeAt(i);
    const t = TABS.get(tabId);
    if (t) { t.term.write(buf); return; }   // Uint8Array -> xterm stitches partial UTF-8
    let q = PENDING.get(tabId);
    if (!q) { q = []; PENDING.set(tabId, q); }
    if (q.length < 4000) q.push(buf);       // buffer pre-register output (capped so a never-registered id can't grow unbounded)
  };
  window.__ptyExit = function (tabId, code) {
    const t = TABS.get(tabId);
    if (!t) return;
    t.dead = true;
    const c = (code === null || code === undefined) ? "" : " (" + code + ")";
    t.term.write("\r\n\x1b[2m[process exited" + c + "]\x1b[0m\r\n");
    if (t.tabEl) t.tabEl.classList.add("dead");
  };

  // ---------- tab naming ----------
  // Each tab reads like a person (Megan, Sakura, Sidney...) from the big pool in names.js, instead of
  // "sonelle 1 / sonelle 2". Prefer a name not already on an open tab; fall back to any (or "sonelle"
  // if the pool is somehow empty) so a tab always gets a label.
  function pickName() {
    const pool = (window.SONELLE_NAMES && window.SONELLE_NAMES.length) ? window.SONELLE_NAMES : null;
    if (!pool) return "sonelle";
    const used = new Set();
    for (const [, e] of TABS) { if (e && e.name) used.add(e.name); }
    for (let i = 0; i < 16; i++) {
      const n = pool[Math.floor(Math.random() * pool.length)];
      if (!used.has(n)) return n;
    }
    return pool[Math.floor(Math.random() * pool.length)];
  }

  // ---------- tab pills ----------
  function makeTabEl(tabId, label) {
    const el = document.createElement("div");
    el.className = "tab";
    el.dataset.id = tabId;
    const lab = document.createElement("span");
    lab.className = "label";
    lab.textContent = label;
    const x = document.createElement("span");
    x.className = "x";
    x.textContent = "×";
    x.title = "close";
    el.appendChild(lab);
    el.appendChild(x);
    el.addEventListener("click", (e) => {
      if (e.target === x) closeTab(tabId);
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
    return { term, fit, pane, webgl, tabEl: null, ro: null, disposers: [], dead: false };
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
    entry.name = project || pickName();   // a project keeps its name; otherwise a random woman's name
    entry.tabEl = makeTabEl(tabId, entry.name);
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
      const sel = (window.getSelection && window.getSelection().toString()) || "";
      if (!sel) { e.preventDefault(); sendRaw("\x03"); }   // no selection -> interrupt; with one -> let copy happen
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

  // ---------- chrome wiring (safe with or without the bridge) ----------
  function wireChrome() {
    const openTab = () => { if (live) createLiveTab(null); else createDemoTab(); };
    $("btn-new").addEventListener("click", openTab);
    $("w-open").addEventListener("click", openTab);
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
    entry.name = pickName();
    entry.tabEl = makeTabEl(did, entry.name);
    TABS.set(did, entry);
    entry.ro = new ResizeObserver(() => scheduleFit(entry));
    entry.ro.observe(entry.pane);
    activateTab(did);
    requestAnimationFrame(() => {
      safeFit(entry);
      entry.term.write("  \x1b[38;2;154;134;196m▸\x1b[0m ");   // bare prompt - matches the real -Bare mode
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
