<#
  prune.ps1 - archive stale hub state so memory + ledgers stop growing forever.
  DRY-RUN BY DEFAULT: it prints what it would do and changes nothing until -Apply.
  It NEVER deletes: everything moves under <hub>\_archive\.

  Usage:  .\prune.ps1 [-Hub <path>] [-MemoryDir <dir>] [-Days 90] [-Apply] [-LedgerKB 40]

  Rules:
    memory  type: project, untouched for more than -Days, and whose shortcode is NOT in
            PROJECTS.md (or whose registry row is marked closed / uzdarytas) -> _archive\memory\.
            type: feedback|user is NEVER auto-archived (listed as "review" past 2x -Days).
    ledger  <hub>\_*_run_STATUS.md over -LedgerKB: sections older than -Days that contain no
            RESUME move to _archive\ledger\<name>_<yyyy-MM>.md; a one-line pointer stays on top.
            The last 3 sections in file order and the 3 newest by date are never touched.
    todo    <hub>\*_TODO.txt: reports how many [x] lines there are. No automatic changes.
  Always writes <hub>\.claude\sonelle_prune_stamp (dry-run too) and finishes by running
  tools\memory_lint.ps1 (-Fix when -Apply, so index lines for archived files are dropped).

  Exit:   0 (report tool - a candidate is not a failure).
#>
param([string]$Hub = '', [string]$MemoryDir = '', [int]$Days = 90, [switch]$Apply, [int]$LedgerKB = 40)
$ErrorActionPreference = 'Stop'

# Capture the parameters BEFORE dot-sourcing memory_lint.ps1: dot-sourcing a script that has a
# param() block creates ITS parameter variables ($MemoryDir, $Fix, $LibraryOnly) in THIS scope,
# which would silently clobber ours. Everything below uses the $p* copies.
$pHub      = $Hub
$pMem      = $MemoryDir
$pDays     = $Days
$pApply    = [bool]$Apply
$pLedgerKB = $LedgerKB

$engine = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot '_registry.ps1')
$lintPath = Join-Path $PSScriptRoot 'memory_lint.ps1'
. $lintPath -LibraryOnly

$resolved = Get-SonelleConfig -Engine $engine -HubOverride $pHub -MemoryOverride $pMem
$hub = $resolved.Hub
$mem = $resolved.MemoryDir

# "closed" in a registry Project cell. The Lithuanian spelling carries a z-caron (U+017E), and this
# file must stay pure ASCII - so the glyph is built at runtime (engine invariant #1).
$closedRe = 'closed|uzdarytas|u' + [char]0x017E + 'darytas'

$cutoff    = (Get-Date).AddDays(-$pDays)
$reviewCut = (Get-Date).AddDays(-2 * $pDays)
$archMemDir = Join-Path $hub '_archive\memory'
$archLedDir = Join-Path $hub '_archive\ledger'

$mode = 'dry-run'
if ($pApply) { $mode = 'apply' }
Write-Host ("[prune] hub: {0}" -f $hub)
# An explicit -Hub makes memory default to <hub>\memory (see Get-SonelleConfig). A real hub often keeps
# memory elsewhere (sonelle.config.json memoryDir), and a silent "no memory dir - skipped" prune would
# look like a clean hub. Fall back to the configured dir, loudly, when <hub>\memory does not exist.
if ($pHub -and -not $pMem -and -not (Test-Path -LiteralPath $mem -PathType Container)) {
  $cfgMem = (Get-SonelleConfig -Engine $engine).MemoryDir
  if ($cfgMem -and (Test-Path -LiteralPath $cfgMem -PathType Container)) {
    Write-Host ("[prune] NOTE: {0} does not exist - using the configured memory dir instead (pass -MemoryDir to override)" -f $mem) -ForegroundColor Yellow
    $mem = $cfgMem
  }
}
Write-Host ("[prune] memory dir: {0} | older than {1} days | mode: {2}" -f $mem, $pDays, $mode)

# ---------------------------------------------------------------------------
# registry
# ---------------------------------------------------------------------------
$reg = @{}
$pf = Join-Path $hub 'PROJECTS.md'
if (Test-Path -LiteralPath $pf) {
  foreach ($p in (Get-SonelleProjects $pf)) { $reg[$p.Short.ToLower()] = $p }
} else {
  Write-Host ("  [WARN ] no PROJECTS.md at {0} - every project memory counts as unregistered; not archiving anything" -f $hub) -ForegroundColor Yellow
}
$haveRegistry = (Test-Path -LiteralPath $pf)

# ---------------------------------------------------------------------------
# memory
# ---------------------------------------------------------------------------
Write-Host "[prune] memory:"
$memArchive = @()
$memReview  = 0
if (-not (Test-Path -LiteralPath $mem -PathType Container)) {
  Write-Host "  (no memory dir - skipped)"
} else {
  foreach ($f in (Get-ChildItem -LiteralPath $mem -Filter *.md -File | Sort-Object Name)) {
    if ($f.Name -eq 'MEMORY.md') { continue }
    $type = (Get-SonelleFrontmatter (Read-SonelleText $f.FullName).Text).Type
    $age = [int]((Get-Date) - $f.LastWriteTime).TotalDays
    if ($type -eq 'feedback' -or $type -eq 'user') {
      if ($f.LastWriteTime -lt $reviewCut) {
        $memReview++
        Write-Host ("  [REVIEW ] {0} ({1} d, type: {2}) - never auto-archived; re-read it yourself" -f $f.Name, $age, $type)
      }
      continue
    }
    if ($type -ne 'project') { continue }
    if ($f.LastWriteTime -ge $cutoff) { continue }
    if (-not $haveRegistry) { continue }
    $short = ''
    $nm = [regex]::Match($f.BaseName, '^project_(.+)$')
    if ($nm.Success) { $short = $nm.Groups[1].Value.ToLower() }
    if (-not $short) {
      Write-Host ("  [KEEP   ] {0} ({1} d) - cannot map the filename to a registry shortcode" -f $f.Name, $age)
      continue
    }
    $row = $null
    if ($reg.ContainsKey($short)) { $row = $reg[$short] }
    $reason = ''
    if (-not $row) { $reason = 'not in PROJECTS.md' }
    elseif ($row.Name -match $closedRe) { $reason = 'registry row marked closed' }
    if ($reason) {
      $memArchive += $f
      Write-Host ("  [ARCHIVE] {0} ({1} d, type: project) - {2}" -f $f.Name, $age, $reason)
    }
  }
  if ($memArchive.Count -eq 0 -and $memReview -eq 0) { Write-Host "  (nothing stale)" }
}

# ---------------------------------------------------------------------------
# ledgers
# ---------------------------------------------------------------------------

# Split a ledger into blocks at "## " / "### " headings. Real ledgers keep the run log one level
# deeper than the fixed "## Facts / ## Gotchas / ## Runs" scaffolding, so the level that actually
# carries dated sections is detected instead of assumed.
function Get-SonelleLedgerBlocks {
  param([string]$Text)
  $t = $Text -replace "`r`n", "`n"
  $lines = $t.Split("`n")
  $pre = New-Object System.Collections.ArrayList
  $blocks = New-Object System.Collections.ArrayList
  $cur = $null
  foreach ($ln in $lines) {
    $m = [regex]::Match($ln, '^(#{2,3})[ \t]+\S')
    if ($m.Success) {
      if ($cur) { [void]$blocks.Add($cur) }
      $cur = [pscustomobject]@{ Level = $m.Groups[1].Value.Length; Header = $ln; Lines = (New-Object System.Collections.ArrayList) }
      [void]$cur.Lines.Add($ln)
    } elseif ($cur) {
      [void]$cur.Lines.Add($ln)
    } else {
      [void]$pre.Add($ln)
    }
  }
  if ($cur) { [void]$blocks.Add($cur) }
  foreach ($b in $blocks) {
    $body = ($b.Lines -join "`n")
    $dm = [regex]::Match($body, '\d{4}-\d{2}-\d{2}')
    $d = ''
    if ($dm.Success) { $d = $dm.Value }
    $b | Add-Member -NotePropertyName Date -NotePropertyValue $d
    $b | Add-Member -NotePropertyName HasResume -NotePropertyValue ([bool]($body -match 'RESUME'))
  }
  return [pscustomobject]@{ Preamble = @($pre); Blocks = @($blocks) }
}

function Get-SonelleSectionDate {
  param([string]$Date)
  if (-not $Date) { return $null }
  try { return [datetime]::ParseExact($Date, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture) } catch { return $null }
}

Write-Host "[prune] ledgers:"
$ledgerSections = 0
$ledgerFiles = 0
$ledgerPlan = @()
foreach ($lf in @(Get-ChildItem -LiteralPath $hub -Filter '_*_run_STATUS.md' -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
  $kb = [int]($lf.Length / 1024)
  if ($lf.Length -le ($pLedgerKB * 1024)) { continue }
  $raw = Read-SonelleText $lf.FullName
  $parsed = Get-SonelleLedgerBlocks $raw.Text
  $lvl2 = @($parsed.Blocks | Where-Object { $_.Level -eq 2 -and $_.Date })
  $lvl3 = @($parsed.Blocks | Where-Object { $_.Level -eq 3 -and $_.Date })
  $level = 2
  if ($lvl3.Count -gt $lvl2.Count) { $level = 3 }
  $sections = @($parsed.Blocks | Where-Object { $_.Level -eq $level })
  for ($i = 0; $i -lt $sections.Count; $i++) { $sections[$i] | Add-Member -NotePropertyName Idx -NotePropertyValue $i -Force }
  $keepIdx = @{}
  for ($i = [Math]::Max(0, $sections.Count - 3); $i -lt $sections.Count; $i++) { $keepIdx[$i] = $true }
  foreach ($b in @($sections | Where-Object { $_.Date } | Sort-Object Date -Descending | Select-Object -First 3)) { $keepIdx[$b.Idx] = $true }
  $cands = @()
  foreach ($s in $sections) {
    if ($keepIdx.ContainsKey($s.Idx)) { continue }
    if ($s.HasResume) { continue }
    $d = Get-SonelleSectionDate $s.Date
    if (-not $d) { continue }
    if ($d -ge $cutoff) { continue }
    $cands += $s
  }
  Write-Host ("  [{0}] {1} KB, {2} section(s) at level {3}, {4} archivable" -f $lf.Name, $kb, $sections.Count, ('#' * $level), $cands.Count)
  foreach ($c in $cands) {
    $h = $c.Header
    if ($h.Length -gt 90) { $h = $h.Substring(0, 90) }
    Write-Host ("    -> {0}" -f $h)
  }
  if ($cands.Count -gt 0) {
    $ledgerFiles++
    $ledgerSections += $cands.Count
    $ledgerPlan += [pscustomobject]@{ File = $lf; Raw = $raw; Parsed = $parsed; Level = $level; Cands = $cands }
  }
}
if ($ledgerPlan.Count -eq 0) { Write-Host ("  (no ledger over {0} KB with archivable sections)" -f $pLedgerKB) }

# ---------------------------------------------------------------------------
# TODO files (report only)
# ---------------------------------------------------------------------------
Write-Host "[prune] todo:"
$todoDone = 0
$todoFiles = @(Get-ChildItem -LiteralPath $hub -Filter '*_TODO.txt' -File -ErrorAction SilentlyContinue | Sort-Object Name)
foreach ($tf in $todoFiles) {
  $n = @([regex]::Matches((Read-SonelleText $tf.FullName).Text, '(?m)^[ \t]*[-*]?[ \t]*\[[xX]\]')).Count
  $todoDone += $n
  if ($n -gt 0) { Write-Host ("  {0}: {1} done line(s)" -f $tf.Name, $n) }
}
if ($todoFiles.Count -eq 0) { Write-Host "  (no *_TODO.txt in the hub)" }

# ---------------------------------------------------------------------------
# apply
# ---------------------------------------------------------------------------
$movedMem = 0
$movedSections = 0
if ($pApply) {
  if ($memArchive.Count -gt 0) {
    New-Item -ItemType Directory -Path $archMemDir -Force | Out-Null
    foreach ($f in $memArchive) {
      $dest = Join-Path $archMemDir $f.Name
      if (Test-Path -LiteralPath $dest) { $dest = Join-Path $archMemDir ($f.BaseName + '_' + (Get-Date -Format 'yyyyMMddHHmmss') + '.md') }
      Move-Item -LiteralPath $f.FullName -Destination $dest
      $movedMem++
      Write-Host ("  [MOVED  ] {0} -> {1}" -f $f.Name, $dest)
    }
  }
  foreach ($plan in $ledgerPlan) {
    New-Item -ItemType Directory -Path $archLedDir -Force | Out-Null
    $eol = "`n"
    if ($plan.Raw.Text -match "`r`n") { $eol = "`r`n" }
    $base = [System.IO.Path]::GetFileNameWithoutExtension($plan.File.Name)
    $targets = @()
    foreach ($grp in ($plan.Cands | Group-Object -Property { $_.Date.Substring(0, 7) } | Sort-Object Name)) {
      $outFile = Join-Path $archLedDir ($base + '_' + $grp.Name + '.md')
      $chunk = @()
      foreach ($s in $grp.Group) { $chunk += ($s.Lines -join $eol) }
      $body = ($chunk -join $eol)
      if (Test-Path -LiteralPath $outFile) {
        $prev = (Read-SonelleText $outFile).Text
        Write-SonelleText -Path $outFile -Text ($prev.TrimEnd() + $eol + $eol + $body + $eol)
      } else {
        $head = ('# archived from ' + $plan.File.Name + ' (' + $grp.Name + ') - moved by tools\prune.ps1 on ' + (Get-Date -Format 'yyyy-MM-dd'))
        Write-SonelleText -Path $outFile -Text ($head + $eol + $eol + $body + $eol)
      }
      $targets += ('_archive\ledger\' + (Split-Path $outFile -Leaf))
      $movedSections += @($grp.Group).Count
    }
    $removed = @{}
    foreach ($c in $plan.Cands) { $removed[$c.Idx] = $true }
    $outLines = New-Object System.Collections.ArrayList
    foreach ($l in $plan.Parsed.Preamble) { [void]$outLines.Add($l) }
    foreach ($b in $plan.Parsed.Blocks) {
      if ($b.Level -eq $plan.Level -and $removed.ContainsKey($b.Idx)) { continue }
      foreach ($l in $b.Lines) { [void]$outLines.Add($l) }
    }
    $shown = $targets
    if ($shown.Count -gt 3) { $shown = @($targets[0], $targets[1], $targets[2]) + @('+' + ($targets.Count - 3) + ' more') }
    $ptr = ('(archived: ' + @($plan.Cands).Count + ' sections -> ' + ($shown -join ', ') + ')')
    $insertAt = 0
    if ($outLines.Count -gt 0 -and ('' + $outLines[0]) -match '^#[ \t]') { $insertAt = 1 }
    $outLines.Insert($insertAt, $ptr)
    Write-SonelleText -Path $plan.File.FullName -Text (($outLines -join $eol)) -Bom $plan.Raw.Bom
    Write-Host ("  [SPLIT  ] {0}: {1} section(s) -> {2}" -f $plan.File.Name, @($plan.Cands).Count, ($targets -join ', '))
  }
}

# ---------------------------------------------------------------------------
# stamp + lint
# ---------------------------------------------------------------------------
$stampDir = Join-Path $hub '.claude'
New-Item -ItemType Directory -Path $stampDir -Force | Out-Null
$stampFile = Join-Path $stampDir 'sonelle_prune_stamp'
Write-SonelleText -Path $stampFile -Text ((Get-Date -Format 'yyyy-MM-ddTHH:mm:ss') + ' mode=' + $mode + "`n")

Write-Host "[prune] memory lint:"
$psExe = (Get-Process -Id $PID).Path
$lintArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $lintPath, '-MemoryDir', $mem)
if ($pApply) { $lintArgs += '-Fix' }
$lintOut = @()
try { $lintOut = @(& $psExe $lintArgs) } catch { $lintOut = @('[lint] could not run: ' + $_.Exception.Message) }
foreach ($l in $lintOut) { Write-Host ("  " + $l) }

Write-Host ""
Write-Host ("[prune] memory: {0} archive candidate(s), 0 feedback archived, {1} review (feedback/user)" -f $memArchive.Count, $memReview)
Write-Host ("[prune] ledger: {0} section(s) in {1} file(s) over {2} KB" -f $ledgerSections, $ledgerFiles, $pLedgerKB)
Write-Host ("[prune] todo: {0} done line(s) in {1} file(s)" -f $todoDone, $todoFiles.Count)
Write-Host ("[prune] stamp: {0}" -f $stampFile)
if ($pApply) {
  Write-Host ("[prune] DONE (apply): moved {0} memory file(s) + {1} ledger section(s) into {2} - nothing deleted." -f $movedMem, $movedSections, (Join-Path $hub '_archive')) -ForegroundColor Green
} else {
  Write-Host "[prune] DONE (dry-run): nothing moved. Re-run with -Apply to move the listed items." -ForegroundColor Green
}
exit 0
