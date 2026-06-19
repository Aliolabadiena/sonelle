# pretooluse_guard.ps1 - engine-dev safety net. Claude Code runs this BEFORE every Bash/Write/Edit
# (a PreToolUse hook). Exit 2 BLOCKS the tool call and feeds the message back to claude; exit 0 allows.
# It turns the engine's invariants - which selftest and the terminal otherwise catch only AFTER the fact -
# into hard pre-blocks. That matters most in a bypassPermissions ("yolo") session, where claude's own
# prompts are skipped and this is the last line of defense. Enforced here:
#   - House rule: *.ps1 sources stay pure ASCII (PS 5.1 misreads non-ASCII in a no-BOM .ps1).
#   - Invariant #4: never scaffold hub/project state at the engine root - no new_project, no plain
#     log_lesson (only "log_lesson -Shared" -> knowledge/ is allowed), and no TODO/ledger/memory there.
#   - Do not force-push (rewrites published history).
# Robustness: ANY read/parse problem -> exit 0. A guard must never break a working session.
$ErrorActionPreference = 'SilentlyContinue'
# Claude streams the hook payload as UTF-8; read it as UTF-8 explicitly (PS 5.1's [Console]::In uses the
# console code page, which would corrupt non-ASCII bytes and defeat the ASCII gate below).
try { $raw = (New-Object System.IO.StreamReader([Console]::OpenStandardInput(), [System.Text.Encoding]::UTF8)).ReadToEnd() } catch { exit 0 }
if (-not $raw) { exit 0 }
try { $j = $raw | ConvertFrom-Json } catch { exit 0 }
$tool = [string]$j.tool_name
$ti   = $j.tool_input
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent   # .claude\hooks -> .claude -> engine root
function Deny($msg) { [Console]::Error.WriteLine('sonelle guard: ' + $msg); exit 2 }

if ($tool -eq 'Write' -or $tool -eq 'Edit') {
  $path = [string]$ti.file_path
  # house rule: pure-ASCII PowerShell (gate the text this call would add)
  if ($path -match '\.ps1$') {
    $text = if ($tool -eq 'Edit') { [string]$ti.new_string } else { [string]$ti.content }
    if ($text) {
      $bad = @($text.ToCharArray() | Where-Object { [int]$_ -gt 127 })
      if ($bad.Count -gt 0) {
        Deny ('this edit adds ' + $bad.Count + ' non-ASCII char(s) to ' + (Split-Path $path -Leaf) + ' - PowerShell sources must stay pure ASCII; build glyphs at runtime via [char] codepoints.')
      }
    }
  }
  # invariant #4: no hub state (TODO / ledger / memory) in the engine root
  $full = $path; try { $full = [System.IO.Path]::GetFullPath($path) } catch {}
  if (($full -like (Join-Path $root '*')) -and (($full -match '_TODO\.txt$') -or ($full -match '_run_STATUS\.md$') -or ($full -match '[\\/]memory[\\/]'))) {
    Deny 'hub state (TODO / ledger / memory) must never land in the engine root - this is a public engine, not a hub.'
  }
}
elseif ($tool -eq 'Bash') {
  $cmd = [string]$ti.command
  if ($cmd -match 'new_project\.ps1') { Deny 'invariant #4 - new_project scaffolds hub state; never run it at the engine root.' }
  if (($cmd -match 'log_lesson\.ps1') -and ($cmd -notmatch '-Shared')) { Deny 'invariant #4 - a plain log_lesson writes hub memory/; at the engine root only "log_lesson -Shared" (knowledge/) is allowed.' }
  if (($cmd -match 'git\s+push') -and (($cmd -match '--force') -or ($cmd -match '(^|\s)-f(\s|$)'))) { Deny 'force-push rewrites published history - if you truly mean it, run it yourself outside the agent.' }
}
exit 0
