<#
  narrate_hook.ps1 - the Claude Code hook command behind sonelle's voice narrator.

  When the glass app launches `claude` it adds `--settings <generated hooks file>` (see
  app\narrator\narrator.py). That file wires THIS script to claude's PreToolUse / PostToolUse /
  Notification / Stop / UserPromptSubmit events. claude pipes one event as JSON on stdin; this
  script appends it as a single line to the per-tab events file named by $env:SONELLE_NARRATE_FILE.
  The app's Python backend tails that file, turns each event into a humanised 3rd-person line, and
  (when the tab's voice toggle is on) speaks it aloud.

  Contract: must be FAST and NON-BLOCKING (claude waits on PreToolUse), must NEVER throw, and must
  ALWAYS exit 0 so it can never block or fail a tool call. If the env var is missing it is a no-op.
  Pure ASCII (house rule); the engine's selftest parses + ASCII-gates every .ps1.
#>
$ErrorActionPreference = 'SilentlyContinue'
try {
  $f = $env:SONELLE_NARRATE_FILE
  if (-not $f) { exit 0 }
  $in = [Console]::In.ReadToEnd()
  if ($in) {
    # collapse to one physical line so the Python tail can split on newlines (a single JSON event
    # may arrive pretty-printed). Bad/garbled lines are skipped tolerantly on the Python side.
    $line = ($in -replace '[\r\n]+', ' ').Trim()
    if ($line) { Add-Content -LiteralPath $f -Value $line -Encoding UTF8 }
  }
} catch {}
exit 0
