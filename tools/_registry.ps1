<#
  _registry.ps1 - the ONE registry parser. Dot-source this; do not parse PROJECTS.md
  with ad-hoc regex anywhere else (that divergence caused the CRLF blind-spot bug).
  Line-ending agnostic: normalizes CRLF->LF before matching.

  Usage:
    . (Join-Path $PSScriptRoot '_registry.ps1')
    $projects = Get-LunaProjects $registryPath   # array of {Short,Name,CodePath,Cells}
#>
function Get-LunaProjects([string]$RegistryPath) {
  if (-not (Test-Path $RegistryPath)) { return @() }
  $txt = (Get-Content $RegistryPath -Raw) -replace "`r`n", "`n"
  $out = @()
  foreach ($m in [regex]::Matches($txt, '(?m)^\|\s*([a-z0-9_]+)\s*\|(.*)$')) {
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
