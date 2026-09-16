<#
  hook_probe.ps1 - capture REAL Claude Code hook payloads (development aid, not installed into a hub).

  Register it in a throwaway folder's .claude\settings.json on the events you want to learn, run one
  cheap `claude -p ... --model haiku` session in that folder, then read the JSONL it appends:

    { "type": "command",
      "command": "powershell -NoProfile -ExecutionPolicy Bypass -File <engine>\tools\hook_probe.ps1 -EventName PreToolUse" }

  Each line is  {"probe_event":"<EventName>","ts":"<iso>","payload":<the raw stdin JSON>}  so a single
  file can hold every event and the shapes stay comparable. It never blocks and never fails the call:
  ANY problem -> exit 0 with nothing captured (a probe must not break the session it observes).

  Params: -EventName  label written to probe_event (the payload's own hook_event_name is kept as-is).
          -Out        target file (default: $env:TEMP\sonelle\probe.jsonl).
          -Quiet      suppress the one-line stderr note.
  See docs\HOOK_PAYLOADS.md for what was captured and when.
#>
[CmdletBinding()]
param(
  [string]$EventName = '',
  [string]$Out = '',
  [switch]$Quiet
)
$ErrorActionPreference = 'SilentlyContinue'

try { $raw = (New-Object System.IO.StreamReader([Console]::OpenStandardInput(), [System.Text.Encoding]::UTF8)).ReadToEnd() } catch { $raw = '' }

$dest = $Out
if (-not $dest) { $dest = Join-Path (Join-Path $env:TEMP 'sonelle') 'probe.jsonl' }
try {
  $dir = Split-Path $dest -Parent
  if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
} catch { exit 0 }

# keep the payload verbatim when it is JSON (that is the whole point of the probe); otherwise embed it
# as a JSON string so the line still parses.
$payload = 'null'
if ($raw) {
  $t = $raw.Trim()
  $isJson = $false
  try { [void]($t | ConvertFrom-Json); $isJson = $true } catch { $isJson = $false }
  if ($isJson) { $payload = $t } else { $payload = (ConvertTo-Json $raw -Compress) }
}
$line = '{"probe_event":' + (ConvertTo-Json ([string]$EventName) -Compress) +
        ',"ts":' + (ConvertTo-Json ((Get-Date).ToString('o')) -Compress) +
        ',"payload":' + $payload + '}'

# several hooks can fire at once - retry briefly on a locked file, then give up quietly.
$enc = New-Object System.Text.UTF8Encoding($false)
for ($i = 0; $i -lt 10; $i++) {
  try { [System.IO.File]::AppendAllText($dest, $line + "`r`n", $enc); break }
  catch { Start-Sleep -Milliseconds 40 }
}
if (-not $Quiet) { try { [Console]::Error.WriteLine('sonelle probe: captured ' + $EventName) } catch {} }
exit 0
