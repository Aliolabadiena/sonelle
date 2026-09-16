<#
  install_hub.ps1 - install (or remove) the sonelle ENFORCEMENT layer in a hub.

  A hub is the folder where CLAUDE.md + PROJECTS.md + the state files live. This copies
  templates\hub\hooks\*.ps1 into <hub>\.claude\hooks\, merges templates\hub\settings.json into
  <hub>\.claude\settings.json (hooks only - `permissions` and anything else you have there is left
  exactly as it was), and copies the slash commands (templates\hub\commands\, with `<engine>` and `<hub>`
  filled in) and the review-only subagents (templates\agents\) when those exist.

  Usage:
    .\install_hub.ps1 -Hub <path>                  install / refresh (idempotent)
    .\install_hub.ps1 -Hub <path> -Canary "Name," -Owner "Name"
                                                   also write <hub>\.claude\sonelle.hub.json:
                                                   canary = the word every reply must start with (Stop hook;
                                                   empty/absent = off), owner = how a block message names you
    .\install_hub.ps1 -Hub <path> -Uninstall       remove exactly what was installed
  Exit: 0 ok, 1 error.

  Idempotent by construction: every install first strips the hook entries that point at sonelle hook
  files, then appends the current set - so running it twice yields the same settings.json. What was
  written is recorded in <hub>\.claude\sonelle.install.json, and -Uninstall removes that list (files it
  would overwrite are backed up to *.pre-sonelle.bak first, so nothing of yours is destroyed).
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$Hub,
  [switch]$Uninstall,
  [string]$Canary,
  [string]$Owner,
  [switch]$Quiet
)
$ErrorActionPreference = 'Stop'

$engine   = Split-Path $PSScriptRoot -Parent
$tplDir   = Join-Path $engine 'templates\hub'
$hookNames = @('prompt_router.ps1', 'hold_guard.ps1', 'main_agent_guard.ps1', 'reviewer_guard.ps1', 'stop_guard.ps1')
# OURS = a command that points at <hub>\.claude\hooks\<one of our names>. Anchoring on the full path
# matters: a bare-filename match would also strip a hook of YOUR OWN whose name merely CONTAINS one of
# ours (`.claude/hooks/my_stop_guard.ps1`) or the same name under a different dir (`tools/hooks/...`),
# and -Uninstall could never give it back.
$ourHookRx = '(?i)\.claude[\\/]hooks[\\/](' + (($hookNames | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')(\s|[\x22\x27]|$)'
$u8 = New-Object System.Text.UTF8Encoding($false)

function Say([string]$msg, [string]$color = 'Gray') { if (-not $Quiet) { Write-Host $msg -ForegroundColor $color } }
function Fail([string]$msg) { Write-Host ('[install_hub] ' + $msg) -ForegroundColor Red; exit 1 }

if (-not (Test-Path $Hub)) { Fail ('hub not found: ' + $Hub) }
$hubFull = (Resolve-Path $Hub).Path
if ($hubFull.TrimEnd('\') -eq $engine.TrimEnd('\')) { Fail 'the engine is not a hub - point -Hub at your workspace folder (invariant #4).' }

$claudeDir  = Join-Path $hubFull '.claude'
$settings   = Join-Path $claudeDir 'settings.json'
$manifestPath = Join-Path $claudeDir 'sonelle.install.json'

# --- JSON helpers ----------------------------------------------------------------------------------
function ConvertTo-HashTree($obj) {
  if ($null -eq $obj) { return $null }
  if ($obj -is [System.Management.Automation.PSCustomObject]) {
    $h = [ordered]@{}
    foreach ($p in $obj.PSObject.Properties) { $h[$p.Name] = ConvertTo-HashTree $p.Value }
    return $h
  }
  if (($obj -is [System.Collections.IEnumerable]) -and ($obj -isnot [string])) {
    $a = @(); foreach ($i in $obj) { $a += , (ConvertTo-HashTree $i) }; return , $a
  }
  return $obj
}
function Read-JsonTree([string]$path) {
  if (-not (Test-Path $path)) { return [ordered]@{} }
  $txt = Get-Content $path -Raw
  if (-not $txt.Trim()) { return [ordered]@{} }
  try { return (ConvertTo-HashTree ($txt | ConvertFrom-Json)) }
  catch { Fail ('cannot parse ' + $path + ' - fix or move it first; refusing to overwrite a settings file I cannot read.') }
}
function Write-JsonTree($tree, [string]$path) {
  $json = ($tree | ConvertTo-Json -Depth 20)
  [System.IO.File]::WriteAllText($path, ($json + "`r`n"), $u8)
}
function Test-OurEntry($entry) {
  if ($null -eq $entry) { return $false }
  $hooks = $entry['hooks']
  if (-not $hooks) { return $false }
  foreach ($h in @($hooks)) {
    if (([string]$h['command']) -match $ourHookRx) { return $true }
  }
  return $false
}
function Remove-OurHooks($tree) {
  if (-not $tree.Contains('hooks')) { return $tree }
  $hooks = $tree['hooks']
  if (-not $hooks) { return $tree }
  foreach ($evt in @($hooks.Keys)) {
    $kept = @(@($hooks[$evt]) | Where-Object { -not (Test-OurEntry $_) })
    if ($kept.Count -eq 0) { $hooks.Remove($evt) } else { $hooks[$evt] = $kept }
  }
  if ($hooks.Count -eq 0) { $tree.Remove('hooks') }
  return $tree
}

# --- uninstall -------------------------------------------------------------------------------------
if ($Uninstall) {
  if (-not (Test-Path $claudeDir)) { Say 'nothing to uninstall (no .claude in the hub)' 'Yellow'; exit 0 }
  $files = @()
  if (Test-Path $manifestPath) {
    try { $mf = Get-Content $manifestPath -Raw | ConvertFrom-Json; $files = @($mf.files) } catch { $files = @() }
  }
  if ($files.Count -eq 0) { $files = @($hookNames | ForEach-Object { 'hooks/' + $_ }) }
  $removed = 0
  foreach ($rel in $files) {
    $p = Join-Path $claudeDir ($rel -replace '/', '\')
    if (Test-Path $p) { Remove-Item $p -Force; $removed++ }
  }
  if (Test-Path $settings) {
    $tree = Read-JsonTree $settings
    $tree = Remove-OurHooks $tree
    Write-JsonTree $tree $settings
  }
  if (Test-Path $manifestPath) { Remove-Item $manifestPath -Force }
  foreach ($d in @('hooks', 'commands', 'agents')) {
    $dp = Join-Path $claudeDir $d
    if ((Test-Path $dp) -and (@(Get-ChildItem $dp -Force).Count -eq 0)) { Remove-Item $dp -Recurse -Force }
  }
  Say ('[install_hub] uninstalled: ' + $removed + ' file(s) removed, hook entries stripped from settings.json') 'Green'
  Say '  (sonelle.hub.json and the prune stamp were left alone - delete them by hand if you want them gone)'
  exit 0
}

# --- install ---------------------------------------------------------------------------------------
if (-not (Test-Path $tplDir)) { Fail ('missing ' + $tplDir + ' - is this the sonelle engine?') }
foreach ($d in @($claudeDir, (Join-Path $claudeDir 'hooks'))) {
  if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}

$prev = @()
if (Test-Path $manifestPath) {
  try { $pm = Get-Content $manifestPath -Raw | ConvertFrom-Json; $prev = @($pm.files) } catch { $prev = @() }
}
$written = @()
function Copy-Managed([string]$src, [string]$relTarget) {
  $dst = Join-Path $claudeDir ($relTarget -replace '/', '\')
  $dir = Split-Path $dst -Parent
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  if ((Test-Path $dst) -and ($script:prev -notcontains $relTarget)) {
    if ((Get-Content $dst -Raw) -ne (Get-Content $src -Raw)) {
      Copy-Item $dst ($dst + '.pre-sonelle.bak') -Force
      Say ('  backed up existing ' + $relTarget + ' -> ' + $relTarget + '.pre-sonelle.bak') 'Yellow'
    }
  }
  Copy-Item $src $dst -Force
  $script:written += $relTarget
}
# slash commands ship with <engine> / <hub> placeholders; the installer is the only place that knows
# both, so it fills them in - otherwise /prune tells the session to guess where sonelle is checked out.
function Copy-Templated([string]$src, [string]$relTarget) {
  $dst = Join-Path $claudeDir ($relTarget -replace '/', '\')
  $dir = Split-Path $dst -Parent
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  $txt = (Get-Content $src -Raw).Replace('<engine>', $engine).Replace('<hub>', $hubFull)
  if ((Test-Path $dst) -and ($script:prev -notcontains $relTarget)) {
    if ((Get-Content $dst -Raw) -ne $txt) {
      Copy-Item $dst ($dst + '.pre-sonelle.bak') -Force
      Say ('  backed up existing ' + $relTarget + ' -> ' + $relTarget + '.pre-sonelle.bak') 'Yellow'
    }
  }
  [System.IO.File]::WriteAllText($dst, $txt, $u8)
  $script:written += $relTarget
}

foreach ($n in $hookNames) {
  $src = Join-Path $tplDir ('hooks\' + $n)
  if (-not (Test-Path $src)) { Fail ('missing hook template: ' + $src) }
  Copy-Managed $src ('hooks/' + $n)
}
# owned by other parts of the engine - copied when present, never created here
$cmdDir = Join-Path $tplDir 'commands'
if (Test-Path $cmdDir) {
  foreach ($f in (Get-ChildItem $cmdDir -File)) { Copy-Templated $f.FullName ('commands/' + $f.Name) }
}
$agentDir = Join-Path $engine 'templates\agents'
if (Test-Path $agentDir) {
  foreach ($f in (Get-ChildItem $agentDir -File)) { Copy-Managed $f.FullName ('agents/' + $f.Name) }
}

# merge hooks into the hub settings.json (permissions and everything else untouched)
$tpl  = Read-JsonTree (Join-Path $tplDir 'settings.json')
$tree = Read-JsonTree $settings
$tree = Remove-OurHooks $tree
if (-not $tree.Contains('hooks')) { $tree['hooks'] = [ordered]@{} }
$hooks = $tree['hooks']
foreach ($evt in $tpl['hooks'].Keys) {
  $cur = @()
  if ($hooks.Contains($evt)) { $cur = @($hooks[$evt]) }
  $hooks[$evt] = @($cur + @($tpl['hooks'][$evt]))
}
Write-JsonTree $tree $settings

if ($PSBoundParameters.ContainsKey('Canary') -or $PSBoundParameters.ContainsKey('Owner')) {
  $hubCfgPath = Join-Path $claudeDir 'sonelle.hub.json'
  $hubCfg = Read-JsonTree $hubCfgPath
  if ($PSBoundParameters.ContainsKey('Canary')) { $hubCfg['canary'] = $Canary; Say ('  canary set: "' + $Canary + '" -> .claude\sonelle.hub.json') }
  if ($PSBoundParameters.ContainsKey('Owner'))  { $hubCfg['owner']  = $Owner;  Say ('  owner set:  "' + $Owner + '" (how the guards address you in a block message)') }
  Write-JsonTree $hubCfg $hubCfgPath
}

$manifest = [ordered]@{
  tool      = 'sonelle install_hub'
  installed = (Get-Date).ToString('o')
  files     = @($written)
}
Write-JsonTree $manifest $manifestPath

Say ('[install_hub] installed into ' + $hubFull) 'Green'
Say ('  hooks:    ' + ($hookNames -join ', '))
Say ('  settings: ' + $settings + ' (hooks merged; permissions untouched)')
Say ('  files:    ' + $written.Count + ' recorded in .claude\sonelle.install.json')
if (-not (Test-Path (Join-Path $claudeDir 'sonelle.hub.json'))) {
  Say '  note: no .claude\sonelle.hub.json - the Stop-hook canary check stays OFF until you add {"canary":"..."}.'
}
exit 0
