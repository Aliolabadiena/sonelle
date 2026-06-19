# sonelle SessionStart hook (project) - surface recent memory into context (recall as
# mechanism, not just a reminder). Output is added to the session context.
# This hook runs from <code>\.claude\hooks\. The memory index may live in the hub
# (<hub>\memory\MEMORY.md) or alongside the project; we probe a few known spots and the
# SONELLE_MEMORY env var (set by the terminal when it can), then fall back to a reminder.
$ErrorActionPreference = 'SilentlyContinue'
$candidates = @(
  $env:SONELLE_MEMORY,
  (Join-Path $PSScriptRoot '..\..\memory\MEMORY.md'),
  (Join-Path $PSScriptRoot '..\..\..\memory\MEMORY.md')
)
$mem = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if ($mem) {
  Write-Output '--- sonelle memory (recall before you start; verify each claim against current code) ---'
  Get-Content $mem -TotalCount 40 | ForEach-Object { Write-Output $_ }
  Write-Output '--- end memory --- capture new lessons after the task with tools/log_lesson.ps1.'
} else {
  Write-Output 'sonelle: no memory index found - skim this project memory before starting; capture lessons after with tools/log_lesson.ps1.'
}
exit 0
