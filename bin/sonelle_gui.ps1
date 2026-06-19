<#
  sonelle_gui.ps1 - launch the sonelle liquid-glass desktop app (Python / pywebview).

  Ensures a local .venv with pywebview + pywinpty (installs on first run), then starts the
  GUI with pythonw.exe (no console window). The terminal brain (bin\sonelle.ps1) runs INSIDE
  the app through a hidden pseudo-terminal (pywinpty) and is rendered by xterm.js - so what you
  type goes to a real PowerShell running behind the scenes. The classic WinForms host still
  lives in bin\sonelle_app.ps1 as a fallback.

  Usage:  powershell -File bin\sonelle_gui.ps1            ensure deps, then open the app
          powershell -File bin\sonelle_gui.ps1 -NoLaunch  ensure deps only (used by selftest)
  Source is pure ASCII.
#>
[CmdletBinding()]
param([switch]$NoLaunch)
$ErrorActionPreference = 'Stop'
$root  = Split-Path $PSScriptRoot -Parent
$venv  = Join-Path $root '.venv'
$py    = Join-Path $venv 'Scripts\python.exe'
$pyw   = Join-Path $venv 'Scripts\pythonw.exe'
$req   = Join-Path $root 'app\requirements.txt'
$appPy = Join-Path $root 'app\sonelle_gui.py'

if (-not (Test-Path $appPy)) { Write-Host "[X] app not found: $appPy" -ForegroundColor Red; exit 1 }

if (-not (Test-Path $py)) {
  # find a base Python to bootstrap the venv (prefer the py launcher, then python on PATH)
  $basePy = $null; $baseArgs = @()
  $g = Get-Command py -ErrorAction SilentlyContinue
  if ($g) { $basePy = $g.Source; $baseArgs = @('-3') }
  else { $g = Get-Command python -ErrorAction SilentlyContinue; if ($g) { $basePy = $g.Source } }
  if (-not $basePy) {
    Write-Host '[!] Python not found. Install Python 3.10+ from https://www.python.org/downloads/' -ForegroundColor Yellow
    Write-Host '    (tick "Add python.exe to PATH" during setup), then run this again.' -ForegroundColor Yellow
    exit 1
  }
  Write-Host 'sonelle: first run - creating .venv and installing pywebview + pywinpty (one time)...'
  & $basePy @baseArgs -m venv $venv
  if (-not (Test-Path $py)) { Write-Host '[X] venv creation failed.' -ForegroundColor Red; exit 1 }
  & $py -m pip install --quiet --upgrade pip
  & $py -m pip install --quiet -r $req
}

# verify the two deps import; (re)install once if not
& $py -c 'import webview, winpty' 2>$null
if ($LASTEXITCODE -ne 0) {
  Write-Host 'sonelle: installing app dependencies...'
  & $py -m pip install --quiet -r $req
  & $py -c 'import webview, winpty' 2>$null
  if ($LASTEXITCODE -ne 0) { Write-Host '[X] could not install pywebview / pywinpty.' -ForegroundColor Red; exit 1 }
}

if ($NoLaunch) { Write-Host 'sonelle: app dependencies OK.'; exit 0 }

# Best-effort: install the high-quality LOCAL neural voice (Kokoro) for the narrator. This is
# OPTIONAL and must NEVER be fatal - if it can't install, the narrator falls back to edge-tts and
# then the Windows SAPI voice, so the app still launches. Only attempt it when it isn't already
# importable (so a working install isn't reinstalled on every launch). Skipped under -NoLaunch above
# so the selftest deps check stays fast.
$voiceReq = Join-Path $root 'app\requirements-voice.txt'
if (Test-Path $voiceReq) {
  # Probe under 'Continue' EAP: a FAILED import (kokoro not installed yet) writes a traceback to
  # stderr, and under the script's 'Stop' EAP PS 5.1 would escalate that to a terminating error and
  # abort the launch. Localize it so the probe can only ever set $LASTEXITCODE.
  $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  & $py -c 'import kokoro_onnx' 1>$null 2>$null
  $haveKokoro = ($LASTEXITCODE -eq 0)
  $ErrorActionPreference = $eap
  if (-not $haveKokoro) {
    # Install in the BACKGROUND (detached) so the window opens NOW - the narrator just falls back to
    # edge-tts / SAPI until the runtime lands, then uses Kokoro automatically. Never blocks the launch.
    # NOTE: only the small kokoro-onnx RUNTIME installs here - the voice MODEL is vendored in app\voice\.
    Write-Host 'sonelle: installing the Kokoro voice runtime in the background - optional, one time...'
    try { Start-Process -FilePath $py -ArgumentList @('-m','pip','install','--quiet','-r',$voiceReq) -WindowStyle Hidden | Out-Null } catch {}
  }
}

# launch the GUI detached, no console window (pythonw). The app owns the hidden PTYs.
Start-Process -FilePath $pyw -ArgumentList @($appPy) -WorkingDirectory (Join-Path $root 'app') | Out-Null
