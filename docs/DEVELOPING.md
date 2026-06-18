# DEVELOPING sonelle (improving the engine itself)

This guide is for working ON the engine (this repo), not for using it to run projects.
Open it via the terminal command `:dev` (which seeds a Claude session here with this context),
or read it before you `cd` into the sonelle folder and run `claude`.

> The root `CLAUDE.md` is the **dispatcher** (how a session routes PROJECTS). When you are
> developing the engine, THIS file governs the session - not the dispatcher framing.

## Session framing (how `:dev` works)
Trigger it with `:dev [prompt]` OR with the grammar using the engine's own name as the shortcode
(`<engine-name>: <prompt>`, e.g. `sonelle, sonelle: add a :foo command`) - both land here. sonelle
launches a Claude session in the engine root, seeded with these instructions. Claude Code ALSO auto-loads the root `CLAUDE.md` (the dispatcher template the engine
ships) into context - but **this file is your sole authority for the session**. If anything in
`CLAUDE.md` talks about routing a shortcode, scaffolding a project, reading hub state, or an
end-of-task ritual, **disregard it**: you are improving the ENGINE, not running a project through it.
The invariants below are absolute and override any dispatcher guidance.

## What you are touching
sonelle is the reusable ENGINE: the dispatcher, the registry format, the templates, the
scaffold/heal/self-improve tools, the terminal, and the lanes. It is a **public** repo with
**zero personal data**.

## Invariants (do NOT break these)
1. **Pure ASCII PowerShell.** PS 5.1 misreads non-ASCII in a no-BOM `.ps1`. Build any glyphs at
   runtime via `[char]` codepoints. selftest fails on any non-ASCII byte in a `.ps1`.
2. **selftest is the gate.** Run `tools\selftest.ps1` and confirm **ALL PASS** before every commit.
   If you add a feature, EXTEND selftest to cover it - the engine must stay self-verifying.
3. **No personal data, ever.** No real hub paths, project names, keys, or memory in this repo.
   `sonelle.config.json`, `memory/`, `*_TODO.txt` are gitignored on purpose - keep it that way.
4. **Do not pollute the engine with hub state.** The engine is not one of your projects. Never
   scaffold TODO / ledger / project-CLAUDE / memory into the engine root.
5. **Registry rows only via `new_project.ps1`** (fixed column shape; never hand-edit rows).
6. **Keep the split:** root `CLAUDE.md` = the dispatcher (and the template a hub adopts);
   `templates\CLAUDE.template.md` = the per-project skeleton. Do not merge these two roles.

## Workflow
1. Read `docs\ARCHITECTURE.md` first (how the pieces fit + the CLAUDE.md load behavior).
2. Make the change. Match the existing style (ASCII; the palette + format-string `Write-Host` calls).
3. `tools\selftest.ps1` -> ALL PASS. Red = fix or revert; never commit red.
4. Commit + push to the public repo. Everything is git-versioned, so **rewind freely** -
   experiment, and `git revert` / `git reset` if a direction turns out wrong.
5. Capture any lesson in YOUR memory (not the engine) so the next session recalls it.

## Common changes
- **New terminal command:** add a handler in the REPL loop of `bin\sonelle.ps1`, a line in
  `ShowHelp`, and a selftest assertion that the handler exists.
- **Terminal UI:** the launch screen is `Welcome` (a minimal rounded card - brand, live project list,
  one example, footer); the full command list lives in `ShowHelp` (`:help`, on demand) - keep the two
  split (don't move the command dump back into the welcome). Box glyphs are built at runtime via
  `[char]` codepoints (e.g. `0x256D`); never paste a non-ASCII glyph into the source. selftest 8b
  guards the welcome (brand shown, no command dump) and that `:help` still lists every command.
- **New tool:** add `tools\<name>.ps1` (ASCII, `$ErrorActionPreference='Stop'`, `-Hub`-aware if it
  touches hub state), wire it where it is used, and cover it in selftest.
- **New template:** add it to `templates\`, have `new_project.ps1` write it, and assert it
  scaffolds in selftest.
- **Self-develop routing:** the shortcode that makes `<engine-name>: <prompt>` reach `:dev` is derived
  from the engine FOLDER name, lowercased (`$script:selfShort` in `bin\sonelle.ps1`), and special-cased in
  `Route` BEFORE the registry lookup - so it never pollutes `PROJECTS.md`, and renaming the engine folder
  updates it automatically.
- **The app (`bin\sonelle_app.ps1`):** a WinForms window that embeds real `sonelle.ps1` consoles as
  tabs via Win32 `SetParent`. It needs STA (it re-launches itself with `-Sta`). Keep it headlessly
  testable: `-SelfTest` must build the UI + interop and exit 0 WITHOUT showing a window or spawning a
  terminal - selftest section 5c relies on that. UI text stays ASCII; build any glyph at runtime via
  `[char]` (the close mark is `[char]0x00D7`).
- **The glass app (`app\`, default `:app`):** a Python `pywebview`/WebView2 front-end (`app\sonelle_gui.py`)
  rendering `app\ui\` with xterm.js tabs over hidden `pywinpty` PTYs running `bin\sonelle.ps1`. The
  JS<->Python contract is fixed (see `docs\ARCHITECTURE.md`) - if you change a method name on one side,
  change BOTH sides and the selftest 8e markers. Keep `app\sonelle_gui.py` ASCII-clean too (selftest only
  ASCII-gates `.ps1`, but stay consistent). Underscore-prefix any data attribute on the `Api` class
  (pywebview introspects public attrs and will recurse into the WinForms window graph). Glass is in-app
  CSS only - WebView2 can't be transparent. Vendored xterm under `app\ui\vendor\` (refresh via its NOTICE.md;
  versions must pair - core 5.5.0 <-> fit 0.10.0 <-> webgl 0.18.0). xterm runs on the **WebGL** renderer
  (`mountWebgl` in `app.js`), NOT the default DOM renderer: over the transparent glass the DOM renderer
  ghosts/flickers and mashes glyphs, WebGL clears each cell on the GPU (falls back to DOM if no GL context).
  Font is Cascadia Mono first (ligatures overlap in the cell grid); resize fits are debounced (`scheduleFit`).
  The scrollbar gets its own lane via a right gutter on `.pane .xterm` (FitAddon drops the columns it covers)
  so it rides the box edge, not the text. Tabs are labelled with random women's names from `app\ui\names.js`
  (`pickName` in `app.js`), not `sonelle N`. The launcher `bin\sonelle_gui.ps1` owns venv+deps; `.venv\` is gitignored.
  The window brands itself `sonelle.ico` (`icon=` on `webview.start()` sets `Form.Icon`; the TASKBAR
  also needs `SetCurrentProcessExplicitAppUserModelID` at startup, else the button groups under
  `pythonw.exe` and shows its Python feather); it drags from the title bar via pywebview's
  `.pywebview-drag-region` (NOT Electron's
  `-webkit-app-region`, which WebView2 ignores) with an `app.js` mousedown guard over `.nodrag` controls;
  Ctrl+V in the composer saves the clipboard image to temp (`save_paste_image`) and inserts an `@"path"`
  token. selftest 8e guards these. **Yolo (skip permission prompts):** `SONELLE_YOLO=1` makes the app spawn
  the terminal with `-Yolo` -> `claude --permission-mode bypassPermissions`; `:yolo`/`-Yolo`/the config key
  `models.orchestratorPermissionMode` are the other ways in (all funnel through `$orchPerm` in `sonelle.ps1`).
- **Docs:** keep `README.md` + `docs\ARCHITECTURE.md` honest (mechanism vs discipline), and add a
  `CHANGELOG.md` entry.

## Releasing
Bump `CHANGELOG.md` (new top entry), keep README's "What's inside" table current, run selftest,
commit, push. There are no version tags yet - the CHANGELOG is the source of truth.
