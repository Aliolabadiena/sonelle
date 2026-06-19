<#
  cost.ps1 - estimate Claude Code token usage + cost for sonelle projects by reading Claude Code's
  OWN local session transcripts (~/.claude/projects/<encoded-cwd>/*.jsonl). No API key and no
  network: it just sums the usage Claude Code already recorded on disk. Dollar figures are
  ESTIMATES from the editable price table below (list prices per 1,000,000 tokens) - good for
  budgeting, NOT billing. Edit the table when prices change.

  Usage:
    tools\cost.ps1                  every registered project + the engine
    tools\cost.ps1 -Short myproj    one project
    tools\cost.ps1 -Days 7          only sessions touched in the last 7 days
#>
[CmdletBinding()]
param([string]$Short = '', [int]$Days = 0, [string]$Hub = '')

$ErrorActionPreference = 'Stop'
$engine = Split-Path $PSScriptRoot -Parent
. (Join-Path $engine 'tools\_registry.ps1')
$resolved = Get-SonelleConfig -Engine $engine -HubOverride $Hub
$hub = $resolved.Hub

# price table: USD per 1,000,000 tokens. cache-write counts as 1.25x input, cache-read as 0.1x input.
# list prices, approximate - matched by a substring of the model id. Edit freely.
$prices = @(
  @{ key = 'opus';   inp = 15.0; outp = 75.0 },
  @{ key = 'sonnet'; inp = 3.0;  outp = 15.0 },
  @{ key = 'haiku';  inp = 1.0;  outp = 5.0 }
)
function Get-Price($model) {
  foreach ($p in $prices) { if ($model -like ('*' + $p.key + '*')) { return $p } }
  return @{ key = 'other'; inp = 0.0; outp = 0.0 }   # unknown model: tokens still counted, cost 0
}

# the per-cwd transcript folder name is the code path with : \ / all turned into '-'.
# overridable via env for a hermetic selftest (mirrors SONELLE_CONFIG).
$projRoot = if ($env:SONELLE_CLAUDE_PROJECTS) { $env:SONELLE_CLAUDE_PROJECTS } else { Join-Path $env:USERPROFILE '.claude\projects' }

function Measure-Cwd($name, $codePath) {
  $enc = ($codePath -replace '[:\\/]', '-')
  $dir = Join-Path $projRoot $enc
  $row = [ordered]@{ Name = $name; Found = (Test-Path $dir); Sessions = 0; In = [int64]0; Out = [int64]0; Cache = [int64]0; Usd = 0.0 }
  if ($row.Found) {
    $files = @(Get-ChildItem $dir -Filter *.jsonl -File -ErrorAction SilentlyContinue)
    if ($Days -gt 0) { $cut = (Get-Date).AddDays(-$Days); $files = @($files | Where-Object { $_.LastWriteTime -ge $cut }) }
    foreach ($f in $files) {
      $row.Sessions++
      foreach ($line in [System.IO.File]::ReadLines($f.FullName)) {
        if ($line -notmatch '"usage"') { continue }
        $o = $null; try { $o = $line | ConvertFrom-Json } catch { continue }
        $u = $o.message.usage; if (-not $u) { $u = $o.usage }
        if (-not $u) { continue }
        $inp = [int64]($u.input_tokens); $outp = [int64]($u.output_tokens)
        $cw  = [int64]($u.cache_creation_input_tokens); $cr = [int64]($u.cache_read_input_tokens)
        $row.In += $inp; $row.Out += $outp; $row.Cache += ($cw + $cr)
        $mdl = if ($o.message.model) { $o.message.model } else { $o.model }
        $pr = Get-Price ([string]$mdl)
        $row.Usd += (($inp * $pr.inp) + ($outp * $pr.outp) + ($cw * $pr.inp * 1.25) + ($cr * $pr.inp * 0.1)) / 1000000.0
      }
    }
  }
  return [pscustomobject]$row
}

# build the work list: one project, or all projects in the registry + the engine itself
$projects = Get-SonelleProjects (Join-Path $hub 'PROJECTS.md')
$targets = @()
if ($Short) {
  $p = $projects | Where-Object { $_.Short -eq $Short.ToLower() } | Select-Object -First 1
  if (-not $p) { Write-Host "[X] shortcode '$Short' is not in the registry." -ForegroundColor Red; exit 1 }
  $targets += @{ Name = $p.Short; Path = $p.CodePath }
} else {
  foreach ($p in $projects) { $targets += @{ Name = $p.Short; Path = $p.CodePath } }
  $targets += @{ Name = '(engine)'; Path = $engine }
}

$rows = @()
foreach ($t in $targets) { if ($t.Path) { $rows += (Measure-Cwd $t.Name $t.Path) } }

# report (ASCII table). token counts get thousands separators; USD to 4 dp (an estimate).
$fmt = '{0,-14} {1,8} {2,13} {3,13} {4,15} {5,12}'
$hdr = $fmt -f 'project', 'sessions', 'input', 'output', 'cache', 'est USD'
Write-Host $hdr
Write-Host ('-' * $hdr.Length)
$tIn = [int64]0; $tOut = [int64]0; $tCache = [int64]0; $tUsd = 0.0; $any = $false
foreach ($r in $rows) {
  if (-not $r.Found) {
    Write-Host ($fmt -f $r.Name, '-', 'no transcript', '', '', '')
    continue
  }
  $any = $true
  Write-Host ($fmt -f $r.Name, $r.Sessions, ('{0:N0}' -f $r.In), ('{0:N0}' -f $r.Out), ('{0:N0}' -f $r.Cache), ('$' + ('{0:N4}' -f $r.Usd)))
  $tIn += $r.In; $tOut += $r.Out; $tCache += $r.Cache; $tUsd += $r.Usd
}
if ($any) {
  Write-Host ('-' * $hdr.Length)
  Write-Host ($fmt -f 'TOTAL', '', ('{0:N0}' -f $tIn), ('{0:N0}' -f $tOut), ('{0:N0}' -f $tCache), ('$' + ('{0:N4}' -f $tUsd)))
}
Write-Host ''
Write-Host '(estimate from local transcripts; edit the price table in cost.ps1 for current rates)' -ForegroundColor DarkGray
