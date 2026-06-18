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
      fontFamily: 'Cascadia Code, Cascadia Mono, Consolas, "Courier New", monospace',
      fontSize: 13, lineHeight: 1.15, cursorBlink: true, scrollback: 5000, theme: THEME
    });
    const fit = new FitAddon.FitAddon();   // double name: module.FitAddon
    term.loadAddon(fit);
    return { term, fit };
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
        e.term.focus();
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
    return { term, fit, pane, tabEl: null, ro: null, disposers: [], dead: false };
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
    entry.tabEl = makeTabEl(tabId, project || ("sonelle " + tabCount));
    TABS.set(tabId, entry);
    const q = PENDING.get(tabId);
    if (q) { q.forEach((b) => entry.term.write(b)); PENDING.delete(tabId); }
    entry.disposers.push(entry.term.onData((d) => {
      try { window.pywebview.api.send_input(tabId, d); } catch (x) {}
    }));
    entry.disposers.push(entry.term.onResize(({ cols, rows }) => {
      try { window.pywebview.api.resize(tabId, cols, rows); } catch (x) {}
    }));
    entry.ro = new ResizeObserver(() => safeFit(entry));
    entry.ro.observe(entry.pane);
    activateTab(tabId);
    try { window.pywebview.api.resize(tabId, entry.term.cols, entry.term.rows); } catch (x) {}
  }

  // ---------- chrome wiring (safe with or without the bridge) ----------
  function wireChrome() {
    const openTab = () => { if (live) createLiveTab(null); else createDemoTab(); };
    $("btn-new").addEventListener("click", openTab);
    $("w-open").addEventListener("click", openTab);
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
    entry.tabEl = makeTabEl(did, "sonelle " + tabCount);
    TABS.set(did, entry);
    entry.ro = new ResizeObserver(() => safeFit(entry));
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
