<#
  _registry.ps1 - the ONE registry parser. Dot-source this; do not parse PROJECTS.md
  with ad-hoc regex anywhere else (that divergence caused the CRLF blind-spot bug).
  Line-ending agnostic: normalizes CRLF->LF before matching.

  Usage:
    . (Join-Path $PSScriptRoot '_registry.ps1')
    $projects = Get-SonelleProjects $registryPath   # array of {Short,Name,CodePath,Cells}
#>
function Get-SonelleProjects([string]$RegistryPath) {
  if (-not (Test-Path $RegistryPath)) { return @() }
  $txt = (Get-Content $RegistryPath -Raw) -replace "`r`n", "`n"
  $out = @()
  # [ \t]* (not \s*): \s matches newlines, so a malformed row with no closing pipe would "borrow" the
  # next line and be parsed as a bogus project. Keep each match on its own line (matches the line-based
  # Python parser in app\sonelle_gui.py - selftest section 9a asserts the two agree).
  foreach ($m in [regex]::Matches($txt, '(?m)^\|[ \t]*([a-z0-9_]+)[ \t]*\|(.*)$')) {
    $short = $m.Groups[1].Value
    if ($short -eq 'shortcode') { continue }
    $cells = @($m.Groups[2].Value.Split('|') | ForEach-Object { $_.Trim() })
    $out += [pscustomobject]@{
      Short    = $short
      Name     = if ($cells.Count -ge 1) { $cells[0] } else { '' }
      CodePath = if ($cells.Count -ge 2) { $cells[1] } else { '' }
      Cells    = $cells
    }
  }
  return $out
}

# A registry CodePath cell is either a real filesystem path or an "NA" sentinel the scaffolder writes
# when a project has no code dir yet (a leading '(' e.g. "(set later)" or '-'). ONE predicate answers
# "is this a real, usable path?" so the call sites (terminal, doctor, check_pointers, team) can't drift.
# A leading '-' would also make Test-Path treat it as a parameter, so this guard doubles as a safety net.
function Test-SonelleCodePath([string]$CodePath) {
  return ([bool]$CodePath) -and ($CodePath -notmatch '^[-(]')
}

# Resolve {Hub, MemoryDir} from sonelle.config.json + optional overrides. Precedence:
#   param override > config > default. An explicit -HubOverride means a DIFFERENT workspace,
#   so config.memoryDir (which describes the config's hub) does NOT apply to it - memory then
#   defaults to <override-hub>\memory unless -MemoryOverride is also given. This keeps the engine's
#   own config from leaking into a temp/other hub (e.g. selftest's throwaway hub).
function Get-SonelleConfig {
  param([string]$Engine, [string]$HubOverride = '', [string]$MemoryOverride = '')
  $cfgHub = ''; $cfgMem = ''; $cfgModels = $null
  # $env:SONELLE_CONFIG overrides the config path (power users + a hermetic selftest); else engine-root.
  $cfgFile = if ($env:SONELLE_CONFIG) { $env:SONELLE_CONFIG } else { Join-Path $Engine 'sonelle.config.json' }
  if (Test-Path $cfgFile) {
    try {
      $c = Get-Content $cfgFile -Raw | ConvertFrom-Json
      if ($c.hub -and $c.hub -ne '.') {
        $cfgHub = if ([System.IO.Path]::IsPathRooted($c.hub)) { $c.hub } else { Join-Path $Engine $c.hub }
      }
      if ($c.memoryDir) {
        $cfgMem = if ([System.IO.Path]::IsPathRooted($c.memoryDir)) { $c.memoryDir } else { Join-Path $Engine $c.memoryDir }
      }
      # raw model block (orchestrator* / lane*) so every caller resolves models from ONE parse, not its own.
      $cfgModels = $c.models
    } catch {
      # A malformed config must NOT silently relocate the whole workspace to the engine root - surface it
      # on the warning stream (so it never pollutes a function's stdout return) and fall back to defaults.
      Write-Warning ("sonelle: ignoring malformed config '{0}' - using defaults ({1})" -f $cfgFile, $_.Exception.Message)
    }
  }
  if ($HubOverride) {
    $hub = $HubOverride
    $mem = if ($MemoryOverride) { $MemoryOverride } else { [System.IO.Path]::Combine($hub, 'memory') }
  } else {
    $hub = if ($cfgHub) { $cfgHub } else { $Engine }
    $mem = if ($MemoryOverride) { $MemoryOverride } elseif ($cfgMem) { $cfgMem } else { [System.IO.Path]::Combine($hub, 'memory') }
  }
  return [pscustomobject]@{ Hub = $hub; MemoryDir = $mem; Models = $cfgModels }
}
