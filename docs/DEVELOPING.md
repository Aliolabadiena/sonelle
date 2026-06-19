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
5. Capture lessons. A **generic, cross-project** lesson (no personal data) ships IN the engine via
   `tools\log_lesson.ps1 -Shared` -> `knowledge\` (public, ASCII, indexed by `knowledge\INDEX.md`); a
   **personal / per-project** lesson goes to YOUR gitignored hub `memory\` (default, no `-Shared`). The
   shared `knowledge\` base is curated engine content (like `docs\`/`templates\`), NOT hub state - so it
   does not violate invariant 4; just keep it personal-data-free. The SessionStart hook recalls both.

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
  so it rides the box edge, not the text. Tabs are labelled with a plain incrementing number (1, 2, 3, ...)
  via `nextTabName` (a monotonic `tabSeq`) in `app.js`. The launcher `bin\sonelle_gui.ps1` owns venv+deps; `.venv\` is gitignored.
  The window brands itself `sonelle.ico` (`icon=` on `webview.start()` sets `Form.Icon`; the TASKBAR
  also needs `SetCurrentProcessExplicitAppUserModelID` at startup, else the button groups under
  `pythonw.exe` and shows its Python feather); it drags from the title bar via pywebview's
  `.pywebview-drag-region` (NOT Electron's
  `-webkit-app-region`, which WebView2 ignores) with an `app.js` mousedown guard over `.nodrag` controls;
  Ctrl+V in the composer saves the clipboard image to temp (`save_paste_image`) and inserts an `@"path"`
  token. A **brand loop** (`#brandloop`, the looping mascot gif `app\ui\brandloop.gif`) is anchored to
  `#app` and HOMES to the bottom-right corner (`bottom:8px`, `right:30px` off the scrollbar lane). It is
  a transparent-fill, soft bordered card (`background:transparent` + hairline border + radius) and has
  **physics**: `wireBrandloopDrag` (`app.js`) makes it `pointer-events:auto`/`cursor:grab`; release it
  mid-drag and `throwLoop` flings it with inertia/friction, BOUNCING off the window edges, then 30s
  later `returnLoopHome` drifts it back home on two straight, eased, axis-aligned moves (the CSS
  `right`/`bottom` is only the HOME corner; once moved it's absolute `left`/`top`). At the home corner
  the pane reserves an 88px bottom band (`.pane` `padding-bottom`) and `#bar` a right band
  (`padding-right`) so text + the command bar stop before it. selftest 8e guards these (incl. the physics).
  **Recolour:** the glass palette is tuned to the gif's blue/indigo/purple - edit the `:root` vars +
  gradients in `app.css` and the xterm `THEME` in `app.js` together if you reskin it.
  **Yolo (skip permission prompts):** `SONELLE_YOLO=1` makes the app spawn
  the terminal with `-Yolo` -> `claude --permission-mode bypassPermissions`; `:yolo`/`-Yolo`/the config key
  `models.orchestratorPermissionMode` are the other ways in (all funnel through `$orchPerm` in `sonelle.ps1`).
  **Voice narrator (`app\narrator.py` + `app\tts.py` + `app\narrate_hook.ps1`):** a speaker toggle on
  EACH tab pill (mute per session). Data source is Claude Code HOOKS, not screen-scraping - the app
  publishes `SONELLE_NARRATE_SETTINGS` (only after probing that `claude` supports `--settings`, so a bad
  flag can never break a working app), `sonelle.ps1` attaches `--settings`, and `narrate_hook.ps1` appends
  each event to the per-tab `SONELLE_NARRATE_FILE`; `TabNarrator` tails it and **dual-renders** each event
  into `(display, speak, kind, important)`. Lines are **composed** (`_render`), not enumerated, so they have
  **direction + variety**: `_subject` pulls what she's on (file basename / bash command / grep pattern /
  task) into a `{s}` slot, the `display` is a short tagged report-box line that NAMES it ("reading
  narrator.py <3"), and the `speak` is a FIRST-PERSON TTS line with energy - a varied opener (`_OPEN`) +
  a phrase from a pool + a reaction on a result (`_REACT`), e.g. "all green, 42 passing, nice!". The
  ambient de-dup is keyed on category+subject (`last_key`), so switching files re-announces but a run of
  the SAME file collapses; the assistant name (if set) is spoken as a sign-on on the bookends (start/idle)
  via `_decorate`. `_clean_speech`/`_strip_emoticons` keep emoticons out of speech, and the **reporting
  style** (`_STYLES`: warm/terse/hacker/bubbly) picks the phrase set + opener/reaction energy. **Do NOT write narration into the terminal** - claude's alt-screen TUI repaints over it (that
  was the report bug); it goes to the DOM report box (`reportLine`/`renderReport`, pink `.rline.voice` /
  white `.rline.status`) and audio plays through ONE global serialized queue (`enqueueAudio`/`pumpAudio`).
  **Voice engine** is **Kokoro** (local neural, `app\tts.py` `_synth_kokoro`). The model is **VENDORED in
  the repo** at `app\voice\` (the ~88 MB int8 build + voice pack - `_kokoro_files`, NO download) so the
  voice ships with sonelle; only the `kokoro-onnx` RUNTIME installs best-effort from
  `app\requirements-voice.txt` (never fatal), with `edge-tts` then SAPI as fallbacks. Default `af_heart`
  at 0.95 speed. Keep the JS<->Python contract in sync on BOTH sides AND in selftest 8e/8f
  (`set_narration`, `__narrate(tabId, display, kind, mime, b64)`); keep `app\narrate_hook.ps1` pure ASCII
  like every `.ps1`, and the `.py` modules ASCII-clean too. edge-tts is pinned `>=7.2.8` (older pins 403).
- **The reporter + settings panel (`app\`):** `#brandloop` is a WRAPPER - a report box (`#loop-report`)
  ABOVE a `.gifwrap` (gif + control row: **report-arrow . padlock . mute . session label**). The
  **report-arrow** (`.lbtn.arrow` -> `toggleReport`) opens/closes the report (so does **V**, when not
  typing in an input); the **padlock** ONLY pins the gif (no bounce / no drift) and has NOTHING to do with
  the report - the report shows on `.brandloop.reportopen` only (the old `.brandloop.locked .report` CSS
  coupling was removed in v1.34). Per-tab gif state lives in `entry.gif` (`applyGifState` on tab switch). Narration goes to the report box (NOT the
  terminal) and audio plays through one global serialized queue. (A desktop pop-out overlay was tried and
  dropped on purpose - the reporter stays in-app; don't re-add it.) The **settings gear** (before the
  `_ O X` controls) opens `#settings`: 20 palettes (`app\ui\palettes.js`, `applyPalette` rewrites the
  `:root` vars + every xterm theme, and `activeTheme` so NEW tabs adopt it), assistant name (DISPLAY only -
  never the engine self-short), upload-your-own mascot (`upload_mascot` -> `%LOCALAPPDATA%\sonelle`, never
  the repo), reporting style, voices instructions (display only), and the **model split**: the
  **orchestrator** model + effort (`models.orchestrator`/`orchestratorEffort` -> `--model`/`--effort`) and
  a separate **code-writer** model (`models.codeWriter`, `inherit`/empty = same) that `bin\sonelle.ps1`
  exports as `CLAUDE_CODE_SUBAGENT_MODEL` so claude's file-editing SUBAGENTS run on their own model.
  `get_settings`/`save_settings` persist to `sonelle.config.json`. **These are LIVE:** `RefreshOrch` in
  `bin\sonelle.ps1` re-reads the model block right before each `claude` launch (Route + DevSelf), so a
  panel change applies to the NEXT prompt with no tab restart - the config file is the channel (and
  `$env:SONELLE_CONFIG` can repoint that file; the resolver in `tools\_registry.ps1` honors it, which is
  also how selftest 5d stays hermetic). Permission mode is NOT re-read live (it has `-Yolo`/`:yolo`
  overrides). Guarded by selftest 5d (behavioral: model/effort/code-writer + SONELLE_CONFIG), 8e
  (reporter), 8f (narrator), 8i (settings); keep the JS<->Python contract synced on both sides.
- **Guard hook + slash commands + inherent altitude (v1.36):** the engine and every scaffolded project
  ship a **PreToolUse guard** (`.claude\hooks\pretooluse_guard.ps1`, wired in `.claude\settings.json` for
  `Write|Edit|Bash`). It reads claude's UTF-8 payload on stdin (`OpenStandardInput` as UTF-8 - PS 5.1's
  `[Console]::In` uses the console code page and would corrupt non-ASCII), and on a violation EXITS 2 to
  BLOCK the call (stderr goes back to claude); any parse/read problem EXITS 0 (a guard must never break a
  session). This is the only guardrail left in a `bypassPermissions` session. The ENGINE guard enforces
  the house rule (no non-ASCII written to a `.ps1`) and invariant #4 (no `new_project`, no plain
  `log_lesson` - only `-Shared` -> `knowledge\`; no `*_TODO.txt`/`*_run_STATUS.md`/`memory\` at the engine
  root) plus blocks force-push; the PROJECT template guard blocks force-push and is a stub to add your own
  rules. **Slash commands** (`.claude\commands\`: `/selftest /heal /ship /ritual`) codify the rituals -
  engine versions drive `selftest`/`doctor`/the commit gate, scaffolded versions drive `sonelle.check.ps1`
  + the project's TODO/ledger. **Inherent operating policy (v1.36, broadened v1.38):** `bin\sonelle.ps1`
  appends a one-line policy (`$operatingPolicy`) to EVERY project/engine session via `--append-system-prompt`
  so claude PROACTIVELY picks the workflow from the task alone (the user states the goal, not the tool):
  delegate breadth-first exploration to subagents on a hard / multi-file task and do small ones directly;
  VERIFY after a change by running the right check (selftest or `sonelle.check.ps1`); HEAL on failure; run the
  end-of-task ritual when done - while scaling down so a one-liner gets no ceremony. The `general:` lane gets
  a minimal `$generalDirective` instead (no project state to maintain). DevSelf also moves its engine framing
  into `--append-system-prompt` (the
  system prompt survives compaction better than a user-turn seed). Both gate on a cached
  `ClaudeSupports '--append-system-prompt'` probe and fall back to folding the text into the prompt on an
  older `claude`. Guarded by selftest 8h (guard exists + behavioral block/allow incl. the non-ASCII case +
  commands + wiring) and 5d (routing attaches `--append-system-prompt`).
- **Onboarding + :adopt + general (v1.37):** the glass app runs each tab in `-Bare`, which now prints a
  tiny no-claude primer (`BareIntro`: `:new` / `:adopt` / `<short>: <prompt>` / connect claude); bare
  `help`/`help:`/`?` shows `ShowHelp` and never routes. **`:adopt <path> [as <short>]`** (`Adopt` in
  `bin\sonelle.ps1`) scaffolds the skeleton over an EXISTING repo then `Route`s an AI conversion prompt
  into it - non-destructive (existing `CLAUDE.md`/`sonelle.check.ps1`/`.claude\` are copied to
  `*.pre-sonelle.bak` first). **`general: <prompt>`** is intercepted in `Route` -> `General`, which runs
  claude in `%TEMP%\sonelle_general` (neutral - no `CLAUDE.md` up the tree) with NO hub state / registry
  row / memory; `general` is a reserved shortcode (new_project refuses it). Guarded by selftest 5f
  (behavioral) + 8b.
- **Docs:** keep `README.md` + `docs\ARCHITECTURE.md` honest (mechanism vs discipline), and add a
  `CHANGELOG.md` entry.

## Releasing
Bump `CHANGELOG.md` (new top entry), keep README's "What's inside" table current, run selftest,
commit, push. There are no version tags yet - the CHANGELOG is the source of truth.
