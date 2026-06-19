<#
  new_project.ps1 - scaffold a new project with the standard sonelle skeleton.
  Hub = the sonelle workspace (parent of this tools/ folder).

  Usage:
    .\new_project.ps1 -Short <short> -Name "<name>" -Path "<path\to\code>"
    .\new_project.ps1 demo "Demo Project" "C:\code\demo"

  Creates (UTF-8, no BOM):
    <hub>\<SHORT_UPPER>_TODO.txt      tasks + state header
    <hub>\_<short>_run_STATUS.md      run ledger
    <Path>\CLAUDE.md                  project onboarding
    <hub>\memory\project_<short>.md   memory file (+ memory\MEMORY.md index line)
    + a row in <hub>\PROJECTS.md       registry
  Idempotent: if the shortcode is already registered it stops without overwriting.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true, Position = 0)][string]$Short,
  [Parameter(Mandatory = $true, Position = 1)][string]$Name,
  [Parameter(Mandatory = $true, Position = 2)][string]$Path,
  [string]$Hub = ''
)

$ErrorActionPreference = 'Stop'
$engine     = Split-Path $PSScriptRoot -Parent           # engine assets (templates) always live here
$hub        = if ($Hub) { $Hub } else { $engine }        # workspace where registry/state/memory live
$tpl        = Join-Path $engine 'templates'
$memDir     = Join-Path $hub 'memory'
$projects   = Join-Path $hub 'PROJECTS.md'
$date       = (Get-Date).ToString('yyyy-MM-dd')
$shortUpper = $Short.ToUpper()

function Write-Utf8($p, $t) { [System.IO.File]::WriteAllText($p, $t, (New-Object System.Text.UTF8Encoding($false))) }
function Fill($t) {
  return $t.Replace('{{SHORT}}', $Short).Replace('{{SHORT_UPPER}}', $shortUpper).Replace('{{NAME}}', $Name).Replace('{{PATH}}', $Path).Replace('{{DATE}}', $date)
}

if ($Short -notmatch '^[a-z0-9_]+$') { Write-Host "[X] Shortcode must be a-z 0-9 _ only (got '$Short')." -ForegroundColor Red; exit 1 }
if (-not (Test-Path $tpl))      { Write-Host "[X] templates folder not found: $tpl" -ForegroundColor Red; exit 1 }
if (-not (Test-Path $projects)) { Write-Host "[X] registry not found: $projects" -ForegroundColor Red; exit 1 }

# duplicate guard
$registry = [System.IO.File]::ReadAllText($projects)
if ($registry -match ('(?m)^\|\s*' + [regex]::Escape($Short) + '\s*\|')) {
  Write-Host "[!] Shortcode '$Short' already in PROJECTS.md - stopping (nothing changed)." -ForegroundColor Yellow; exit 1
}

# ensure memory dir + index
if (-not (Test-Path $memDir)) { New-Item -ItemType Directory -Path $memDir -Force | Out-Null }
$memIndex = Join-Path $memDir 'MEMORY.md'
if (-not (Test-Path $memIndex)) { Write-Utf8 $memIndex "# Memory index" }

# create code dir
if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null; Write-Host "[+] created code dir: $Path" }

# write skeleton
$todoFile   = Join-Path $hub ($shortUpper + '_TODO.txt')
$statusFile = Join-Path $hub ('_' + $Short + '_run_STATUS.md')
$claudeFile = Join-Path $Path 'CLAUDE.md'
$memFile    = Join-Path $memDir ('project_' + $Short + '.md')

Write-Utf8 $todoFile   (Fill ([System.IO.File]::ReadAllText((Join-Path $tpl 'TODO.template.txt'))));        Write-Host "[+] $todoFile"
Write-Utf8 $statusFile (Fill ([System.IO.File]::ReadAllText((Join-Path $tpl 'run_STATUS.template.md'))));   Write-Host "[+] $statusFile"
Write-Utf8 $claudeFile (Fill ([System.IO.File]::ReadAllText((Join-Path $tpl 'CLAUDE.template.md'))));       Write-Host "[+] $claudeFile"
Write-Utf8 $memFile    (Fill ([System.IO.File]::ReadAllText((Join-Path $tpl 'project_memory.template.md')))); Write-Host "[+] $memFile"

# project hooks (Stop -> heal/check + lesson reminder; SessionStart -> recall) + a starter health check
$hooksDir = Join-Path $Path '.claude\hooks'
if (-not (Test-Path $hooksDir)) { New-Item -ItemType Directory -Path $hooksDir -Force | Out-Null }
Copy-Item (Join-Path $tpl 'settings.template.json')   (Join-Path $Path '.claude\settings.json')   -Force
Copy-Item (Join-Path $tpl 'hooks\session_start.ps1')  (Join-Path $hooksDir 'session_start.ps1')   -Force
Copy-Item (Join-Path $tpl 'hooks\stop.ps1')           (Join-Path $hooksDir 'stop.ps1')            -Force
Write-Host "[+] $Path\.claude\settings.json (+ hooks)"
$check = Join-Path $Path 'sonelle.check.ps1'
$checkBody = @'
# sonelle.check.ps1 - health check for {{NAME}}. Auto-detects a common test/build command.
# Exit 0 = healthy, 1 = failing, 2 = NOT configured (no checks found - replace this with REAL checks).
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Push-Location $here
try {
  if (Test-Path (Join-Path $here 'package.json')) {
    $pkg = Get-Content (Join-Path $here 'package.json') -Raw | ConvertFrom-Json
    if ($pkg.scripts -and $pkg.scripts.test) { npm test; exit $LASTEXITCODE }
  }
  if ((Test-Path (Join-Path $here 'pyproject.toml')) -or (Test-Path (Join-Path $here 'pytest.ini'))) {
    python -m pytest -q; exit $LASTEXITCODE
  }
  if (Get-ChildItem $here -Filter *.csproj -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1) {
    dotnet test; exit $LASTEXITCODE
  }
  if (Test-Path (Join-Path $here 'Cargo.toml')) { cargo test;    exit $LASTEXITCODE }
  if (Test-Path (Join-Path $here 'go.mod'))     { go test ./...; exit $LASTEXITCODE }
  Write-Output '[{{SHORT}}] sonelle.check.ps1 is a placeholder - no test command detected. Add real checks.'
  exit 2
} finally { Pop-Location }
'@
Write-Utf8 $check (Fill $checkBody)
Write-Host "[+] $check (auto-detecting starter)"

# memory index line (clean append)
$idxLine = "- [$Name ($Short)](project_$Short.md) - new project ($date); state {{U}}_TODO.txt + ledger".Replace('{{U}}', $shortUpper)
$exIdx = ([System.IO.File]::ReadAllText($memIndex) -replace "`r`n", "`n").TrimEnd("`n")
Write-Utf8 $memIndex ($exIdx + "`n" + $idxLine + "`n")
Write-Host "[+] memory\MEMORY.md index line added"

# registry row (clean append, attaches under the table)
$row = "| $Short | $Name | $Path | yes | {{U}}_TODO.txt + _{{S}}_run_STATUS.md + memory/project_{{S}}.md | (fill in) |".Replace('{{U}}', $shortUpper).Replace('{{S}}', $Short)
$exReg = ([System.IO.File]::ReadAllText($projects) -replace "`r`n", "`n").TrimEnd("`n")
Write-Utf8 $projects ($exReg + "`n" + $row + "`n")
Write-Host "[+] PROJECTS.md registry row added"

Write-Host ""
Write-Host "OK - '$Short' ($Name) created. Open it: $Short`: <prompt>" -ForegroundColor Green
