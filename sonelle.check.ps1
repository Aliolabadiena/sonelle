<#
  sonelle.check.ps1 - the engine's own health check (the doctor hook for sonelle itself).
  Runs the full self-test. Use this as the model for your projects' sonelle.check.ps1.
#>
& (Get-Process -Id $PID).Path -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'tools\selftest.ps1')
exit $LASTEXITCODE
