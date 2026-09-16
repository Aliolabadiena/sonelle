<#
  selftest.d\prune.ps1 - covers tools\memory_lint.ps1 + tools\prune.ps1 (v1.47).
  Dot-sourced by tools\selftest.ps1 with $engine, $tmp and the Ok helper already defined.
  Also runnable STANDALONE:  powershell -NoProfile -ExecutionPolicy Bypass -File tools\selftest.d\prune.ps1
  (the fallbacks below supply $engine / $tmp / $ps / Ok and print their own summary).

  Fixture: a throwaway hub with a memory dir (dangling links, a stale CLOSED project, a live
  project, fresh feedback, an old user note, an oversize index line, one index line whose target
  is gone), a >40 KB ledger with dated sections (one carrying RESUME), a small ledger that must
  stay untouched, and a TODO file. Proves: the lint counts + -Fix; check_pointers fails ONLY on a
  dangling link; prune dry-run changes nothing; -Apply moves (never deletes) and keeps the last 3
  ledger sections, the newest ones and RESUME; the stamp is written; a second run is clean.
#>

# ---- standalone fallbacks (no-ops when dot-sourced by selftest.ps1) ----
$prStandalone = $false
if (-not (Get-Command Ok -ErrorAction SilentlyContinue)) {
  $prStandalone = $true
  $script:fail = 0
  $script:pass = 0
  function Ok($label, $cond) {
    if ($cond) { Write-Host ("  [PASS] {0}" -f $label) -ForegroundColor Green; $script:pass++ }
    else { Write-Host ("  [FAIL] {0}" -f $label) -ForegroundColor Red; $script:fail++ }
  }
}
if (-not $engine) { $engine = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }
if (-not $ps)     { $ps = (Get-Process -Id $PID).Path }
if (-not $tmp)    { $tmp = Join-Path $env:TEMP 'sonelle_selftest' }
if (-not (Test-Path $tmp)) { New-Item -ItemType Directory -Path $tmp -Force | Out-Null }

Write-Host "== prune. memory lint + prune (archive, never delete) =="

function PrnWrite($path, $text) {
  [System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($false)))
}
function PrnAge($path, $days) {
  (Get-Item -LiteralPath $path).LastWriteTime = (Get-Date).AddDays(-$days)
}
function PrnRun($file, $argsArr) {
  $out = @(& $ps -NoProfile -ExecutionPolicy Bypass -File $file @argsArr 2>&1)
  return [pscustomobject]@{ Text = ($out -join "`n"); Code = $LASTEXITCODE }
}

$lintPs  = Join-Path $engine 'tools\memory_lint.ps1'
$prunePs = Join-Path $engine 'tools\prune.ps1'
$chkPs   = Join-Path $engine 'tools\check_pointers.ps1'
Ok "memory_lint.ps1 exists" (Test-Path $lintPs)
Ok "prune.ps1 exists"       (Test-Path $prunePs)

# ---------------------------------------------------------------------------
# fixture
# ---------------------------------------------------------------------------
$case = Join-Path $tmp 'prune_case'
if (Test-Path $case) { Remove-Item $case -Recurse -Force }
$mem = Join-Path $case 'memory'
New-Item -ItemType Directory -Path $mem -Force | Out-Null

Copy-Item (Join-Path $engine 'CLAUDE.md') (Join-Path $case 'CLAUDE.md') -Force
$reg = @(
  '# Projects registry (selftest fixture)',
  '',
  '| Shortcode | Project | Code path | Git | State sources (read FIRST) | Keys / notes |',
  '|---|---|---|---|---|---|',
  '| live | Live Proj | (set later) | no | LIVE_TODO.txt + _live_run_STATUS.md | - |',
  '| stale | Stale Proj (CLOSED) | (set later) | no | STALE_TODO.txt + _stale_run_STATUS.md | - |'
) -join "`n"
PrnWrite (Join-Path $case 'PROJECTS.md') $reg

PrnWrite (Join-Path $mem 'project_stale.md') @"
---
name: project_stale
description: closed project memory
metadata:
  type: project
---

Stale notes. Background lives in [[nope_missing]].
"@
PrnWrite (Join-Path $mem 'project_live.md') @"
---
name: project_live
description: live project memory
type: project
---

Live project notes.
"@
PrnWrite (Join-Path $mem 'feedback_keep.md') @"
---
name: feedback_keep
description: a standing rule
metadata:
  type: feedback
---

Standing rule. Related: [[also_missing]].
"@
PrnWrite (Join-Path $mem 'user_old.md') @"
---
name: user_old
description: an old user preference
metadata:
  type: user
---

An old preference nobody has touched in a year.
"@
$longLine = '- [Very long index line](feedback_keep.md) - ' + ('x' * 140)
$idxLines = @(
  '- [Stale proj](project_stale.md) - closed project memory',
  '- [Live proj](project_live.md) - live project memory',
  '- [Keep this](feedback_keep.md) - standing rule',
  '- [User pref](user_old.md) - old preference',
  '- [Ghost](project_ghost.md) - target file does not exist',
  $longLine
) -join "`n"
PrnWrite (Join-Path $mem 'MEMORY.md') $idxLines

PrnWrite (Join-Path $case 'STALE_TODO.txt') "- [x] done one`n- [ ] not done`n- [x] done two`n"

# ledger: 8 dated sections at '### ', >40 KB. Section 3 carries RESUME; the last 3 are recent.
$filler = ((1..120 | ForEach-Object { '  padding line that only exists to push this ledger over the size gate, nothing to see here.' }) -join "`n")
$recent = @((Get-Date).AddDays(-7).ToString('yyyy-MM-dd'), (Get-Date).AddDays(-6).ToString('yyyy-MM-dd'), (Get-Date).AddDays(-5).ToString('yyyy-MM-dd'))
$ledParts = @(
  '# Stale Proj - run ledger',
  '',
  '## Fixed facts',
  '- Code: (none)',
  '',
  '## Gotchas',
  '- none yet',
  '',
  '## Runs',
  '',
  ('### 2024-01-05 - run one' + "`n" + $filler),
  ('### 2024-02-05 - run two' + "`n" + $filler),
  ('### 2024-03-05 - run three' + "`n" + 'RESUME: pick this one up first.' + "`n" + $filler),
  ('### 2024-04-05 - run four' + "`n" + $filler),
  ('### 2024-05-05 - run five' + "`n" + $filler),
  ('### ' + $recent[0] + ' - run six' + "`n" + $filler),
  ('### ' + $recent[1] + ' - run seven' + "`n" + $filler),
  ('### ' + $recent[2] + ' - run eight' + "`n" + $filler)
)
$ledger = Join-Path $case '_stale_run_STATUS.md'
PrnWrite $ledger (($ledParts -join "`n") + "`n")
$smallLedger = Join-Path $case '_live_run_STATUS.md'
PrnWrite $smallLedger ("# Live Proj - run ledger`n`n## Runs`n`n### 2024-01-09 - ancient but small`nnothing much`n")
$smallBefore = (Get-Content $smallLedger -Raw)
Ok "fixture ledger is over the 40 KB gate" ((Get-Item $ledger).Length -gt (40 * 1024))

foreach ($f in @('project_stale.md', 'project_live.md')) { PrnAge (Join-Path $mem $f) 200 }
PrnAge (Join-Path $mem 'user_old.md') 400
PrnAge (Join-Path $mem 'feedback_keep.md') 1

# ---------------------------------------------------------------------------
# lint: report -> check_pointers -> fix -> report
# ---------------------------------------------------------------------------
$l1 = PrnRun $lintPs @('-MemoryDir', $mem)
Ok "lint exits 1 on issues"                 ($l1.Code -eq 1)
Ok "lint finds exactly 3 issues"            ($l1.Text -match '3 issue\(s\)')
Ok "lint counts 2 dangling links"           ($l1.Text -match 'dangling links: 2')
Ok "lint names the dangling link"           ($l1.Text -match 'dangling link \[\[nope_missing\]\]')
Ok "lint flags the stale index line"        ($l1.Text -match 'project_ghost\.md')
Ok "lint warns on the oversize index line"  ($l1.Text -match 'MEMORY\.md: 1 index line\(s\) over 150 chars')
Ok "lint changes nothing without -Fix"      (((Get-Content (Join-Path $mem 'project_stale.md') -Raw) -match '\[\[nope_missing\]\]') -and ((Get-Content (Join-Path $mem 'MEMORY.md') -Raw) -match 'project_ghost\.md'))

$c1 = PrnRun $chkPs @('-Hub', $case, '-MemoryDir', $mem)
Ok "check_pointers fails on a dangling link"      ($c1.Code -eq 1)
Ok "check_pointers explains the lint MISS"        ($c1.Text -match 'memory lint: dangling')

$l2 = PrnRun $lintPs @('-MemoryDir', $mem, '-Fix')
Ok "lint -Fix exits 0"                      ($l2.Code -eq 0)
Ok "lint -Fix reports 3 fixed"              ($l2.Text -match '3 issue\(s\) \(3 fixed\)')
Ok "-Fix rewrites the dangling link"        ((Get-Content (Join-Path $mem 'project_stale.md') -Raw) -match '\(link removed: nope_missing\)')
Ok "-Fix drops the stale index line"        (-not ((Get-Content (Join-Path $mem 'MEMORY.md') -Raw) -match 'project_ghost\.md'))
Ok "-Fix keeps the good index lines"        ((Get-Content (Join-Path $mem 'MEMORY.md') -Raw) -match 'project_live\.md')

$l3 = PrnRun $lintPs @('-MemoryDir', $mem)
Ok "lint is clean after -Fix"               (($l3.Code -eq 0) -and ($l3.Text -match '0 issue\(s\)') -and ($l3.Text -match 'dangling links: 0'))
$c2 = PrnRun $chkPs @('-Hub', $case, '-MemoryDir', $mem)
Ok "check_pointers passes once links are clean" ($c2.Code -eq 0)

# variant links ([[a-b]] resolving to a_b) are reported and repaired
$vmem = Join-Path $case 'mem_variant'
New-Item -ItemType Directory -Path $vmem -Force | Out-Null
PrnWrite (Join-Path $vmem 'project_live.md') @"
---
name: project_live
description: live project memory
metadata:
  type: project
---

Body with a dash-spelled link: [[project-live]].
"@
PrnWrite (Join-Path $vmem 'MEMORY.md') "- [Live](project_live.md) - live project memory`n"
$v1 = PrnRun $lintPs @('-MemoryDir', $vmem)
Ok "lint flags a -/_ link variant as an issue" (($v1.Code -eq 1) -and ($v1.Text -match 'does not match the file name') -and ($v1.Text -match 'dangling links: 0'))
$v2 = PrnRun $lintPs @('-MemoryDir', $vmem, '-Fix')
Ok "-Fix rewrites the variant to the real name" (($v2.Code -eq 0) -and ((Get-Content (Join-Path $vmem 'project_live.md') -Raw) -match '\[\[project_live\]\]'))

# the -Fix rewrite refreshed mtimes; re-age so the prune staleness rules see the fixture as built
foreach ($f in @('project_stale.md', 'project_live.md')) { PrnAge (Join-Path $mem $f) 200 }
PrnAge (Join-Path $mem 'user_old.md') 400
PrnAge (Join-Path $mem 'feedback_keep.md') 1

# ---------------------------------------------------------------------------
# prune: dry-run
# ---------------------------------------------------------------------------
$ledgerBefore = (Get-Item $ledger).Length
$d1 = PrnRun $prunePs @('-Hub', $case, '-MemoryDir', $mem, '-Days', '90')
Ok "prune dry-run exits 0"                    ($d1.Code -eq 0)
Ok "dry-run lists 1 memory archive candidate" ($d1.Text -match 'memory: 1 archive candidate')
Ok "dry-run archives 0 feedback"              ($d1.Text -match '0 feedback archived')
Ok "dry-run lists the closed project by name" ($d1.Text -match 'project_stale\.md.*registry row marked closed')
Ok "dry-run keeps the registered live project" (-not ($d1.Text -match 'ARCHIVE\] project_live'))
Ok "dry-run flags the old user memory for review" (($d1.Text -match 'REVIEW \] user_old\.md') -and ($d1.Text -match '1 review'))
Ok "dry-run finds 4 archivable ledger sections" ($d1.Text -match 'ledger: 4 section\(s\) in 1 file\(s\)')
Ok "dry-run counts the TODO done lines"        ($d1.Text -match 'todo: 2 done line')
Ok "dry-run runs the lint at the end"          ($d1.Text -match '\[lint\] DONE')
Ok "dry-run moves nothing (memory)"            (Test-Path (Join-Path $mem 'project_stale.md'))
Ok "dry-run moves nothing (ledger)"            ((Get-Item $ledger).Length -eq $ledgerBefore)
Ok "dry-run creates no _archive dir"           (-not (Test-Path (Join-Path $case '_archive')))
Ok "dry-run writes the prune stamp"            (Test-Path (Join-Path $case '.claude\sonelle_prune_stamp'))

# ---------------------------------------------------------------------------
# prune: -Apply
# ---------------------------------------------------------------------------
$a1 = PrnRun $prunePs @('-Hub', $case, '-MemoryDir', $mem, '-Days', '90', '-Apply')
Ok "prune -Apply exits 0"                     ($a1.Code -eq 0)
Ok "-Apply moves the stale memory out"        (-not (Test-Path (Join-Path $mem 'project_stale.md')))
Ok "-Apply archives it (never deletes)"       (Test-Path (Join-Path $case '_archive\memory\project_stale.md'))
Ok "-Apply keeps the live project memory"     (Test-Path (Join-Path $mem 'project_live.md'))
Ok "-Apply keeps feedback + user memory"      ((Test-Path (Join-Path $mem 'feedback_keep.md')) -and (Test-Path (Join-Path $mem 'user_old.md')))
Ok "-Apply drops the archived index line"     (-not ((Get-Content (Join-Path $mem 'MEMORY.md') -Raw) -match 'project_stale\.md'))

$ledTxt = Get-Content $ledger -Raw
Ok "-Apply archives the old ledger sections"  ((Test-Path (Join-Path $case '_archive\ledger\_stale_run_STATUS_2024-01.md')) -and (Test-Path (Join-Path $case '_archive\ledger\_stale_run_STATUS_2024-05.md')))
Ok "archived section text landed in _archive" ((Get-Content (Join-Path $case '_archive\ledger\_stale_run_STATUS_2024-01.md') -Raw) -match '### 2024-01-05 - run one')
Ok "-Apply removed the archived sections"     (-not ($ledTxt -match '2024-01-05'))
Ok "-Apply kept the RESUME section"           (($ledTxt -match '2024-03-05') -and ($ledTxt -match 'RESUME'))
Ok "-Apply kept the last 3 sections"          (($ledTxt -match $recent[0]) -and ($ledTxt -match $recent[1]) -and ($ledTxt -match $recent[2]))
Ok "ledger has exactly 4 sections left"       ((@([regex]::Matches($ledTxt, '(?m)^### ')).Count) -eq 4)
Ok "-Apply leaves a pointer line on top"      ($ledTxt -match '(?m)^\(archived: 4 sections -> _archive\\ledger\\')
Ok "pointer sits under the title"             ((($ledTxt -replace "`r`n", "`n").Split("`n")[0]) -match '^# Stale Proj')
Ok "-Apply ignores a ledger under the gate"   ((Get-Content $smallLedger -Raw) -eq $smallBefore)
Ok "-Apply refreshes the prune stamp"         ((Get-Content (Join-Path $case '.claude\sonelle_prune_stamp') -Raw) -match 'mode=apply')

# ---------------------------------------------------------------------------
# second run = clean
# ---------------------------------------------------------------------------
$d2 = PrnRun $prunePs @('-Hub', $case, '-MemoryDir', $mem, '-Days', '90')
Ok "second dry-run finds no memory candidate" ($d2.Text -match 'memory: 0 archive candidate')
Ok "second dry-run finds no ledger sections"  ($d2.Text -match 'ledger: 0 section\(s\)')
Ok "second dry-run lint is clean"             ($d2.Text -match '0 issue\(s\)')
$c3 = PrnRun $chkPs @('-Hub', $case, '-MemoryDir', $mem)
Ok "check_pointers still passes after prune"  ($c3.Code -eq 0)

# ---------------------------------------------------------------------------
# robustness: nothing here may throw or archive by accident
# ---------------------------------------------------------------------------
$bare = Join-Path $case 'bare_hub'
New-Item -ItemType Directory -Path $bare -Force | Out-Null
PrnWrite (Join-Path $bare '_x_run_STATUS.md') ("no headings at all, just text`n" * 40)
$r1 = PrnRun $lintPs @('-MemoryDir', (Join-Path $bare 'memory'))
Ok "lint on a missing memory dir exits 0"       (($r1.Code -eq 0) -and ($r1.Text -match 'dangling links: 0'))
$r2 = PrnRun $prunePs @('-Hub', $bare, '-MemoryDir', (Join-Path $bare 'memory'))
Ok "prune with no PROJECTS.md archives nothing" (($r2.Code -eq 0) -and ($r2.Text -match 'memory: 0 archive candidate') -and ($r2.Text -match 'no PROJECTS\.md'))
Ok "prune survives a headingless ledger"        ($r2.Text -match 'ledger: 0 section')
# -Hub without -MemoryDir must not silently prune an empty <hub>\memory: it says which dir it used
$r3 = PrnRun $prunePs @('-Hub', $case)
Ok "prune without -MemoryDir reports the dir it used" (($r3.Code -eq 0) -and ($r3.Text -match '(?m)^\[prune\] memory dir: '))

if (Test-Path $case) { Remove-Item $case -Recurse -Force }

if ($prStandalone) {
  Write-Host ""
  if ($script:fail -eq 0) { Write-Host ("[selftest.d/prune] ALL PASS ({0} checks)" -f $script:pass) -ForegroundColor Green; exit 0 }
  else { Write-Host ("[selftest.d/prune] {0} FAIL / {1} pass" -f $script:fail, $script:pass) -ForegroundColor Red; exit 1 }
}
