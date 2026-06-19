# pretooluse_guard.ps1 - project safety net. Claude Code runs this BEFORE every Bash/Write/Edit
# (a PreToolUse hook). Exit 2 BLOCKS the call and shows the message to claude; exit 0 allows. This
# matters most in a bypassPermissions ("yolo") session, where it is the only thing standing between the
# agent and a destructive command. Out of the box it blocks force-pushes; add your own rules below.
# Robustness: ANY read/parse problem -> exit 0. A guard must never break a working session.
$ErrorActionPreference = 'SilentlyContinue'
# Claude streams the hook payload as UTF-8; read it as UTF-8 explicitly (PS 5.1's [Console]::In uses the
# console code page, which would corrupt any non-ASCII bytes in the payload).
try { $raw = (New-Object System.IO.StreamReader([Console]::OpenStandardInput(), [System.Text.Encoding]::UTF8)).ReadToEnd() } catch { exit 0 }
if (-not $raw) { exit 0 }
try { $j = $raw | ConvertFrom-Json } catch { exit 0 }
$tool = [string]$j.tool_name
$ti   = $j.tool_input
function Deny($msg) { [Console]::Error.WriteLine('guard: ' + $msg); exit 2 }

if ($tool -eq 'Bash') {
  $cmd = [string]$ti.command
  if (($cmd -match 'git\s+push') -and (($cmd -match '--force') -or ($cmd -match '(^|\s)-f(\s|$)'))) {
    Deny 'force-push rewrites published history - if you truly mean it, run it yourself.'
  }
  # --- add project-specific blocks here, e.g. refuse a destructive reset:
  # if ($cmd -match 'git\s+reset\s+--hard') { Deny 'refusing git reset --hard - stash instead.' }
}
# --- to guard file writes, inspect $ti.file_path / $ti.content / $ti.new_string and Deny as needed ---
exit 0
