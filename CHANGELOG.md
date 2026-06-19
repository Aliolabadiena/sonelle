# Changelog

## v1.35 — 2026-06-19 (model split + live settings: thinky orchestrator, separate code-writer)
- **Separate model for the code-writer (subagents) vs the orchestrator.** The settings panel now has an
  **orchestrator model + effort** (the session you talk to -> claude's `--model`/`--effort`) AND a
  **code-writer model** (`inherit` = same). When set, `bin\sonelle.ps1` exports it as
  `CLAUDE_CODE_SUBAGENT_MODEL`, so claude's file-editing subagents run on their own model - e.g. a thinky
  Opus orchestrator with an Opus (or faster Sonnet) code-writer. Persisted under `models.codeWriter`. A
  `best` option (Fable 5 if available, else Opus) was added to both pickers.
- **Settings are now LIVE - no tab restart.** Before, model/effort were read once when a tab launched, so
  a change in the panel did nothing until you opened a new terminal (this confused people). `RefreshOrch`
  now re-reads the model block from config right before each `claude` launch (Route + DevSelf), so a panel
  change applies to your NEXT prompt in any open tab. (A claude session already mid-run keeps what it
  launched with - that's Claude Code's own in-session effort control, not sonelle's to change.)
- **`$env:SONELLE_CONFIG` overrides the config path.** The resolver (`tools\_registry.ps1`) honors it -
  handy for power users, and it lets selftest 5d run **hermetically** instead of depending on the dev's
  real engine-root config (which made the model/effort assertions fragile).
- **selftest:** 5d is now hermetic and behavioral - it proves model/effort come from config (live) and
  that the code-writer reaches claude as `CLAUDE_CODE_SUBAGENT_MODEL`; 8i covers the new code-writer
  field; new checks assert `RefreshOrch` re-reads per prompt and the resolver honors `SONELLE_CONFIG`.
  All green.

## v1.34 — 2026-06-19 (reporter UX: an arrow opens the report; the lock just pins)
- **The report now opens with an arrow on the gif - the padlock only pins.** Before, the padlock did
  double duty (pin the gif AND reveal the report), which was confusing. Now the gif's control row leads
  with a dedicated **report-arrow** (`toggleReport`); the **padlock** is purely "lock in place" (no
  bounce / no drift home) and has nothing to do with the report box. The **V** key still toggles the
  report too. The arrow points up to open (the box expands upward) and flips down when open. CSS
  decoupled: `.brandloop.locked .report` is gone; the report shows on `.reportopen` only.
- **selftest:** 8e updated - the control row asserts the report-arrow, the JS asserts the arrow wires
  `toggleReport`, and the CSS asserts the lock no longer opens the report (decoupling guarded). All green.

## v1.33 — 2026-06-19 (the reporter + customization: sonelle gets a face and a settings panel)
- **Narration moved OUT of the terminal into a report box (the report bug fixed).** sonelle used to
  type her humanised lines straight into the xterm, but claude's TUI runs on the alternate screen and
  repaints over them, so they vanished. Now each line lands in a **DOM report box under the mascot gif**
  (pink for her voice, soft white for the play-by-play). The old terminal-injection machinery
  (`typeNarration`/`writeOrHold`/`runNarrQueue`/holdback) is gone.
- **The mascot is now a reporter you can lock, open, and mute.** `#brandloop` became a wrapper: the gif +
  a control row (**padlock . mute . session label**) + a report box that sits ABOVE the gif (so the gif
  stays in its home corner and the box expands upward). The padlock pins the gif (no bounce / no drift
  home) and opens the report; pressing **V** (when not typing) opens/closes the report WITHOUT locking;
  mute mirrors that tab's voice toggle; the session label is low-contrast "moody" text. **Per-tab gif
  state** (position, lock, report-open, log) is saved and restored as you switch tabs, and the report box
  uses the same scrollbar styling as the terminal.
- **Dual-rendering narrator + queued speech.** Each event now yields a **display** line (short, with a
  cute ASCII tag like `:)` / `<3`) for the box and a **speak** line (fuller, natural, third person, no
  emoticons) for TTS; `_clean_speech` strips emoticons/kaomoji so they're never vocalized. All audio
  plays through **one global serialized queue** so two sessions never talk over each other, and with 2+
  active reporters the spoken opener announces "session N, ...".
- **A customization settings panel (the titlebar gear).** A new gear - placed BEFORE the `_ O X`
  window controls - opens a glass panel: **20 colour palettes** (live preview, applied to the CSS vars +
  every xterm theme), an **assistant name** (display-only - never touches the engine self-dev shortcode),
  **upload your own mascot** (gif/photo, staged to `%LOCALAPPDATA%\sonelle`, never the repo), **4
  reporting styles** (warm / terse / hacker / bubbly), **other-voices instructions** (display only), and
  the **claude model + effort** (written to `models.*`, picked up by new terminals). Saved to
  `sonelle.config.json`; palette/name also cached in `localStorage` so they apply instantly on launch.
- **selftest:** 8e gains the reporter-wrapper / control-row / per-tab-state / report-box (lock-or-V)
  checks; 8f asserts the dual-rendering split, the 4 styles, emoticon stripping, the global audio queue,
  and that the pop-out/overlay is fully removed; new **8i** (gear-before-controls, >=20 palettes, the full
  panel, mascot staged outside the repo, name display-only, model/effort under `models.*`). All green.

## v1.32 — 2026-06-19 (engine hardening: honest heal, real behavioral tests, less drift)
- **No more green-placeholder lie (H1+H2).** A brand-new project's `sonelle.check.ps1` is no longer a
  hollow `exit 0`; `new_project.ps1` now scaffolds an **auto-detector** that finds the project's real
  test command (`npm test` / `pytest` / `dotnet test` / `cargo test` / `go test`) and runs it - and
  when it finds none it exits **2 = NOT configured** instead of faking health. `doctor.ps1` understands
  exit 2 and reports `[warn] ... NOT configured (placeholder) - add real checks` instead of counting it
  as a PASS. So "HEALTHY" now means something was actually checked. selftest sections 2 + 4 cover both.
- **Recall is now mechanism, not a nag (H3).** The per-project SessionStart hook no longer just prints
  "remember to read your memory" - it **surfaces the memory index straight into context** (first 40
  lines of `memory\MEMORY.md`), probing the `SONELLE_MEMORY` env var and the known relative spots, and
  falls back to the reminder only when no index is found. selftest section 2 asserts the scaffolded
  hook actually reads `MEMORY.md`.
- **The terminal takes `-Hub` now (Q4).** `bin\sonelle.ps1` gained a `-Hub <path>` parameter that wins
  over `sonelle.config.json`, mirroring every other tool and making the terminal testable in isolation
  (the prerequisite for the new behavioral routing test). Caught a real bug doing it: PowerShell
  variable names are case-insensitive, so the `$Hub` param and the working `$hub` variable were the
  same slot - `$hub = $root` silently clobbered the override. Fixed by capturing the param first.
  selftest section 9b drives `-Demo -Hub <temphub>` and asserts the welcome lists the override hub's
  projects (a behavioral check, not just a grep).
- **The terminal now has a real behavioral test (T1+T4).** selftest section 5d puts a fake `claude` on
  PATH that records its argv + working directory, drives the terminal over stdin with `-Hub`, and
  asserts it handed claude `--model opus --effort xhigh`, `cd`'d into the project's code path, and that
  `-Yolo` adds `--permission-mode bypassPermissions` while a plain run does not. This is the first test
  that exercises routing end-to-end instead of grepping source - it would have caught the Q4 bug on its
  own. Leaking session env (`SONELLE_YOLO`, `SONELLE_NARRATE_SETTINGS`) is neutralized so it's deterministic.
- **One config resolver, not three (Q3).** `bin\sonelle.ps1` and `bin\sonelle_team.ps1` no longer
  hand-parse `sonelle.config.json` - both now call the canonical `Get-SonelleConfig`, which was extended
  to surface the raw `models` block alongside the hub/memory it already resolved. Four parsers collapse
  toward one, so a config-format change can't silently desync the terminal from the lanes. selftest
  section 9 asserts both callers use the resolver and that no inline JSON parse remains.
- **The two registry parsers can no longer drift (Q1+Q2).** `_registry.ps1` warned against ad-hoc
  registry parsing, but `app\sonelle_gui.py` had its own Python copy. The Python parse is now a single
  `parse_projects(path)` function, and selftest section 9a runs both the PowerShell and Python parsers
  over the same registry and asserts they return identical results - so a change to one that diverges
  fails the build. A guard meta-test (Q2) greps the repo for the registry-row regex and refuses any
  third parser outside the two sanctioned files. Fixed a latent divergence in passing: the Python
  parser would have listed a lower-cased `shortcode` header row as a project; it now skips it like the
  PowerShell parser does.
- **`new_project` is transactional now (R1).** The scaffold writes a TODO, ledger, project CLAUDE.md,
  memory file, hooks, a health check, a memory-index line and a registry row - if any step failed
  partway it used to leave orphans (e.g. a memory-index line with no registry row). It now tracks every
  file/dir it creates and snapshots the two append-targets, and on ANY failure it rolls everything back:
  either the whole project lands or nothing does. selftest section 5e forces a mid-scaffold failure and
  asserts no TODO/ledger/registry-row/index-line is left behind.
- **`doctor` now catches orphaned state (R2).** `check_pointers` already verifies registry -> files;
  doctor now does the reverse, flagging `*_TODO.txt` / `_*_run_STATUS.md` / `memory\project_*.md` whose
  `<short>` has no registry row (a leftover from a deleted project), and registry rows missing their
  TODO state file. These are non-fatal warnings (you may be mid-cleanup) so a real all-clear still
  exits 0. selftest section 4 plants an orphan TODO and asserts doctor warns about it without failing.
- **Lanes can be checked for overlap before they collide (R3).** Parallel lanes coordinate purely by an
  honor-system `owns:` declaration + disjoint file ownership - the riskiest feature when a project has no
  git merge safety. `sonelle_team.ps1 <project> -Verify` now parses every lane's `owns:` line, normalizes
  the paths/globs, and reports any two lanes that claim the same file or an ancestor directory of it,
  exiting 1 so it can gate a launch. selftest section 5b asserts it flags an overlap and passes when
  ownership is disjoint.
- **The glass app stops debugging blind (R4).** `app\sonelle_gui.py` swallowed ~20 exceptions silently.
  A tiny `_dbg(msg)` (gated on `SONELLE_DEBUG`, never itself raises) now leaves a trail at the
  non-narrator swallow sites - PTY read/write/resize/kill, `run_js`, config + registry reads, the window
  controls and shutdown - so a harder unattended session is diagnosable instead of mute. The behaviour
  is unchanged (still swallows); it just records why. selftest section 8e asserts the logger exists and
  is used. (The narrator's own except blocks are left untouched.)
- **Two new test layers - and a real bug they found (T2+T3).** A golden snapshot (T2) pins the exact
  template set and the full scaffold manifest, so an accidental template change that would alter every
  new project trips the build. A registry-parser fuzz (T3) feeds `Get-SonelleProjects` malformed rows
  (missing cells, empty/uppercase shorts, pipes in paths, stray CR) and asserts it neither throws nor
  returns junk. T3 immediately caught a real bug: the parser's `\s*` matched newlines, so a malformed
  row with no closing pipe "borrowed" the next line and became a bogus project (and silently diverged
  from the line-based Python parser). Fixed to `[ \t]*` so each match stays on its own line.
- **Faster, lighter app (P1-P3).** `:app` no longer spawns python to probe deps on every launch - it
  writes a `.venv\.deps_ok` sentinel and re-probes only when it's missing or older than
  `requirements.txt` (P1). xterm scrollback is now a clamped, `localStorage`-configurable constant
  instead of a hard-coded 5000 per tab (P2). The PTY base64 decode is a single `Uint8Array.from(atob...)`
  pass instead of a per-character loop (P3). selftest covers all three.
- **A build stamp (A4).** The terminal now reads the top version header from `CHANGELOG.md` (the source
  of truth - there are no version tags) and shows it in the welcome footer and `:help`, so any session
  or log records exactly which engine build it ran against. selftest asserts the welcome carries it.
- **Honest framing (H4).** With heal and recall now real mechanism (H1-H3), `CLAUDE.md` and `README.md`
  were tightened to say so: HEAL now lists unconfigured + orphan detection and the real default check;
  SELF-IMPROVE says recall is surfaced into context, not merely reminded. No more overselling
  discipline as mechanism.

## v1.31 — 2026-06-19 (glass app: a real voice in the repo, in the terminal, per tab; a gif with physics; a shared knowledge base)
- **A real, human voice - VENDORED in the repo.** The narrator's primary engine is now **Kokoro**, a
  modern neural voice that runs LOCALLY (ONNX): free, no API key, fully offline. The voice MODEL ships
  IN the engine at `app\voice\` (the ~88 MB int8 build + voice pack, small enough to live in plain git)
  - **no download**, it's there on clone. Only the small `kokoro-onnx` runtime installs via pip
  (best-effort, `app\requirements-voice.txt`). `edge-tts` (cloud neural) then Windows **SAPI** stay on
  as automatic fallbacks, so she always talks. Default voice `af_heart` at 0.95 speed.
- **She texts you - in the terminal itself.** Narration is no longer a floating banner; it's typed
  straight into the terminal, word-by-word, like she's messaging you live. Two voices on screen:
  **pink** (a `> ` caret, the bypass-permissions magenta) is sonelle talking TO you - openers,
  check-ins, milestones, her answers; **soft white** is the quiet play-by-play of what she's doing.
  The wording is now warm **first person** ("ok, on it.", "running the tests...", "all green - 1666
  passing!") instead of robotic third person. Her lines are serialized against claude's own output
  (a brief hold-back) so the two never interleave mid-line.
- **Voice is now per-tab.** Each tab pill carries its own speaker toggle, so you mute the boring
  research sessions and keep the important ones talking. (The single titlebar toggle is gone.)
- **The brand loop has physics.** The mascot gif is a transparent-fill, soft bordered card you can
  drag anywhere; release it mid-motion and it FLINGS and BOUNCES off the window edges until friction
  stops it, then 30s later it drifts back home on two straight, eased, axis-aligned moves.
- **Recoloured to the gif.** The whole glass panel shifted from lilac/magenta to the brand loop's
  **blue / indigo / purple** (sampled straight from the gif), incl. the xterm theme + scrollbar.
- **A shared knowledge base (`knowledge\`).** Generic, cross-project lessons now ship IN the engine
  (public, ASCII, zero personal data) so a fresh clone already knows them - distinct from personal /
  per-project memory, which stays in the gitignored hub `memory\`. `tools\log_lesson.ps1 -Shared`
  captures a generic lesson here (linked from `knowledge\INDEX.md`); the SessionStart hook recalls it.
- selftest `8e`/`8f`/`8g` extended for all of it: the bundled Kokoro model (no download), the inline
  pink/white narration, the per-tab speaker, the transparent gif + throw/bounce/drift-home, the
  `voice`/`status` kind on `window.__narrate`, and the shared knowledge base + `-Shared` capture.

## v1.30 — 2026-06-19 (glass app: sonelle gets a voice)
- **A per-tab voice narrator: when on, sonelle speaks her progress out loud in third person, and the
  reports show in bold pink.** New titlebar speaker toggle (per active tab). When a tab's voice is on,
  she narrates the important beats - *"sonelle is reading the code... sonelle is editing the scripts...
  she kicks off the test suite... tests came back green - 1666 passing... ouch, she ran into 7 problems...
  she's pushing the commit up... she's all done, and idle now."* - rate-limited so it's the headline
  beats, not every keystroke. Each line also renders as a **bold-pink** overlay at the top of the pane
  (the same magenta as claude's "bypass permissions on" badge) while her normal output stays white.
  - **Robust data source = Claude Code hooks, not screen-scraping.** The app launches `claude` with
    `--settings <generated file>` so its `PreToolUse`/`PostToolUse`/`Notification`/`Stop`/
    `UserPromptSubmit` events append (via `app\narrate_hook.ps1`) to a per-tab JSONL file. A per-tab
    Python narrator (`app\narrator.py`) tails that file, maps events to humanised lines, and (voice on)
    speaks them. **Safety:** the app first probes that `claude` actually supports `--settings`; if not,
    the flag is never passed, so an older/absent claude can't be broken - narration just stays dormant.
  - **TTS** (`app\tts.py`): `edge-tts` neural voices (free, no API key; default `en-US-AriaNeural`,
    set `narrator.voice/rate/pitch/engine` in `sonelle.config.json`) with a built-in Windows **SAPI**
    offline fallback, so she still talks with no connection. Audio plays in the WebView2 page.
  - **Off by default & escapable:** voice is per-tab and starts off; set `narrator.enabled:false` (or
    `SONELLE_NARRATE=0`) to disable the whole feature. `edge-tts>=7.2.8` (7.0.0 pinned 403 on the
    Microsoft handshake). selftest gains a `8f. voice narrator` section.
- **Three bug fixes from a full app/brain audit:** (1) the GUI's output-pusher thread could crash on a
  poison-pill drained mid-batch during shutdown - now it finishes the batch and stops cleanly; (2)
  Ctrl+C in the composer with text selected interrupted the agent instead of copying - it now respects
  an input-box selection (which `window.getSelection()` doesn't see) and only sends the interrupt when
  nothing is selected; (3) the `+` button advertised "Ctrl+T" but no handler existed - Ctrl+T now opens
  a new terminal.

## v1.29 — 2026-06-19 (glass app: the brand loop gets its own clean corner)
- **The mascot gif now sits in a clean empty corner with nothing drawn under it, and clears the
  scrollbar.** Two refinements over v1.28: (1) the whole command-bar **panel** now stops before the
  gif instead of just its content - the right band moved from `.cmdbar` `padding-right` to `#bar`
  `padding-right` (`176px -> 190px`), so the glass cmdbar's right edge (input + send button) parks to
  the LEFT of the gif and the panel no longer runs under the gif's corner; `.cmdbar` padding is back to
  normal (`0 16px`). (2) The gif is pulled IN off the right edge (`right:14px -> 30px`) so its right
  edge stops short of the terminal **scrollbar** lane (the scrollbar rides ~15..22px in) - it no longer
  sits over the scroll block. Net effect: the gif's foot sits over the bare page background beside the
  shrunk bar and its body over the pane's empty bottom band - a clean framed corner with no panel,
  text, or scrollbar beneath it. The gif size, opacity, and timing are unchanged. selftest 8e now
  asserts the gif is pulled off the scrollbar lane (`.brandloop` `right >= 24px`) and that the panel
  reserve is on `#bar` (`padding-right >= 120px`). Verified with a headless render.

## v1.28 — 2026-06-19 (glass app: the composer stops before the brand loop, horizontally too)
- **The command bar no longer runs under the mascot gif sideways.** v1.26 stopped *terminal* text from
  running under the brand loop by reserving a bottom band; but the **composer** (the input you type in +
  the send button) still slid right, underneath the gif's corner. Now `.cmdbar` reserves a matching
  RIGHT band (`padding-right: 8px -> 176px`, the width of the gif at `right:14px`) - the horizontal twin
  of the pane's 88px bottom band. The send button parks to the LEFT of the gif and the input (`flex:1`)
  shrinks so typed text stops *before* the gif instead of sliding under it. The gif itself is unchanged
  (same size, position, opacity). selftest 8e adds an assertion that the command bar reserves that right
  band (`.cmdbar` `padding-right >= 120px`).

## v1.27 — 2026-06-19 (glass app: tabs are just numbered 1, 2, 3)
- **Terminal tabs are now labelled with a plain number instead of a random woman's name.** The
  `app\ui\names.js` pool (a few hundred names) and the `pickName()` picker are removed; `app.js` now
  names each tab with a monotonic counter via `nextTabName()` (`1`, `2`, `3`, ... in the order opened).
  The counter only climbs, so closing a tab never renumbers the others. `index.html` no longer loads
  `names.js`, and the file is deleted. selftest 8e drops the name-pool checks and instead asserts the
  numbered naming (`nextTabName` / `tabSeq`, no `pickName`/`SONELLE_NAMES`) and that `names.js` is gone.

## v1.26 — 2026-06-19 (glass app: the brand loop drops into the bar, text stops above it)
- **The mascot brand loop now sits LOW over the send-button corner, and terminal text stops above it
  instead of running under it.** The gif was lifted clear of the composer (v1.25); now it is dropped
  back DOWN into the command bar (`bottom:72px -> 8px`) so it overlays the send-button corner, as
  requested. To keep text off it, the terminal grid now genuinely *stops before* the gif rather than
  being hidden behind the opaque block: the pane reserves an 88px bottom band (`.pane` `padding-bottom:
  12px -> 88px`), and because `FitAddon` subtracts that padding when it sizes the grid, the bottom rows
  end ABOVE the gif's top - no text is ever drawn (and lost) behind it. The gif stays OPAQUE (so nothing
  shows through where it sits over the bar) and decorative (`pointer-events:none`), so clicks still pass
  THROUGH it to the send button beneath - send keeps working even while the gif covers it (Enter sends
  too). selftest 8e now also asserts the gif is low (`bottom <= 24px`) and the pane reserves a bottom
  band (`padding-bottom >= 40px`). Verified with a headless render.

## v1.25 — 2026-06-19 (glass app: the brand loop is opaque, bigger, and slower)
- **The mascot brand loop no longer lets terminal text show through it, and it's bigger and calmer.**
  The gif has a transparent top (~20% of its pixels), so over the glass terminal you could see text
  *through* it - it looked like the text was running behind the figure. It is now OPAQUE: a solid
  `#07091f` backing (the gif's own opaque floor colour, so the fill is seamless) sits behind it, so
  terminal text can never show through - the block reads as a clean wall the text stops at instead of
  running under it. It is **20% bigger** (`height:112px -> 134px`) and **lifted clear of the composer**
  (`bottom:4px -> 72px`, above the `8+52+8 = 68px` the pad + bar + gap occupy) so the now-opaque block
  never covers the send button. The gif file itself is **re-timed to half speed** (each frame `100ms
  -> 200ms`, an 1.8s loop now 3.6s) via a lossless binary patch of its frame delays - the pixels and
  palette are untouched, only the timing changed. selftest 8e now also asserts the `.brandloop` opaque
  backing. The gif stays vendored in the repo (`app\ui\brandloop.gif`).

## v1.24 — 2026-06-19 (glass app: the brand loop is now the mascot gif, perched on the input bar)
- **The bottom-right brand loop is now the real animated mascot gif, not the CSS sound-wave.** v1.23's
  coral wave is replaced by `app\ui\brandloop.gif` (a transparent-background pixel-art loop), and it no
  longer just floats in the terminal corner - it now STRADDLES the seam between the composer and the
  terminal: anchored to `#app` (the shared parent of `#stack` + `#bar`) with its vertical centre on the
  top edge of the command bar (`height:112px; bottom:4px` over the 52px bar + 8px pad), so the lower
  half overlaps the input bar you type into and the upper half rises into the terminal - the figure
  looks perched on the bar. Still decorative only (`aria-hidden` + `pointer-events:none`, lifted above
  both panels by `z-index`), so it never blocks a click or text selection (the send button included)
  beneath it; the gif self-animates (no CSS keyframes). selftest 8e now asserts the `#brandloop` `<img>`,
  its `src="brandloop.gif"`, the shipped gif file, the `.brandloop` rule, and `pointer-events:none`.
  Verified with a headless render: the gif loads with a transparent background and sits across the seam,
  lower half on the input bar, upper half in the terminal.

## v1.23 — 2026-06-19 (glass app: an always-on brand loop in the bottom-right)
- **There's now a living sonelle mark in the bottom-right corner.** A small coral sound-wave sits in
  the bottom-right of the terminal area and gently loops all the time - it breathes (a soft
  opacity + 1px bob) while the wave itself flows. Quiet brand presence, on whenever the app is open.
  It's pure CSS (no gif asset to ship or fail to load), anchored to `#stack` so it always rides just
  above the composer regardless of the footer height, and decorative only: `aria-hidden` +
  `pointer-events:none` so it never intercepts a click or text selection in the terminal beneath it.
  Honors `prefers-reduced-motion` (holds still, stays visible). selftest 8e asserts the element, its
  svg wave, the `.brandloop` rule, `pointer-events:none`, and the `@keyframes`/`animation` wiring.
  Verified with a headless render: the wave shows in the corner, above the input.

## v1.22 — 2026-06-19 (glass app: real app icon, softer glass, scrollbar clears the text)
- **The brand mark is now the real app icon, not a gradient cube.** Both the titlebar mark and the
  welcome-screen mark were plain lilac gradient squares; they now render the actual sonelle sound-wave
  icon (inline SVG, kept in sync with `assets\icon\sonelle.svg`) - crisp at any size, no asset-path or
  HTTP-server concerns. selftest 8e asserts the brand mark embeds the icon (and no longer a gradient cube).
- **Glass dialled back ~20% (less "AI").** Every tunable glass effect was softened so the UI reads calmer:
  backdrop blur/saturate, drop+inset shadows, the logo glow, the body "bloom" radial layers, and the
  hairline border alphas all stepped down ~0.8x. Layout, radius, font, padding, and text colours are
  untouched, and the panels/titlebar stay clearly separated from the background.
- **Scrollbar clears the last glyph with a real gap.** The terminal's right gutter widened
  (`.pane .xterm{ padding-right }` 14->18px, pane right padding 6->4px) and the thumb is now a thin pill
  with a transparent border + `background-clip:content-box`, so it sits in its own lane with a few px of
  air to the right of the text - verified with an overflow render. (FitAddon subtracts the element padding
  when it sizes columns, which is the only real lever here.)
- **Initial-prompt grey background: left as-is, by design.** That grey block is drawn by **claude itself**
  (a 256/truecolor background SGR in its prompt box) only once claude is running - a raw-byte capture of
  `sonelle.ps1 -Bare` confirmed nothing emits it before then, so neither `app.css` nor the xterm `THEME`
  can restyle it. The only lever is rewriting that SGR out of the PTY stream, which is too fragile to
  ship: the exact colour is a claude-version/theme detail (silent regression on update), a broad strip
  would wreck legitimate claude backgrounds (diffs, selections, syntax), and a selftest could only check a
  hardcoded sample, not live behaviour. Not worth the risk for a cosmetic tint.

## v1.21 — 2026-06-19 (glass app: scrollbar off the text, human tab names)
- **Scrollbar no longer overlaps the terminal.** It used to ride the right inner edge of the xterm grid,
  painting over the last column of glyphs. The pane now pulls its right padding in and gives the terminal
  its own right gutter (`.pane .xterm{ padding-right }`) - FitAddon subtracts that padding when it sizes
  the columns, so the text stops short and the scrollbar sits in a clean lane at the box edge.
- **Tabs read like people, not `sonelle 1 / sonelle 2`.** Each tab is now labelled with a random woman's
  name (Megan, Sakura, Sidney...) drawn from a few-hundred-strong, culturally diverse pool in
  `app\ui\names.js`. `pickName()` avoids names already on an open tab; a project-named tab keeps its
  project name. selftest 8e checks the pool, the picker, the gutter CSS, and the new script include.

## v1.20 — 2026-06-18 (glass app: crisp WebGL terminal + a yolo switch to skip permission prompts)
- **No more flicker / mashed-together text.** The glass terminal rendered with xterm.js's default DOM
  renderer over a *transparent* background, where a "space" cell never paints over the glyph beneath it -
  so old characters bled through and words ran together (`labai daug` -> `labaicdaug`), and the whole pane
  fluttered on resize. It now uses the **WebGL** renderer (`@xterm/addon-webgl`, vendored), which clears
  every cell each frame on the GPU; it falls back to the DOM renderer if no GL context is available. Also:
  the font is **Cascadia Mono** first (ligature fonts overlap in xterm's one-glyph-per-cell grid), and
  resize fits are debounced to one per frame (`scheduleFit`) so dragging the window no longer churns.
- **`:yolo` - stop the permission prompts.** `claude` asks before risky actions by default. New ways to
  skip them, all routed through `claude --permission-mode bypassPermissions`:
  - `SONELLE_YOLO=1` env var -> the glass app launches each terminal with `-Yolo` (persistent, opt-in);
  - `:yolo` (or `:yolo on|off`) toggles it live inside any terminal;
  - `sonelle.ps1 -Yolo` flag, or `sonelle.config.json` -> `models.orchestratorPermissionMode`.
  Opt-in by design (the public engine never bypasses by default). selftest 8a/8e assert the flag, the
  toggle, the env-var wiring, the vendored addon, and that the front-end mounts WebGL + debounces fits.

## v1.19 — 2026-06-18 (glass app: fix the Python icon still showing in the taskbar)
- **The taskbar finally shows sonelle, not Python.** v1.18 set the window's `Form.Icon` via `icon=` on
  `webview.start()`, but the **taskbar** button kept showing `pythonw.exe`'s Python-feather icon. The
  window is frameless, so `Form.Icon` only ever brands the (hidden) title bar; the taskbar groups buttons
  by **AppUserModelID**, and with none set the button stayed grouped under the host `pythonw.exe` and used
  its icon. `sonelle_gui.py` now calls `SetCurrentProcessExplicitAppUserModelID("sonelle.glass.app")` at
  startup (before any window exists; Windows-only, swallowed elsewhere), claiming its own taskbar identity
  so the button adopts the sonelle mark. selftest 8e asserts the call is present.

## v1.18 — 2026-06-18 (glass app: sonelle icon, draggable window, Ctrl+V image paste)
- **sonelle icon, not the Python feather.** The running glass app now shows the **sonelle** icon in the
  window/taskbar. pywebview's winforms backend, given no icon, extracts one from `sys.executable`
  (`pythonw.exe`) - so the app branded itself as Python. `sonelle_gui.py` now passes
  `icon=assets\icon\sonelle.ico` to `webview.start()`, matching the launcher `.lnk` and the classic
  WinForms host. Falls back gracefully if the .ico is missing.
- **The window moves now.** The frameless title bar was styled with `-webkit-app-region:drag`, which is
  an Electron-only feature that **WebView2 ignores** - so the window was stuck. It now uses pywebview's
  `.pywebview-drag-region` class on `#titlebar`, with an `app.js` mousedown guard that cancels the drag
  over `.nodrag` controls so buttons/tabs/the input still click normally.
- **Ctrl+V pastes images into claude's context.** Paste a clipboard image into the composer and it is
  saved to a temp file (new `save_paste_image` API; written to the OS temp dir, never the repo) and an
  `@"<path>"` token is inserted. Sending the routed prompt hands that path to claude exactly like
  `:attach` / inline `@path` already do, so the image enters context.
- selftest 8e now asserts the icon is wired, the title bar is a drag region with the guard, and both
  sides of `save_paste_image` exist.

## v1.17 — 2026-06-18 (glass app: composer is the only input, terminal is read-only)
- Reversed v1.16: the bottom composer is back AND is now the ONLY place you type. The terminal pane
  is output-only (`xterm` `disableStdin: true`) - you can't type into the window, which is what made
  it feel ambiguous. You type in the composer; it forwards to the hidden PowerShell/claude.
- The composer forwards the keys an interactive TUI needs so claude stays fully usable: Enter sends the
  line; Up/Down, Tab, Esc pass through; Ctrl+C sends an interrupt (unless text is selected, so copy still
  works). Clicking the read-only terminal refocuses the composer (unless you selected text to copy).
- The composer auto-focuses on open; minimal placeholder ("ask a project to do something").
- Verified live (real window: composer present, typing ":help" in it drove the hidden terminal and the
  output rendered, composer cleared, stderr clean); selftest ALL PASS.

## v1.16 — 2026-06-18 (glass app: one input - the terminal itself)
- Removed the bottom composer box (and its placeholder). Two input surfaces (a composer + the
  terminal) was confusing; claude's interactive TUI needs raw keys (arrows, Ctrl+C) in the terminal
  anyway, so the terminal is now the SINGLE input - type `sotis: fix the build` right at the `>`
  prompt, exactly like a normal terminal / Claude Code. The active terminal auto-focuses on open.
- The window is now just the title bar + the terminal pane: nothing else to parse.
- Verified live (real window: no composer, terminal focused, stderr clean); selftest ALL PASS.

## v1.15 — 2026-06-18 (glass app: chat feel, not coding feel)
- The glass app now feels like talking, not coding. `bin\sonelle.ps1` got a `-Bare` switch (no
  welcome card, minimal routing echo - just `> <project>`); the app spawns `sonelle.ps1 -Bare`, so a
  tab opens to a calm empty terminal instead of the welcome/help wall.
- Removed the project chips row from the app. You pick a project the way the grammar already works -
  type `sotis: fix the build` in the one bottom composer - and that's it.
- Composer placeholder is conversational ("ask a project to do something   e.g. sotis: fix the build");
  the empty-state card is trimmed to just an "open a terminal" button.
- selftest: asserts `-Bare` suppresses the welcome and that the backend spawns `sonelle.ps1 -Bare`.
  Verified live (real window: no welcome wall, no chips, clean prompt, stderr clean).
- (The bare welcome only affects the app; a plain `sonelle.ps1` console still shows the full welcome.)

## v1.14 — 2026-06-18 (the liquid-glass desktop app: Python front-end, terminal behind the scenes)
- New `app/`: a frameless Python (pywebview / WebView2) desktop app with a muted dark-purple
  liquid-glass UI. Each tab is an xterm.js terminal; the real PowerShell (`bin\sonelle.ps1`) runs
  BEHIND THE SCENES inside a pseudo-terminal (pywinpty) and is rendered by xterm.js - so what you
  type goes to a hidden shell and the interactive `claude` TUI works in-app. The PowerShell routing
  brain is reused unchanged; the Python layer is purely front-end + PTY plumbing.
- `bin\sonelle_gui.ps1`: bootstraps a local `.venv` (pywebview + pywinpty) on first run, then launches
  the GUI with `pythonw` (no console). `:app` and the taskbar shortcut now open this glass app by
  default; the classic WinForms host stays available via `:app-classic` and `make_launcher -Classic`
  (`-Terminal` still makes a single bare console).
- xterm.js 5.5.0 + @xterm/addon-fit 0.10.0 vendored under `app\ui\vendor\` (MIT, offline). The glass
  is self-contained (in-app gradient + `backdrop-filter` panels) because WebView2 can't be transparent
  on Windows - identical on Win10/11. Needs the Evergreen WebView2 runtime (present on Win10/11).
- selftest section 8e asserts the app files exist, the JS<->Python contract markers are present, the
  launcher wiring is correct, and `py_compile`s the backend; section 1 now excludes `.venv` from the
  ASCII gate. `.gitignore` ignores `.venv/` + `__pycache__/`.
- Engineered from a 4-agent research spec (exact pywebview/pywinpty/xterm integration) and hardened by
  a multi-agent adversarial review. Verified headlessly: backend PTY streams `sonelle.ps1` end-to-end,
  the UI renders (browser preview), and a live pywebview window opens/renders/closes cleanly.

## v1.13 — 2026-06-18 (terminal UI: a calm welcome, Claude Code-style)
- The terminal no longer dumps all 11 commands on every launch. A new `Welcome` function draws a
  single clean rounded card (brand + tagline, your projects pulled live from `PROJECTS.md`, and one
  worked example like `sotis: fix the build`) plus a one-line footer (`runs on your Claude
  subscription  ·  @path attaches an image  ·  :help`). The full command list moved to `:help`
  (on demand) - so the first thing you see is calm and obvious, not a wall.
- The prompt is now just a clay `>` arrow (`  >`), matching the minimal Claude Code feel; routing
  feedback is tidier (`> sotis  opus . xhigh` / code path / prompt on their own dim lines).
- Commands are UNCHANGED - still the `:` prefix (`:help :new :dev` ...) and the same grammar
  `[address,] <short>: <prompt>`. Only the presentation changed; nothing to relearn.
- `:help` and `:projects` got a scannable header + aligned two-column layout. The box-drawing glyphs
  are built at runtime via `[char]` codepoints (source stays pure ASCII); output encoding is set to
  UTF-8 so they render in the embedded app consoles too.
- App (`bin\sonelle_app.ps1`): friendlier empty state ("each tab is a full sonelle"). Each embedded
  tab now shows the new welcome, so the whole app reads cleaner with no structural change.
- selftest section 8b: runs `sonelle.ps1 -Demo`, asserts it exits 0, shows the brand + tagline, no
  longer dumps the command list, has a `Welcome` function drawn with runtime box glyphs, and that
  `:help` still lists every command. ALL PASS.

## v1.12 — 2026-06-18 (the sonelle app: many terminals, one window)
- New `bin\sonelle_app.ps1`: a single Claude-styled window that hosts MANY sonelle terminals as
  tabs. Each tab embeds a REAL console running `bin\sonelle.ps1` (reparented into the window via
  Win32 `SetParent`), so every tab is the exact same terminal you get from `sonelle.ps1` - just
  several at once. `[ + new ]` opens a tab; click a tab to switch; the tab's `[x]` closes it
  (kills that terminal's process tree). Self-contained WinForms host - NO Windows Terminal needed.
- Consoles attach ASYNCHRONOUSLY: a `Forms.Timer` polls each spawned terminal for its window handle
  and then reparents it. No blocking, no `DoEvents` re-entrancy - which is what stops the window from
  crashing when you close a tab or click during attach. Every event handler is wrapped (try/catch +
  runtime `$ErrorActionPreference='Continue'`) so a stray error can never tear the window down. The
  app tracks ONLY the PIDs it spawns and kills exactly those on close (never other terminals).
- Polish: dark native title bar (DWM immersive dark mode), a clay accent line under the tab strip,
  per-tab hover + a clay underline on the active tab, hover states on `+ new` and the close mark.
- New terminal command `:app` launches it (via `Start-Process powershell -Sta`); `:help` lists it.
- `bin\make_launcher.ps1` now makes the primary `sonelle` shortcut open the APP by default (icon,
  launched under `-Sta`); use `-Terminal` for a single bare console shortcut.
- selftest section 5c builds the UI + Win32 interop headlessly (`sonelle_app.ps1 -SelfTest`, which
  shows no window and spawns no terminal) and asserts the embed path, theme, and `:app`/launcher wiring.
- Engineering note: built on WinForms (not WPF) - every control has a native HWND, so hosting a
  real console is robust; WPF would need a fragile `WindowsFormsHost` bridge for the same result.

## v1.11 — 2026-06-18 (config: memoryDir; cleaner validate)
- `check_pointers` + `doctor` are now config-aware: they read `hub` AND a new `memoryDir` from
  `sonelle.config.json` (params still override) via a shared `Get-SonelleConfig` in `tools\_registry.ps1`.
  Set `memoryDir` when your project memory lives OUTSIDE `<hub>\memory` (e.g. a Claude Code memory dir),
  so the validate ritual resolves memory pointers correctly instead of reporting false MISS.
- Precedence: an explicit `-Hub` override uses `<hub>\memory` (config.memoryDir does NOT leak into a
  different / temp hub - e.g. selftest's throwaway hub stays correct). `doctor` forwards `-MemoryDir` to
  `check_pointers`. selftest section 9 covers the resolver precedence.
- (brain-backup, separate `sonelle-state` repo) `sonelle_sync.ps1`: `git add` stderr is now redirected
  like commit/push, so the LF->CRLF warnings no longer surface as error records and the script returns a
  clean exit 0 on success.

## v1.10 — 2026-06-18 (address the engine by its own name)
- The engine's own shortcode now routes to self-development: `<engine-name>: <prompt>` (e.g.
  `sonelle, sonelle: add a :foo command`) is the grammar form of `:dev`. The shortcode is derived from
  the engine folder name (`$script:selfShort`), so it follows a rename. It does NOT touch the registry
  (the engine is still not a project) - `Route` special-cases it to `DevSelf` (carrying staged/inline images).
- `:projects` now lists the reserved self-dev shortcode; `:dev` also forwards staged images.
- selftest section 8 asserts the self-shortcode is derived from the folder name and that `Route` routes it to dev.

## v1.9 — 2026-06-18 (self-development: improve the engine from the engine)
- New terminal command `:dev [prompt]`: opens an orchestrator session (your max model) rooted in the
  engine, seeded so it develops the ENGINE itself - it reads `docs\DEVELOPING.md` + `docs\ARCHITECTURE.md`,
  honors the invariants (pure-ASCII PS, no personal data, no hub state in the engine), and must keep
  `tools\selftest.ps1` green. The seed overrides the dispatcher framing of the root `CLAUDE.md` for that session.
- `docs\DEVELOPING.md`: the canonical guide for changing the engine safely (invariants, the selftest gate,
  "extend selftest for every new feature", rewind-via-git, how to add a command/tool/template).
- `CLAUDE.md` + `docs\ARCHITECTURE.md` + `README.md` updated to point at the self-develop path.
- selftest section 8 asserts the `:dev` handler, the `DevSelf` function, `DEVELOPING.md`, and the
  dispatcher pointer are all wired.

## v1.8 — 2026-06-18 (named "sonelle" + final icon)
- NAME: the engine and its private brain-backup were renamed from the working name `luna` to
  **sonelle** (feminine, distinctive). All folders, file names, file content, the two GitHub repos,
  the user `statusLine` path, the launcher shortcut, and the hub dispatcher refs were updated; old
  GitHub URLs redirect.
- ICON: final mark = a coral sound-wave on a deep-plum rounded tile (`#FF9B85` on `#241A33`),
  superseding the earlier moon-phases concept. `assets/icon/make_icon.py` redraws it ->
  `sonelle.ico` (16-256) + `sonelle.png`; vector source `sonelle.svg`.
- selftest ALL PASS after the rename.

## v1.7 — 2026-06-18 (usage status line)
- `tools/statusline.ps1`: a Claude Code statusLine showing usage every session - `model+effort | 5h% |
  7d% | ctx%`, colour-coded green/amber/red by load. Wire via settings.json `statusLine` ->
  `powershell -NoProfile -File .../tools/statusline.ps1` (+ `refreshInterval`). 5h/7d rate-limit % appear
  for Pro/Max after the first API response; gracefully omitted otherwise (ctx always shown).
- selftest asserts the status line renders usage from a sample payload.
- On-demand subscription audit: the `/usage` slash command (account-level, day/week toggle).

## v1.6 — 2026-06-18 (permissions: no-ask deploy + autonomous lanes)
- Lanes take a permission mode: `sonelle_team` start scripts add `--permission-mode <mode>` (config
  `models.lanePermissionMode`, engine default `acceptEdits`). Set `bypassPermissions` in sonelle.config.json
  for fully-autonomous workers (never prompt).
- Orchestrator optional `models.orchestratorPermissionMode` (default unset -> inherits your global default).
- (User-side, not in repo) allow-rules in `~/.claude/settings.json`: `Bash(ssh *)` / `Bash(scp *)` /
  `Bash(git push*)` so VPS deploy + push never prompt; `skipDangerousModePermissionPrompt` so bypass mode
  isn't gated by the danger dialog.
- MCP NOTE: Supabase/Canva/Drive/Calendar/Gmail are claude.ai ACCOUNT connectors (not project-scoped),
  so every sonelle session inherits them already - nothing to move. Chrome = a browser extension that
  attaches per-session (a sonelle session is attachable).
- selftest asserts lane start scripts carry `--permission-mode`.

## v1.5 — 2026-06-18 (model + effort policy)
- ORCHESTRATOR is ALWAYS max: the terminal session you talk to launches `claude` with
  `--model opus --effort xhigh` (a strong boss orchestrates the workers well). Overridable via
  `sonelle.config.json` `models.orchestrator` / `orchestratorEffort`, but defaults to max.
- LANES (workers) take per-lane model + effort: `:team proj bugs=opus,triage=haiku:medium,write=opus`.
  Each lane's start script runs `claude --model <m> --effort <e>`. Defaults `laneDefault=opus` /
  `laneEffort=high` (config `models.laneDefault` / `laneEffort`); per-lane `name=model[:effort]` overrides.
  Models: `haiku | sonnet | opus | claude-fable-5`; effort `low|medium|high|xhigh` (bad effort rejected).
- The terminal echoes the orchestrator model+effort before each hand-off; selftest asserts the per-lane
  model lands in the start script.

## v1.4 — 2026-06-18 (icon + launcher + multi-instance)
- ICON (initial concept; the final mark is the sonelle coral wave - see v1.8): vector source
  `assets/icon/sonelle.svg` + Pillow generator `assets/icon/make_icon.py` -> multi-size `sonelle.ico`
  (16-256) + `sonelle.png`. Re-themeable (edit colors, re-run).
- LAUNCHER: `bin/make_launcher.ps1` creates a pinnable `sonelle.lnk` (Desktop + Start Menu) carrying the
  icon, opening the sonelle terminal from ANYWHERE. Target = Windows Terminal if installed, else powershell.exe.
- MULTI-INSTANCE: `bin/sonelle_team.ps1` runs up to 5 parallel "lanes" on one project - each a `claude`
  session scoped to a DISJOINT workstream, coordinating via a shared board `<code>/.sonelle/lanes/` +
  disjoint ownership (NOT shared live memory). WT tabs if `wt`, else separate windows. Added `:team
  <proj> <lanes>` and `:status <proj>` to the terminal. Cap 5; warns at >3 (rate limits); rejects
  duplicate/bad lane names; `-DryRun` writes the board + start scripts without launching.
- selftest now covers the new scripts (parse/ASCII) + a sonelle_team dry-run (board + start script + parse).
- NOTE: launcher + lane launching fire in real sessions (structurally verified here). `wt` is not
  installed on this machine -> they use PowerShell windows; install Windows Terminal for tabs.

## v1.3 — 2026-06-18 (enforcement hooks)
- **Heal + self-improve are now ENFORCED, not just ritual.** Added Claude Code hooks in
  `.claude/settings.json`: a **SessionStart** hook (recall reminder -> context) and a **Stop** hook
  (auto-runs the project's `sonelle.check.ps1` + a "capture a lesson" reminder). Hooks ship in the engine
  and are scaffolded into every new project (`.claude/hooks/{session_start,stop}.ps1` + `settings.json`).
- `new_project` now also writes a starter `sonelle.check.ps1` into each project (so the Stop hook + doctor
  have a real health surface to run).
- selftest verifies hook scripts parse + are ASCII, both `settings.json` files are valid JSON, and a
  scaffolded project gets `.claude/settings.json` + hooks + `sonelle.check.ps1`.
- NOTE: hooks are structurally verified (parse / JSON / scaffold) but fire only inside real Claude Code
  sessions - not triggered in this build session. Conservative by design (always exit 0, Test-Path guards).

## v1.2 — 2026-06-18 (skeptical-audit fixes)
- **SECURITY:** `.gitignore` had trailing inline comments (git treats `pattern  # x` as a literal
  filename), so `sonelle.config.json` / `memory/` / `*_TODO.txt` were NOT ignored - a `git add -A`
  could have leaked a hub's brain to the public repo. Comments moved to their own lines; verified
  via `git check-ignore` (now a selftest gate).
- **check_pointers** silently validated ZERO projects: its `([^\r\n]*)$` row regex didn't match the
  CRLF rows `new_project` wrote. Root cause was 4 divergent registry regexes; replaced with ONE
  shared CRLF-safe parser `tools\_registry.ps1` used by check_pointers, doctor, and the terminal.
- **selftest** now proves the validator actually works: asserts check_pointers flips to exit 1 on a
  deleted code path, and asserts `.gitignore` ignores the private paths. Both critical bugs would now fail the test.
- `log_lesson.ps1` gained `-Hub` (was writing memory into the engine, not the hub).
- `new_project` normalizes line endings (LF) so it never writes mixed CRLF/LF again.
- Terminal: safe address-strip (only strips a leading `addr,` before a real `short:`; no more
  mangling prose with commas); `@path` only stripped when it's a real file (emails/@handles/decorators
  survive); echoes the final prompt before handing to `claude`; lowercases the shortcode; enables VT /
  falls back to no-color (respects `NO_COLOR`).
- `doctor`: guards missing `git`/`PROJECTS.md`, adds an environment preflight (PowerShell + `claude`
  on PATH), and distinguishes HEALTHY from NOTHING-CHECKED (empty registry no longer reads green).
- Docs made honest: "any machine" -> "any Windows machine + prereqs"; HEAL = detect + manual fix;
  SELF-IMPROVE = capture + discipline (not engine-enforced); documented CLAUDE.md auto-load behavior.

## v1.1 — 2026-06-18
- `-Hub` threading across `new_project` / `check_pointers` / `doctor` + the terminal, so one
  engine can drive a separate workspace coherently.
- Engine vs hub separation: templates are read from the engine, state is written to the hub
  (fixes scaffolding into an external `-Hub`).
- Terminal: image attach via `:attach <path>` and inline `@<path>`; `:clear`.
- `tools\selftest.ps1` + `sonelle.check.ps1`: end-to-end self-test (parse/ASCII/scaffold/
  check_pointers/doctor/duplicate-guard) into a throwaway temp hub. All pass.
- Fixed `$args` automatic-variable shadowing in the terminal's heal path.

## v1.0 — 2026-06-18
- Dispatcher (`CLAUDE.md`) + registry (`PROJECTS.md`) + grammar `[address,] <short>: <prompt>`.
- Claude-styled terminal `bin\sonelle.ps1` (routes to `claude`, runs on a Claude subscription).
- Three superpowers: scaffold (`new_project`), heal (`doctor` + `docs\HEAL.md`),
  self-improve (`log_lesson` + `docs\SELF_IMPROVE.md`).
- Templates, docs (`HEAL`, `SELF_IMPROVE`, `ARCHITECTURE`). Pure-ASCII PowerShell.
