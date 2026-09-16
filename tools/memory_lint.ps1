<#
  memory_lint.ps1 - lint a hub memory\ directory: dangling [[links]], a stale MEMORY.md index,
  size budgets and frontmatter hygiene. Report-only by default; -Fix repairs the mechanical ones.

  Usage:  .\memory_lint.ps1 [-MemoryDir <dir>] [-Fix]
          . .\memory_lint.ps1 -LibraryOnly       # dot-source: defines the parsers, runs nothing

  Checks (ISSUE = exit 1 unless -Fix repairs it; WARN = report only, never changes the exit code):
    ISSUE  [[link]] whose target file does not exist        -Fix -> "(link removed: name)"
    ISSUE  [[a-b]] that only resolves as a_b (or vice versa) -Fix -> rewritten to the real name
    ISSUE  MEMORY.md index line whose (file.md) is missing  -Fix -> the line is dropped
    WARN   memory file with no index line in MEMORY.md
    WARN   MEMORY.md over 200 lines / 25 KB, index line over 150 chars (docs budget)
    WARN   frontmatter: name: does not match the filename, or description:/type: missing

  Frontmatter "type:" is read both top-level and nested under "metadata:" (both shapes exist).
  Exit:   0 = no unfixed issues, 1 = at least one unfixed issue.
#>
param([string]$MemoryDir = '', [switch]$Fix, [switch]$LibraryOnly)
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Parsers. prune.ps1 dot-sources this file with -LibraryOnly so there is exactly
# ONE frontmatter/link parser in the engine (same rule as _registry.ps1).
# ---------------------------------------------------------------------------

# PS 5.1's Get-Content defaults to the ANSI code page, which would mangle the UTF-8
# memory files on a -Fix rewrite. Always read/write bytes as UTF-8 and keep the BOM as found.
function Read-SonelleText {
  param([string]$Path)
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  $bom = ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191)
  $enc = New-Object System.Text.UTF8Encoding($false)
  $txt = $enc.GetString($bytes)
  if ($bom -and $txt.Length -gt 0) { $txt = $txt.Substring(1) }
  return [pscustomobject]@{ Text = $txt; Bom = $bom }
}

function Write-SonelleText {
  param([string]$Path, [string]$Text, [bool]$Bom = $false)
  $enc = New-Object System.Text.UTF8Encoding($Bom)
  [System.IO.File]::WriteAllText($Path, $Text, $enc)
}

# Returns {Name, Description, Type} from a leading --- ... --- block. "type:" is accepted
# top-level AND indented under "metadata:"; "node_type:" must NOT be mistaken for it.
function Get-SonelleFrontmatter {
  param([string]$Text)
  $out = [pscustomobject]@{ Name = ''; Description = ''; Type = '' }
  if (-not $Text) { return $out }
  $t = $Text -replace "`r`n", "`n"
  $m = [regex]::Match($t, '^---\n(.*?)\n---', 'Singleline')
  if (-not $m.Success) { return $out }
  $fm = $m.Groups[1].Value
  $nm = [regex]::Match($fm, '(?m)^name:[ \t]*(.+?)[ \t]*$')
  if ($nm.Success) { $out.Name = $nm.Groups[1].Value.Trim().Trim('"').Trim("'") }
  $dm = [regex]::Match($fm, '(?m)^description:[ \t]*(.+?)[ \t]*$')
  if ($dm.Success) { $out.Description = $dm.Groups[1].Value.Trim().Trim('"').Trim("'") }
  $tm = [regex]::Match($fm, '(?m)^[ \t]*type:[ \t]*([A-Za-z0-9_\-]+)')
  if ($tm.Success) { $out.Type = $tm.Groups[1].Value.ToLower() }
  return $out
}

# Resolve a [[wiki link]] against the memory dir. Status: ok | variant | missing.
# "variant" = the exact spelling is not a file but the -/_ swapped spelling is.
function Resolve-SonelleMemoryLink {
  param([string]$Name, [string]$Dir)
  $base = ('' + $Name).Trim()
  if ($base -match '\|') { $base = ($base -split '\|')[0].Trim() }
  if ($base -match '#')  { $base = ($base -split '#')[0].Trim() }
  if (-not $base) { return [pscustomobject]@{ Status = 'missing'; File = '' } }
  $cands = @()
  foreach ($n in @($base, ($base -replace '-', '_'), ($base -replace '_', '-'))) {
    $f = $n
    if ($f -notmatch '(?i)\.md$') { $f = $f + '.md' }
    if ($cands -notcontains $f) { $cands += $f }
  }
  if (Test-Path -LiteralPath (Join-Path $Dir $cands[0])) {
    return [pscustomobject]@{ Status = 'ok'; File = $cands[0] }
  }
  foreach ($c in $cands) {
    if (Test-Path -LiteralPath (Join-Path $Dir $c)) { return [pscustomobject]@{ Status = 'variant'; File = $c } }
  }
  return [pscustomobject]@{ Status = 'missing'; File = $cands[0] }
}

function Get-SonelleMemoryFiles {
  param([string]$Dir)
  if (-not (Test-Path -LiteralPath $Dir -PathType Container)) { return @() }
  return @(Get-ChildItem -LiteralPath $Dir -Filter *.md -File | Sort-Object Name)
}

if ($LibraryOnly) { return }

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
$engine = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot '_registry.ps1')
$resolved = Get-SonelleConfig -Engine $engine -MemoryOverride $MemoryDir
$mem = $resolved.MemoryDir

$script:issues = 0; $script:fixes = 0; $script:warns = 0; $script:dangling = 0
function Add-Issue($msg) { Write-Host ("  [ISSUE] {0}" -f $msg) -ForegroundColor Red; $script:issues++ }
function Add-Fix($msg)   { Write-Host ("  [FIXED] {0}" -f $msg) -ForegroundColor Cyan; $script:fixes++ }
function Add-Warn($msg)  { Write-Host ("  [WARN ] {0}" -f $msg) -ForegroundColor Yellow; $script:warns++ }

$mode = 'report'
if ($Fix) { $mode = 'fix' }
Write-Host ("[lint] memory dir: {0} (mode: {1})" -f $mem, $mode)

if (-not (Test-Path -LiteralPath $mem -PathType Container)) {
  Write-Host ("  [WARN ] memory dir not found - nothing to lint") -ForegroundColor Yellow
  Write-Host ("[lint] DONE: 0 issue(s) (0 fixed), 1 warning(s), dangling links: 0")
  exit 0
}

$files = Get-SonelleMemoryFiles $mem

# --- per-file: [[links]] + frontmatter -------------------------------------
foreach ($f in $files) {
  $r = Read-SonelleText $f.FullName
  $txt = $r.Text
  $orig = $txt
  $names = @([regex]::Matches($txt, '\[\[([^\[\]\r\n]+)\]\]') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
  foreach ($n in $names) {
    $res = Resolve-SonelleMemoryLink -Name $n -Dir $mem
    if ($res.Status -eq 'ok') { continue }
    $token = '[[' + $n + ']]'
    if ($res.Status -eq 'missing') {
      $script:dangling++
      Add-Issue ("{0}: dangling link {1}" -f $f.Name, $token)
      if ($Fix) {
        $txt = $txt.Replace($token, ('(link removed: ' + $n + ')'))
        Add-Fix ("{0}: {1} -> (link removed: {2})" -f $f.Name, $token, $n)
      }
    } else {
      $good = '[[' + ($res.File -replace '(?i)\.md$', '') + ']]'
      Add-Issue ("{0}: link {1} does not match the file name - should be {2}" -f $f.Name, $token, $good)
      if ($Fix) {
        $txt = $txt.Replace($token, $good)
        Add-Fix ("{0}: {1} -> {2}" -f $f.Name, $token, $good)
      }
    }
  }
  if ($Fix -and $txt -ne $orig) { Write-SonelleText -Path $f.FullName -Text $txt -Bom $r.Bom }

  if ($f.Name -ne 'MEMORY.md') {
    $fm = Get-SonelleFrontmatter $orig
    if (-not $fm.Name) { Add-Warn ("{0}: frontmatter has no 'name:'" -f $f.Name) }
    # dashes and underscores are interchangeable in practice (dash-style name:, underscore filename),
    # so only a REAL divergence warns - otherwise the lint cries wolf on every file.
    elseif (($fm.Name -replace '-', '_') -ne ($f.BaseName -replace '-', '_')) { Add-Warn ("{0}: frontmatter name '{1}' does not match the filename" -f $f.Name, $fm.Name) }
    if (-not $fm.Description) { Add-Warn ("{0}: frontmatter has no 'description:'" -f $f.Name) }
    if (-not $fm.Type) { Add-Warn ("{0}: frontmatter has no 'type:' (top-level or under metadata:)" -f $f.Name) }
  }
}

# --- MEMORY.md index -------------------------------------------------------
$idx = Join-Path $mem 'MEMORY.md'
$referenced = @{}
if (-not (Test-Path -LiteralPath $idx)) {
  Add-Warn 'MEMORY.md index is missing'
} else {
  $ir = Read-SonelleText $idx
  $eol = "`n"
  if ($ir.Text -match "`r`n") { $eol = "`r`n" }
  $lines = ($ir.Text -replace "`r`n", "`n").Split("`n")
  $keep = New-Object System.Collections.ArrayList
  $long = New-Object System.Collections.ArrayList
  foreach ($ln in $lines) {
    $m = [regex]::Match($ln, '\]\(([^)\r\n]+\.md)\)')
    if (-not $m.Success) { [void]$keep.Add($ln); continue }
    $target = Split-Path $m.Groups[1].Value -Leaf
    $referenced[$target.ToLower()] = $true
    if (-not (Test-Path -LiteralPath (Join-Path $mem $target))) {
      Add-Issue ("MEMORY.md: index line points at a missing file ({0})" -f $target)
      if ($Fix) { Add-Fix ("MEMORY.md: dropped the index line for {0}" -f $target); continue }
    }
    if ($ln.Length -gt 150) { [void]$long.Add($ln) }
    [void]$keep.Add($ln)
  }
  # aggregated on purpose: one WARN per over-long line would drown the real findings.
  if ($long.Count -gt 0) {
    $longest = 0
    foreach ($l in $long) { if ($l.Length -gt $longest) { $longest = $l.Length } }
    $ex = @()
    foreach ($l in @($long | Select-Object -First 3)) {
      $h = $l
      if ($h.Length -gt 50) { $h = $h.Substring(0, 50) }
      $ex += ($h + '...')
    }
    Add-Warn ("MEMORY.md: {0} index line(s) over 150 chars (longest {1}); e.g. {2}" -f $long.Count, $longest, ($ex -join ' | '))
  }
  if ($Fix -and $keep.Count -ne $lines.Count) {
    Write-SonelleText -Path $idx -Text (($keep -join $eol)) -Bom $ir.Bom
  }
  if ($lines.Count -gt 200) { Add-Warn ("MEMORY.md: {0} lines (> 200) - split or prune the index" -f $lines.Count) }
  $bytes = (Get-Item -LiteralPath $idx).Length
  if ($bytes -gt 25600) { Add-Warn ("MEMORY.md: {0} bytes (> 25 KB) - split or prune the index" -f $bytes) }
  foreach ($f in $files) {
    if ($f.Name -eq 'MEMORY.md') { continue }
    if (-not $referenced.ContainsKey($f.Name.ToLower())) { Add-Warn ("{0}: no index line in MEMORY.md" -f $f.Name) }
  }
}

$unfixed = $script:issues - $script:fixes
Write-Host ("[lint] DONE: {0} issue(s) ({1} fixed), {2} warning(s), dangling links: {3}" -f $script:issues, $script:fixes, $script:warns, $script:dangling)
if ($unfixed -gt 0) { exit 1 } else { exit 0 }
