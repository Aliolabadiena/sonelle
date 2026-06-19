<#
  build_plugin.ps1 - (re)generate the Claude Code PLUGIN under plugin\ from the canonical skills in
  templates\skills. The plugin packages sonelle's reusable SKILLS so anyone can install them into
  their own Claude Code via the marketplace (.claude-plugin\marketplace.json at the repo root)
  WITHOUT cloning the engine. The terminal / dispatcher / GUI are NOT plugin-able (they run outside
  claude); skills are the portable layer - which is exactly what a plugin is for.

  templates\skills is the SINGLE SOURCE OF TRUTH; this just mirrors it into the plugin layout, and
  selftest section 12 rebuilds into a temp dir and diffs, so the committed plugin can never drift.

  Usage:
    tools\build_plugin.ps1           rebuild plugin\
    tools\build_plugin.ps1 -Out X    build into X (selftest builds into a temp dir to diff)
#>
[CmdletBinding()]
param([string]$Out = '')
$ErrorActionPreference = 'Stop'
$engine = Split-Path $PSScriptRoot -Parent
if (-not $Out) { $Out = Join-Path $engine 'plugin' }
$skillsSrc = Join-Path $engine 'templates\skills'
if (-not (Test-Path $skillsSrc)) { Write-Host "[X] no templates\skills to package" -ForegroundColor Red; exit 1 }

function Write-Utf8($p, $t) { [System.IO.File]::WriteAllText($p, $t, (New-Object System.Text.UTF8Encoding($false))) }

if (Test-Path $Out) { Remove-Item $Out -Recurse -Force }
New-Item -ItemType Directory -Path (Join-Path $Out '.claude-plugin') -Force | Out-Null
Copy-Item $skillsSrc (Join-Path $Out 'skills') -Recurse -Force

# manifest: name is the only required field. [ordered] so the JSON is deterministic (no-drift diff).
$manifest = [ordered]@{
  name        = 'sonelle-skills'
  description = 'Reusable Claude Code skills from the sonelle engine: systematic-debugging, verification-before-completion, plan-before-build, frontend-design, design-review, accessibility-audit. Model-invocable - they auto-load when a task matches.'
}
Write-Utf8 (Join-Path $Out '.claude-plugin\plugin.json') ($manifest | ConvertTo-Json -Depth 5)

$n = @(Get-ChildItem (Join-Path $Out 'skills') -Directory).Count
Write-Host "[+] built plugin at $Out ($n skills)"
