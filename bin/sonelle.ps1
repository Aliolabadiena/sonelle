<#
  sonelle.ps1 - the sonelle terminal. Claude-styled launcher: reads the grammar
  `[address,] <short>: <prompt>`, routes to the right project via PROJECTS.md, and hands
  the prompt to `claude` (Claude Code) - which runs on your Claude subscription.

  Usage:
    powershell -File bin\sonelle.ps1          start the terminal (REPL)
    powershell -File bin\sonelle.ps1 -Demo    print the banner + help, then exit (no REPL)

  Commands inside:  <short>: <prompt>   :projects   :new   :heal [short]   :team   :status   :dev   :help   :q
  Source is pure ASCII; Unicode glyphs are built at runtime via [char] codepoints.
#>
[CmdletBinding()]
param([switch]$Demo, [switch]$Bare, [switch]$Yolo, [string]$Hub = '')   # -Bare: chat-feel (glass app); -Yolo: claude skips permission prompts; -Hub: workspace override (wins over config)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
# Capture -Hub NOW: PowerShell variable names are case-insensitive, so the param $Hub and the working
# variable $hub are the SAME slot - any later '$hub = ...' would clobber the override otherwise.
$hubOverride = $Hub
. (Join-Path $root 'tools\_registry.ps1')
# ONE config resolver (Get-SonelleConfig): hub (-Hub override wins) + the raw models block. No ad-hoc parse here.
$resolved  = Get-SonelleConfig -Engine $root -HubOverride $hubOverride
$hub       = $resolved.Hub
# Orchestrator (the session you talk to): model + effort (sensible thinky defaults). code-writer = the
# model claude's file-editing SUBAGENTS use (via CLAUDE_CODE_SUBAGENT_MODEL); '' = inherit the orchestrator.
$orchModel = 'opus'; $orchEffort = 'xhigh'; $orchPerm = ''; $orchCode = ''
$origSubagentModel = $env:CLAUDE_CODE_SUBAGENT_MODEL   # preserve any external override so '' restores it
$cm = $resolved.Models
if ($cm) {
  if ($cm.orchestrator)               { $orchModel = $cm.orchestrator }
  if ($cm.orchestratorEffort)         { $orchEffort = $cm.orchestratorEffort }
  if ($cm.orchestratorPermissionMode) { $orchPerm = $cm.orchestratorPermissionMode }
  if ($cm.codeWriter)                 { $orchCode = [string]$cm.codeWriter }
}
# -Yolo (or the env var the glass app forwards) overrides the mode so claude never asks for permission.
# bypassPermissions is a real claude --permission-mode choice; toggle it live in the REPL with :yolo.
if ($Yolo -or $env:SONELLE_YOLO) { $orchPerm = 'bypassPermissions' }
# Re-read the orchestrator model/effort + the code-writer (subagent) model from config right BEFORE each
# claude launch, so a change in the app's settings panel applies to the NEXT prompt with no tab restart
# (the panel writes sonelle.config.json - that file, or $env:SONELLE_CONFIG, is the channel). Permission
# mode is NOT re-read here: it has live overrides (-Yolo / SONELLE_YOLO / :yolo) a re-read would clobber.
function RefreshOrch {
  try {
    $r = Get-SonelleConfig -Engine $root -HubOverride $hubOverride
    $m = $r.Models
    if ($m) {
      if ($m.orchestrator)       { $script:orchModel  = [string]$m.orchestrator }
      if ($m.orchestratorEffort) { $script:orchEffort = [string]$m.orchestratorEffort }
      $script:orchCode = if ($m.codeWriter) { [string]$m.codeWriter } else { '' }
    } else { $script:orchCode = '' }
  } catch {}
  # route file-editing to its OWN model via claude's subagent override; '' restores any external value.
  if ($script:orchCode) { $env:CLAUDE_CODE_SUBAGENT_MODEL = $script:orchCode }
  elseif ($script:origSubagentModel) { $env:CLAUDE_CODE_SUBAGENT_MODEL = $script:origSubagentModel }
  else { Remove-Item Env:CLAUDE_CODE_SUBAGENT_MODEL -ErrorAction SilentlyContinue }
}
# Voice narrator (glass app): when the app set SONELLE_NARRATE_SETTINGS, attach it as claude's
# --settings so claude's hooks stream progress events to the per-tab file the app narrates from.
# The app only sets this env after probing that `claude` supports --settings, so we can never feed
# claude a bad flag here. Empty (no narration) for a plain terminal -> nothing changes.
$orchSettings = ''
if ($env:SONELLE_NARRATE_SETTINGS -and (Test-Path $env:SONELLE_NARRATE_SETTINGS)) { $orchSettings = $env:SONELLE_NARRATE_SETTINGS }
# Probe `claude --help` ONCE (cached per process) for a flag, so a missing flag can never break a working
# session - the same defensive contract the narrator uses before attaching --settings. Used below to gate
# --append-system-prompt; a build without it falls back to folding the framing into the prompt.
$script:claudeHelp = $null
function ClaudeSupports($flag) {
  if ($null -eq $script:claudeHelp) {
    try { $script:claudeHelp = (& claude --help 2>$null | Out-String) } catch { $script:claudeHelp = '' }
  }
  return ([bool]($script:claudeHelp -match [regex]::Escape($flag)))
}
# Inherent altitude directive: sonelle appends this to EVERY session it launches (engine-dev + project
# routes) via claude's --append-system-prompt. It SELF-GATES - claude takes the deep, subagent-delegating
# path only when a task is genuinely hard, and skips it for small ones (best results on the hard tasks, no
# wasted effort on the easy ones). One line (no newlines / cmd metacharacters) so it passes through any
# launcher unmangled.
$script:delegationDirective = 'Altitude - match your effort to the task: for a large or multi-file change, like a refactor or a cross-cutting edit that first needs you to understand how several files interact, delegate the breadth-first exploration to subagents via the Task tool and keep your own context for the synthesis and the edit; for a small focused change just do it directly and do not spawn subagents or over-plan a one-liner.'
$psExe = (Get-Process -Id $PID).Path
# (_registry.ps1 is already dot-sourced above for Get-SonelleConfig - Get-SonelleProjects comes from it too.)

# --- color support: enable VT on legacy consoles; fall back to plain text ---
$useColor = -not $env:NO_COLOR
if ($useColor) {
  try {
    $vt = Add-Type -Name SonelleVT -Namespace Win32 -PassThru -ErrorAction Stop -MemberDefinition '[DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int h); [DllImport("kernel32.dll")] public static extern bool GetConsoleMode(IntPtr h, out int m); [DllImport("kernel32.dll")] public static extern bool SetConsoleMode(IntPtr h, int m);'
    $h = $vt::GetStdHandle(-11); $m = 0
    if ($vt::GetConsoleMode($h, [ref]$m)) { [void]$vt::SetConsoleMode($h, ($m -bor 4)) }   # ENABLE_VIRTUAL_TERMINAL_PROCESSING
  } catch {}
}
# --- palette (Claude: clay accent, cream text) via ANSI 24-bit; empty when no color ---
if ($useColor) {
  $E = [char]27
  $clay = "$E[38;2;204;120;92m"; $cream = "$E[38;2;235;232;222m"; $dim = "$E[38;2;140;140;140m"; $bold = "$E[1m"; $R = "$E[0m"
} else { $clay = ''; $cream = ''; $dim = ''; $bold = ''; $R = '' }
$bar = ([string][char]0x2500) * 50
$arrow = [string][char]0x25B8
# rounded box-drawing glyphs (built at runtime so the source stays pure ASCII)
$gTL = [string][char]0x256D; $gTR = [string][char]0x256E; $gBL = [string][char]0x2570; $gBR = [string][char]0x256F
$gH  = [string][char]0x2500; $gV  = [string][char]0x2502; $dot = [string][char]0x00B7
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$script:staged = @()   # image paths staged via :attach, consumed by the next routed prompt
$script:selfShort = (Split-Path $root -Leaf).ToLower()   # the engine's own name -> routes to self-development (:dev)
$script:bare = [bool]$Bare   # chat-feel mode for the app: suppress welcome + trim routing echo
# A4: the build stamp = the top version header in CHANGELOG.md (the source of truth; no version tags),
# so any session/log can record exactly which engine build it ran against.
function SonelleVersion {
  $cl = Join-Path $root 'CHANGELOG.md'
  if (Test-Path $cl) { foreach ($l in (Get-Content $cl -TotalCount 40)) { if ($l -match '^##\s+(v[0-9][^ ]*)') { return $Matches[1] } } }
  return ''
}
$script:version = SonelleVersion

function ProjectShorts {
  $pf = Join-Path $hub 'PROJECTS.md'
  if (Test-Path $pf) { return @((Get-SonelleProjects $pf) | ForEach-Object { $_.Short }) }
  return @()
}
# A clean welcome card (drawn once at start; -NoClear skips the screen clear for demo/piped runs).
# Replaces the old full-command dump: the welcome stays minimal, and :help shows everything on demand.
function Welcome {
  param([switch]$NoClear)
  if (-not $NoClear) { try { Clear-Host } catch {} }
  $iw = 46
  function Row($plain, $body) {
    $pad = $iw - 2 - $plain.Length; if ($pad -lt 0) { $pad = 0 }
    Write-Host ("  " + $clay + $gV + $R + " " + $body + (' ' * $pad) + " " + $clay + $gV + $R)
  }
  Write-Host ""
  Write-Host ("  " + $clay + $gTL + ($gH * $iw) + $gTR + $R)
  Row "sonelle   your projects, one orchestrator" ($clay + $bold + "sonelle" + $R + "   " + $dim + "your projects, one orchestrator" + $R)
  Row "" ""
  $shorts = ProjectShorts
  if ($shorts.Count -gt 0) {
    $show  = @($shorts | Select-Object -First 5)
    $extra = $shorts.Count - $show.Count
    $sepP  = " " + $dot + " "
    $plainList = ($show -join $sepP)
    $colList   = (($show | ForEach-Object { $clay + $_ + $R }) -join (" " + $dim + $dot + $R + " "))
    if ($extra -gt 0) { $plainList += $sepP + "+" + $extra; $colList += " " + $dim + $dot + $R + " " + $dim + "+" + $extra + $R }
    Row ("projects   " + $plainList) ($dim + "projects   " + $R + $colList)
    $eg = $show[0]
  } else {
    Row ("projects   none yet " + $dot + " type :new") ($dim + "projects   none yet " + $dot + " type " + $R + $cream + ":new" + $R)
    $eg = "myproj"
  }
  Row ("type       " + $eg + ": fix the build") ($dim + "type       " + $R + $cream + $eg + ": fix the build" + $R)
  Write-Host ("  " + $clay + $gBL + ($gH * $iw) + $gBR + $R)
  $ver = if ($script:version) { "  " + $dot + "  " + $script:version } else { "" }
  Write-Host ("  " + $dim + "runs on your Claude subscription  " + $dot + "  @path attaches an image  " + $dot + "  :help" + $ver + $R)
  Write-Host ""
}
function ShowHelp {
  $hver = if ($script:version) { "  " + $dim + $script:version + $R } else { "" }
  Write-Host ("  " + $bold + "commands" + $R + $hver)
  Write-Host ""
  $rows = @(
    @("<short>: <prompt>",    ("run a prompt in a project  (e.g. " + $cream + "sotis: fix the build" + $dim + ")")),
    @("general: <prompt>",    "one-off question / quick task - no project, no saved state"),
    @(":attach <path>",       ("attach an image to the next prompt (or inline " + $cream + "@path" + $dim + ")")),
    @(":projects",            "list your projects"),
    @(":new",                 "scaffold a new project"),
    @(":adopt <path>",        "convert an existing project into the workflow (AI, best-effort)"),
    @(":heal [short]",        "health-check / heal a project"),
    @(":team <proj> <lanes>", "run up to 5 parallel lanes on one project"),
    @(":status <proj>",       "show each lane's status"),
    @(":app",                 "open the liquid-glass app (many terminals, one window)"),
    @(":app-classic",         "open the classic WinForms app (fallback)"),
    @(":dev [prompt]",        ("improve sonelle itself (or  " + $cream + $script:selfShort + ": ..." + $dim + ")")),
    @(":yolo [on|off]",       "toggle claude skipping permission prompts (bypassPermissions)"),
    @(":clear",               "clear staged images"),
    @(":help   :q",           "this help / quit")
  )
  # NOTE: loop var must NOT be $r - PowerShell vars are case-insensitive, so $r would clobber the
  # ANSI reset $R used just below. Concatenated descriptions are parenthesized because the comma
  # operator binds tighter than +, which would otherwise split a row into many array elements.
  foreach ($row in $rows) {
    $left = $row[0]; $pad = 22 - $left.Length; if ($pad -lt 1) { $pad = 1 }
    Write-Host ("    " + $cream + $left + $R + (' ' * $pad) + $dim + $row[1] + $R)
  }
}
# The glass app opens each tab in -Bare mode; a blank prompt is unfriendly, so show a tiny NO-CLAUDE
# primer (make a project / bring one in / run a task / connect claude) instead of the full welcome card.
function BareIntro {
  Write-Host ""
  Write-Host ("  " + $clay + $bold + "sonelle" + $R + "  " + $dim + "run your projects through one assistant  " + $dot + "  type " + $R + $cream + "help" + $R)
  Write-Host ("  " + $dim + "make a project   " + $R + $cream + ":new" + $R + $dim + "    bring an existing one in   " + $R + $cream + ":adopt <path>" + $R)
  Write-Host ("  " + $dim + "run a task       " + $R + $cream + "<short>: <prompt>" + $R + $dim + "   e.g.  " + $R + $cream + "myproj: fix the build" + $R)
  Write-Host ("  " + $dim + "connect claude   install Claude Code and sign in:  https://claude.com/claude-code" + $R)
  Write-Host ""
}
function ShowProjects {
  Write-Host ("  " + $bold + "projects" + $R)
  $pf = Join-Path $hub 'PROJECTS.md'
  if (Test-Path $pf) {
    $projs = Get-SonelleProjects $pf
    if ($projs.Count -eq 0) { Write-Host ("    " + $dim + "registry empty - type :new to create your first project." + $R) }
    else { foreach ($p in $projs) { Write-Host ("    " + $clay + $p.Short + $R + "   " + $dim + $p.Name + $R) } }
  } else { Write-Host ("    " + $dim + "no PROJECTS.md at hub: " + $hub + $R) }
  Write-Host ("    " + $clay + $script:selfShort + $R + "   " + $dim + "(the engine itself - develop it; same as :dev)" + $R)
}
function ResolveCode($short) {
  $pf = Join-Path $hub 'PROJECTS.md'
  $p = (Get-SonelleProjects $pf) | Where-Object { $_.Short -eq $short } | Select-Object -First 1
  if ($p) { return $p.CodePath }
  return $null
}
function NewProject {
  $s = (Read-Host "  shortcode (a-z0-9_)").Trim()
  if (-not $s) { return }
  $n = (Read-Host "  project name").Trim()
  $p = (Read-Host "  code path").Trim()
  & $psExe -ExecutionPolicy Bypass -File (Join-Path $root 'tools\new_project.ps1') $s $n $p -Hub $hub | Out-Host
}
function Heal($short) {
  $dargs = @('-ExecutionPolicy','Bypass','-File',(Join-Path $root 'tools\doctor.ps1'))
  if ($short) { $dargs += $short }
  $dargs += @('-Hub', $hub)
  & $psExe @dargs | Out-Host
}
function Team($rest) {
  $rest = $rest.Trim(); $sp = $rest.IndexOf(' ')
  if ($sp -lt 1) { Write-Host ("  {0}usage: :team <project> <lane1,lane2,...>{1}" -f $dim, $R); return }
  $pj = $rest.Substring(0, $sp)
  $ln = ($rest.Substring($sp + 1).Trim()) -replace '\s+', ','
  & $psExe -ExecutionPolicy Bypass -File (Join-Path $root 'bin\sonelle_team.ps1') $pj -Lanes $ln -Hub $hub | Out-Host
}
function StatusLanes($pj) {
  if (-not $pj) { Write-Host ("  {0}usage: :status <project>{1}" -f $dim, $R); return }
  & $psExe -ExecutionPolicy Bypass -File (Join-Path $root 'bin\sonelle_team.ps1') $pj -Status -Hub $hub | Out-Host
}
function Adopt($rest) {
  # bring an EXISTING (non-sonelle) project into the workflow: scaffold the skeleton over it, then hand
  # claude an AI pass to adapt the generic scaffold to the real code. Best-effort - a very different repo
  # structure may need a manual fix. Existing files are backed up to *.pre-sonelle.bak, never clobbered.
  $rest = $rest.Trim()
  if (-not $rest) { Write-Host ("  {0}usage: :adopt <path-to-existing-project> [as <shortcode>]{1}" -f $dim, $R); return }
  $short = ''
  if ($rest -match '^(.*?)\s+as\s+([A-Za-z0-9_]+)\s*$') { $path = $Matches[1]; $short = $Matches[2].ToLower() } else { $path = $rest }
  $path = $path.Trim().Trim('"')
  if (-not (Test-Path $path -PathType Container)) { Write-Host ("  {0}[!] not a folder: {1}{2}" -f $clay, $path, $R); return }
  $path = (Resolve-Path $path).Path
  if (-not $short) { $short = ((Split-Path $path -Leaf).ToLower() -replace '[^a-z0-9_]', ''); if (-not $short) { $short = 'proj' } }
  $pf = Join-Path $hub 'PROJECTS.md'
  if ((Test-Path $pf) -and @((Get-SonelleProjects $pf) | Where-Object { $_.Short -eq $short }).Count) {
    Write-Host ("  {0}[!] '{1}' is already registered - choose another:  :adopt <path> as <short>{2}" -f $clay, $short, $R); return
  }
  Write-Host ("  " + $clay + $arrow + " adopt" + $R + "  " + $dim + $path + "  " + $dot + "  as " + $R + $cream + $short + $R)
  Write-Host ("  {0}this writes sonelle's files INTO that folder (CLAUDE.md, sonelle.check.ps1, .claude\) and then{1}" -f $dim, $R)
  Write-Host ("  {0}asks claude to adapt them to your code. BEST-EFFORT: a very different structure may need a{1}" -f $dim, $R)
  Write-Host ("  {0}manual fix. existing files are backed up to *.pre-sonelle.bak (nothing is overwritten blind).{1}" -f $dim, $R)
  if ((Read-Host "  adopt it now? (y/N)") -notmatch '^(y|Y)') { Write-Host ("  {0}cancelled - nothing changed.{1}" -f $dim, $R); return }
  # non-destructive: back up anything new_project would overwrite
  $bk = @()
  foreach ($rel in @('CLAUDE.md', 'sonelle.check.ps1')) {
    $fp = Join-Path $path $rel
    if (Test-Path $fp) { Copy-Item $fp ($fp + '.pre-sonelle.bak') -Force; $bk += $rel }
  }
  $cdir = Join-Path $path '.claude'
  if (Test-Path $cdir) { $bdir = $cdir + '.pre-sonelle.bak'; if (Test-Path $bdir) { Remove-Item $bdir -Recurse -Force }; Copy-Item $cdir $bdir -Recurse -Force; $bk += '.claude' }
  if ($bk.Count) { Write-Host ("  {0}backed up: {1}  (-> *.pre-sonelle.bak){2}" -f $dim, ($bk -join ', '), $R) }
  # scaffold the skeleton (registry row + hub state + project files)
  & $psExe -ExecutionPolicy Bypass -File (Join-Path $root 'tools\new_project.ps1') $short (Split-Path $path -Leaf) $path -Hub $hub | Out-Host
  if ($LASTEXITCODE -ne 0) { Write-Host ("  {0}[!] scaffold failed - skipping the AI conversion.{1}" -f $clay, $R); return }
  # hand claude the conversion task; Route reuses the launch path (model/effort/append-system-prompt, cd in)
  $conv = "This project was just ADOPTED into sonelle from an EXISTING codebase - it was NOT built for sonelle, so treat this as best-effort and tell me honestly what you cannot adapt. Do NOT change application code or behavior. " +
          "Step 1: read the project to learn its REAL build/test setup. " +
          "Step 2: rewrite sonelle.check.ps1 so it runs this project's ACTUAL tests/build - right now it is a generic auto-detect placeholder; if there is genuinely no check, say so and leave a clear TODO instead of a fake pass. " +
          "Step 3: rewrite CLAUDE.md to describe how to actually work in THIS repo; if a CLAUDE.md.pre-sonelle.bak exists, merge anything useful from it, then you may delete the .pre-sonelle.bak files. " +
          "Step 4: update the project's TODO and ledger to reflect the real current state. " +
          "Step 5: finish with a short, honest report of what you adapted and what still needs my manual attention."
  Write-Host ("  {0}scaffold done - handing claude the conversion (best-effort)...{1}" -f $dim, $R)
  Route $short $conv @()
}
function AppLaunch {
  # the liquid-glass Python app (pywebview); the terminal runs inside it via a hidden PTY
  $gui = Join-Path $root 'bin\sonelle_gui.ps1'
  if (-not (Test-Path $gui)) { Write-Host ("  {0}[!] app launcher not found: {1}{2}" -f $clay, $gui, $R); return }
  Write-Host ("  {0}-> opening the {1}sonelle app{0} (liquid glass)...{2}" -f $dim, $clay, $R)
  $pyw = Join-Path $root '.venv\Scripts\pythonw.exe'
  $py  = Join-Path $root '.venv\Scripts\python.exe'
  $appPy = Join-Path $root 'app\sonelle_gui.py'
  $depsOk = $false
  if ((Test-Path $pyw) -and (Test-Path $py) -and (Test-Path $appPy)) {
    # P1: cache the import probe with a sentinel so we don't spawn python on every launch. Re-probe only
    # when the sentinel is missing or older than requirements.txt (a deps change invalidates the cache).
    $sentinel = Join-Path $root '.venv\.deps_ok'
    $reqFile  = Join-Path $root 'app\requirements.txt'
    $reqTime  = if (Test-Path $reqFile) { (Get-Item $reqFile).LastWriteTimeUtc } else { [datetime]::MinValue }
    if ((Test-Path $sentinel) -and ((Get-Item $sentinel).LastWriteTimeUtc -ge $reqTime)) {
      $depsOk = $true
    } else {
      & $py -c 'import webview, winpty' 2>$null   # pythonw has no stderr; probe first so a half-installed venv can't die silently
      $depsOk = ($LASTEXITCODE -eq 0)
      if ($depsOk) { try { Set-Content -Path $sentinel -Value ((Get-Date).ToUniversalTime().ToString('o')) -ErrorAction SilentlyContinue } catch {} }
    }
  }
  if ($depsOk) {
    # deps confirmed - launch the GUI directly, no console flash
    Start-Process -FilePath $pyw -ArgumentList @($appPy) -WorkingDirectory (Join-Path $root 'app') | Out-Null
  } else {
    # missing/partial venv - go through the bootstrap launcher (creates .venv, shows install progress)
    Start-Process $psExe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $gui) | Out-Null
  }
}
function AppLaunchClassic {
  # the classic WinForms host (reparents real consoles) - kept as a fallback
  $app = Join-Path $root 'bin\sonelle_app.ps1'
  if (-not (Test-Path $app)) { Write-Host ("  {0}[!] app not found: {1}{2}" -f $clay, $app, $R); return }
  Write-Host ("  {0}-> opening the classic {1}sonelle app{0} (WinForms tabs)...{2}" -f $dim, $clay, $R)
  Start-Process $psExe -ArgumentList @('-NoProfile', '-Sta', '-ExecutionPolicy', 'Bypass', '-File', $app) | Out-Null
}
function DevSelf($prompt, $images) {
  $claude = Get-Command claude -ErrorAction SilentlyContinue
  if (-not $claude) {
    Write-Host ("  {0}[!] 'claude' not found on PATH - install Claude Code + log into your subscription first.{1}" -f $clay, $R)
    return
  }
  $ask = if ($prompt) { $prompt } else { 'Ask me what to improve, then propose a short plan before editing.' }
  if ($images -and $images.Count -gt 0) {
    $ask = $ask + "`n`nAttached image(s) - please read them:`n" + (($images | ForEach-Object { " - $_" }) -join "`n")
    Write-Host ("  {0}+ {1} image(s) attached{2}" -f $dim, $images.Count, $R)
  }
  # Engine-dev framing lives in the SYSTEM prompt (--append-system-prompt), not the user turn, so it holds
  # up under long sessions / compaction instead of getting buried. The task itself stays the user prompt.
  $framing = "You are developing the sonelle ENGINE ITSELF (this repository = your current working directory). It is a PUBLIC repo with ZERO personal data.`n" +
          "Read docs\DEVELOPING.md and docs\ARCHITECTURE.md FIRST, and treat docs\DEVELOPING.md as your SOLE authority for THIS session. Claude Code auto-loads the root CLAUDE.md (the dispatcher template the engine ships) - IGNORE its dispatcher / project-routing / state-reading framing here; this session develops the engine, it does not route projects or manage a hub.`n" +
          "Honor every invariant in DEVELOPING.md: pure-ASCII PowerShell, no personal data in the repo, do NOT scaffold hub/project state (never run new_project or log_lesson at the engine root), and run tools\selftest.ps1 to ALL PASS before any commit (extend selftest for new features so the engine stays self-verifying). Everything is git-versioned, so changes are rewindable."
  RefreshOrch   # pick up any settings-panel change to model/effort/code-writer (live, no restart)
  $mline = $orchModel + " " + $dot + " " + $orchEffort; if ($orchCode) { $mline += " " + $dot + " code:" + $orchCode }
  Write-Host ("  " + $clay + $arrow + " dev" + $R + "  " + $dim + "developing the engine itself  " + $dot + "  " + $mline + $R)
  $dirty = $false
  if (Get-Command git -ErrorAction SilentlyContinue) { try { $dirty = [bool](& git -C $root status --porcelain 2>$null) } catch {} }
  if ($dirty) { Write-Host ("  {0}note: engine has uncommitted changes - commit/stash first for a clean rewind point.{1}" -f $dim, $R) }
  $cargs = @('--model', $orchModel, '--effort', $orchEffort)
  # framing + the inherent altitude directive ride the system prompt when claude supports it; otherwise
  # fold them into the prompt (older builds) so behavior degrades gracefully, never breaks.
  if (ClaudeSupports '--append-system-prompt') { $cargs += @('--append-system-prompt', ($framing + "`n`n" + $script:delegationDirective)); $promptArg = $ask }
  else { $promptArg = $framing + "`n`n" + $script:delegationDirective + "`n`nTask: " + $ask }
  if ($orchPerm) { $cargs += @('--permission-mode', $orchPerm) }; if ($orchSettings) { $cargs += @('--settings', $orchSettings) }
  Push-Location $root
  try { & claude @cargs $promptArg } finally { Pop-Location }
  # invariant #4 guard: the engine must stay clean of hub state - warn if a session left any behind
  $junk = @(Get-ChildItem $root -Filter '*_TODO.txt' -File -ErrorAction SilentlyContinue) + @(Get-ChildItem $root -Filter '_*_run_STATUS.md' -File -ErrorAction SilentlyContinue)
  if ($junk.Count -gt 0 -or (Test-Path (Join-Path $root 'memory'))) {
    Write-Host ("  {0}[!] hub-state (TODO/ledger/memory) detected in the engine root - it must stay clean; move it to your hub or delete it.{1}" -f $clay, $R)
  }
  $script:staged = @()   # staged images consumed
}
function General($prompt, $images) {
  # one-off Q/A or quick task with NO project: run claude in a NEUTRAL scratch dir (outside any hub/project
  # tree, so no CLAUDE.md is auto-loaded) and write NO hub state / memory / registry row - nothing to clutter.
  $claude = Get-Command claude -ErrorAction SilentlyContinue
  if (-not $claude) {
    Write-Host ("  {0}[!] 'claude' not found on PATH. Install Claude Code and log into your subscription.{1}" -f $clay, $R)
    return
  }
  $finalPrompt = $prompt
  if ($images -and $images.Count -gt 0) {
    $finalPrompt = $prompt + "`n`nAttached image(s) - please read them:`n" + (($images | ForEach-Object { " - $_" }) -join "`n")
    Write-Host ("  {0}+ {1} image(s) attached{2}" -f $dim, $images.Count, $R)
  }
  # neutral ground: $env:TEMP has no CLAUDE.md up its tree, so claude starts with a clean slate
  $scratch = Join-Path $env:TEMP 'sonelle_general'
  if (-not (Test-Path $scratch)) { New-Item -ItemType Directory -Path $scratch -Force | Out-Null }
  RefreshOrch
  $mline = $orchModel + " " + $dot + " " + $orchEffort; if ($orchCode) { $mline += " " + $dot + " code:" + $orchCode }
  if ($script:bare) {
    Write-Host ("  " + $clay + $arrow + " " + $R + $dim + "general" + $R)
  } else {
    Write-Host ("  " + $clay + $arrow + " general" + $R + "  " + $dim + $mline + $R)
    Write-Host ("    " + $dim + "scratch (no project, no saved state)" + $R)
    Write-Host ("    " + $dim + ($finalPrompt -replace "`n", " / ") + $R)
  }
  $cargs = @('--model', $orchModel, '--effort', $orchEffort)
  if (ClaudeSupports '--append-system-prompt') { $cargs += @('--append-system-prompt', $script:delegationDirective) }
  else { $finalPrompt = $script:delegationDirective + "`n`n" + $finalPrompt }
  if ($orchPerm) { $cargs += @('--permission-mode', $orchPerm) }; if ($orchSettings) { $cargs += @('--settings', $orchSettings) }
  Push-Location $scratch
  try { & claude @cargs $finalPrompt } finally { Pop-Location }
  $script:staged = @()   # staged images consumed
}
function Route($short, $prompt, $images) {
  if ($short -eq $script:selfShort) { DevSelf $prompt $images; return }   # the engine's own name -> develop the engine
  if ($short -eq 'general') { General $prompt $images; return }           # reserved: a neutral scratch lane (no project/state)
  $code = ResolveCode $short
  if (-not $code) {
    Write-Host ("  {0}'{1}' is not in the registry.{2}" -f $clay, $short, $R)
    if ((Read-Host "  create new project '$short'? (y/N)") -match '^(y|Y)') { NewProject }
    return
  }
  if ($code -notmatch '^[-(]' -and -not (Test-Path $code)) { Write-Host ("  {0}[warn] code path missing: {1}{2}" -f $clay, $code, $R) }
  $claude = Get-Command claude -ErrorAction SilentlyContinue
  if (-not $claude) {
    Write-Host ("  {0}[!] 'claude' not found on PATH. Install Claude Code and log into your subscription,{1}" -f $clay, $R)
    Write-Host ("  {0}    then this terminal will hand prompts to it. (https://claude.com/claude-code){1}" -f $dim, $R)
    return
  }
  $finalPrompt = $prompt
  if ($images -and $images.Count -gt 0) {
    $finalPrompt = $prompt + "`n`nAttached image(s) - please read them:`n" + (($images | ForEach-Object { " - $_" }) -join "`n")
    Write-Host ("  {0}+ {1} image(s) attached{2}" -f $dim, $images.Count, $R)
  }
  RefreshOrch   # pick up any settings-panel change to model/effort/code-writer (live, no restart)
  $mline = $orchModel + " " + $dot + " " + $orchEffort; if ($orchCode) { $mline += " " + $dot + " code:" + $orchCode }
  if ($script:bare) {
    Write-Host ("  " + $clay + $arrow + " " + $R + $dim + $short + $R)   # chat feel: just confirm the project
  } else {
    Write-Host ("  " + $clay + $arrow + " " + $short + $R + "  " + $dim + $mline + $R)
    Write-Host ("    " + $dim + $code + $R)
    Write-Host ("    " + $dim + ($finalPrompt -replace "`n", " / ") + $R)
  }
  $cargs = @('--model', $orchModel, '--effort', $orchEffort)
  # the inherent altitude directive rides the system prompt (self-gates: deep on hard tasks, direct on easy)
  if (ClaudeSupports '--append-system-prompt') { $cargs += @('--append-system-prompt', $script:delegationDirective) }
  else { $finalPrompt = $script:delegationDirective + "`n`n" + $finalPrompt }
  if ($orchPerm) { $cargs += @('--permission-mode', $orchPerm) }; if ($orchSettings) { $cargs += @('--settings', $orchSettings) }
  if ($code -notmatch '^[-(]' -and (Test-Path $code)) { Push-Location $code } else { Push-Location $root }
  try { & claude @cargs $finalPrompt } finally { Pop-Location }
  $script:staged = @()   # staged images consumed
}

if (-not $script:bare) { Welcome -NoClear:([bool]$Demo) } else { BareIntro }
if ($Demo) { Write-Host ("  " + $dim + "(demo mode - welcome only; no REPL)" + $R); return }

while ($true) {
  Write-Host -NoNewline ("  " + $clay + $arrow + " " + $R)
  $in = Read-Host
  if ($null -eq $in) { break }
  $t = $in.Trim()
  if (-not $t) { continue }
  if ($t -match '^:(q|quit|exit)$') { break }
  elseif ($t -eq ':help') { ShowHelp; continue }
  elseif ($t -match '^\s*(help|\?)\s*:?\s*$') { ShowHelp; continue }   # bare 'help' / 'help:' / '?' -> commands, never routed to claude
  elseif ($t -eq ':projects') { ShowProjects; continue }
  elseif ($t -eq ':new') { NewProject; continue }
  elseif ($t -match '^:adopt\b\s*(.*)$') { Adopt ($Matches[1].Trim()); continue }
  elseif ($t -match '^:heal\s*(.*)$') { Heal ($Matches[1].Trim()); continue }
  elseif ($t -match '^:team\s+(.+)$') { Team $Matches[1]; continue }
  elseif ($t -match '^:status\s*(.*)$') { StatusLanes ($Matches[1].Trim()); continue }
  elseif ($t -eq ':app') { AppLaunch; continue }
  elseif ($t -eq ':app-classic') { AppLaunchClassic; continue }
  elseif ($t -match '^:dev\b\s*(.*)$') { DevSelf ($Matches[1].Trim()) $script:staged; continue }
  elseif ($t -match '^:attach\s+(.+)$') {
    $ip = $Matches[1].Trim().Trim('"')
    if (Test-Path $ip) { $script:staged += (Resolve-Path $ip).Path; Write-Host ("  {0}staged ({1} total): {2}{3}" -f $dim, $script:staged.Count, $ip, $R) }
    else { Write-Host ("  {0}[!] not found: {1}{2}" -f $clay, $ip, $R) }
    continue
  }
  elseif ($t -eq ':clear') { $script:staged = @(); Write-Host ("  {0}staged images cleared{1}" -f $dim, $R); continue }
  elseif ($t -match '^:yolo\b\s*(.*)$') {
    # toggle (or set on/off) whether claude skips permission prompts; applies to the NEXT prompt onward
    $a = $Matches[1].Trim().ToLower()
    if     ($a -eq 'on')  { $orchPerm = 'bypassPermissions' }
    elseif ($a -eq 'off') { $orchPerm = '' }
    else   { $orchPerm = if ($orchPerm -eq 'bypassPermissions') { '' } else { 'bypassPermissions' } }
    if ($orchPerm -eq 'bypassPermissions') {
      Write-Host ("  {0}yolo {1}ON{0}  - claude will NOT ask for permission (bypassPermissions){2}" -f $dim, $clay, $R)
    } else {
      Write-Host ("  {0}yolo {1}OFF{0} - claude asks before risky actions (default){2}" -f $dim, $cream, $R)
    }
    continue
  }
  else {
    $bodyText = $t
    # strip a leading "address," ONLY when what follows is a real "<short>: ..." (don't mangle prose with commas)
    if ($bodyText -match '^[A-Za-z0-9 _-]+,\s*([a-z0-9_]+\s*:.+)$') { $bodyText = $Matches[1] }
    # pull out inline @<path> images, removing ONLY tokens that are real files (leave emails/@handles/decorators alone)
    $imgs = @() + $script:staged
    foreach ($mm in [regex]::Matches($bodyText, '@"([^"]+)"|@(\S+)')) {
      $p = if ($mm.Groups[1].Value) { $mm.Groups[1].Value } else { $mm.Groups[2].Value }
      if (Test-Path $p) { $imgs += (Resolve-Path $p).Path; $bodyText = $bodyText.Replace($mm.Value, '') }
    }
    $bodyText = $bodyText.Trim()
    if ($bodyText -match '^([a-z0-9_]+)\s*:\s*(.+)$') { Route $Matches[1].ToLower() $Matches[2] $imgs }
    else { Write-Host ("  {0}? use  {1}<short>: <prompt>{0}  (e.g.  myproj: fix the build){2}" -f $dim, $cream, $R) }
  }
}
Write-Host ("{0}  bye.{1}" -f $dim, $R)
