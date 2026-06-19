<#
  repomap.ps1 - a cheap STRUCTURAL map of a codebase: each source file with its top-level symbols
  (functions / classes / types), so an assistant can grasp a large repo without reading every file.
  Pure PowerShell, regex-based - a fast PRIMER, not an exact parser (no tree-sitter dependency).

  Usage:
    tools\repomap.ps1 -Path C:\code\proj              print the map
    tools\repomap.ps1 -Path C:\code\proj -Out map.md  also write it to a file
    tools\repomap.ps1 -Path . -Top 12 -MaxFiles 80    tune how much is shown
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true, Position = 0)][string]$Path,
  [string]$Out = '',
  [int]$Top = 10,
  [int]$MaxFiles = 60
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path $Path)) { Write-Host "[X] path not found: $Path" -ForegroundColor Red; exit 1 }
$root = (Resolve-Path $Path).Path

# dirs we never descend into (build output, deps, vcs, sonelle's own config)
$skipDir = @('.git', 'node_modules', '.venv', 'venv', 'env', 'dist', 'build', 'out', 'target', 'bin', 'obj', '__pycache__', '.next', '.nuxt', '.svelte-kit', 'coverage', '.idea', '.vs', 'vendor', '.claude', '.cache')

# JS/TS family: functions, classes, exported arrow consts, and (TS) interfaces / types / enums
$jsPat = '^\s*(export\s+)?(default\s+)?(async\s+)?(function\*?|class)\s+\w+|^\s*(export\s+)?(const|let|var)\s+[A-Za-z0-9_$]+\s*=\s*(async\s*)?(\(|function|[A-Za-z0-9_$]+\s*=>)'
$tsPat = $jsPat + '|^\s*(export\s+)?(declare\s+)?(abstract\s+)?(interface|type|enum)\s+\w+'
# broad fallback for other languages: a definition keyword at the start of a line
$defPat = '^\s*(export\s+|public\s+|private\s+|protected\s+|internal\s+|static\s+|pub\s+|abstract\s+|final\s+|async\s+|open\s+|override\s+|default\s+)*(function|func|fn|def|class|interface|struct|enum|trait|type|module|namespace|record|object|sub|proc)\b'

$patByExt = @{
  '.ps1' = '^\s*function\s+[\w-]+'; '.psm1' = '^\s*function\s+[\w-]+'
  '.py' = '^\s*(async\s+def|def|class)\s+\w+'
  '.js' = $jsPat; '.jsx' = $jsPat; '.mjs' = $jsPat; '.cjs' = $jsPat
  '.ts' = $tsPat; '.tsx' = $tsPat
}
$codeExt = @('.ps1', '.psm1', '.py', '.js', '.jsx', '.mjs', '.cjs', '.ts', '.tsx', '.go', '.rs', '.rb', '.php', '.java', '.kt', '.scala', '.swift', '.cs', '.cpp', '.cc', '.hpp', '.c', '.h', '.lua', '.sh', '.sql', '.vue', '.svelte')

function Clean-Sig($line) {
  $s = $line.Trim()
  $s = $s -replace '\s*\{\s*$', ''     # drop a trailing opening brace
  $s = $s -replace '\s+', ' '          # collapse whitespace
  if ($s.Length -gt 100) { $s = $s.Substring(0, 97) + '...' }
  return $s
}

# pruning walk: descend the tree but never into a $skipDir, collecting code-file paths
$files = New-Object System.Collections.Generic.List[string]
$stack = New-Object System.Collections.Stack
$stack.Push($root)
while ($stack.Count -gt 0) {
  $d = $stack.Pop()
  $entries = $null; try { $entries = [System.IO.Directory]::GetFileSystemEntries($d) } catch { continue }
  foreach ($e in $entries) {
    if ([System.IO.Directory]::Exists($e)) {
      if ($skipDir -notcontains (Split-Path $e -Leaf)) { $stack.Push($e) }
    } elseif ($codeExt -contains [System.IO.Path]::GetExtension($e).ToLower()) {
      $files.Add($e)
    }
  }
}

$results = @()
foreach ($f in $files) {
  $ext = [System.IO.Path]::GetExtension($f).ToLower()
  $pat = if ($patByExt.ContainsKey($ext)) { $patByExt[$ext] } else { $defPat }
  $syms = @()
  try {
    foreach ($line in [System.IO.File]::ReadLines($f)) {
      if ($line.Length -gt 400) { continue }       # skip minified / data lines
      if ($line -match $pat) { $syms += (Clean-Sig $line) }
    }
  } catch { continue }
  if ($syms.Count -gt 0) {
    $results += [pscustomobject]@{ Rel = $f.Substring($root.Length).TrimStart('\', '/'); Count = $syms.Count; Syms = $syms }
  }
}

$results = @($results | Sort-Object Count -Descending)
$shown = if ($results.Count -gt $MaxFiles) { @($results[0..($MaxFiles - 1)]) } else { $results }
$totalSyms = ($results | Measure-Object Count -Sum).Sum; if (-not $totalSyms) { $totalSyms = 0 }

$lines = @()
$lines += "# Repo map: $root"
$lines += ("# {0} source files with symbols, {1} symbols total. Structural regex primer (not exact)." -f $results.Count, $totalSyms)
if ($results.Count -gt $MaxFiles) { $lines += ("# (showing the top {0} files by symbol count)" -f $MaxFiles) }
$lines += ''
foreach ($r in $shown) {
  $lines += ("{0}  ({1})" -f $r.Rel, $r.Count)
  $take = if ($r.Syms.Count -gt $Top) { @($r.Syms[0..($Top - 1)]) } else { $r.Syms }
  foreach ($s in $take) { $lines += ("  - " + $s) }
  if ($r.Syms.Count -gt $Top) { $lines += ("  ... +{0} more" -f ($r.Syms.Count - $Top)) }
}
$text = ($lines -join "`r`n") + "`r`n"
if ($Out) { [System.IO.File]::WriteAllText($Out, $text, (New-Object System.Text.UTF8Encoding($false))) }
Write-Host $text
