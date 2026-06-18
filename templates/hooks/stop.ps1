# sonelle Stop hook (project) - HEAL detect + SELF-IMPROVE reminder after each task.
# Runs this project's sonelle.check.ps1 (if present) and nudges to capture lessons. Always exit 0
# (non-blocking; never loops).
$ErrorActionPreference = 'SilentlyContinue'
$chk = Join-Path $PSScriptRoot '..\..\sonelle.check.ps1'
if (Test-Path $chk) {
  & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File $chk
} else {
  Write-Output 'sonelle: no sonelle.check.ps1 in this project - add real health checks (see sonelle docs/HEAL.md).'
}
Write-Output 'sonelle: if you learned something this task (gotcha/feedback/dead-end), capture it via tools/log_lesson.ps1.'
exit 0
