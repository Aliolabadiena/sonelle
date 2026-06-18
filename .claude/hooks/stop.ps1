# luna engine Stop hook - validate registry pointers after each task. Always exit 0 (non-blocking).
$ErrorActionPreference = 'SilentlyContinue'
$chk = Join-Path $PSScriptRoot '..\..\tools\check_pointers.ps1'
if (Test-Path $chk) {
  & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File $chk
}
exit 0
