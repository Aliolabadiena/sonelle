<#
  selftest.d\agents.ps1 - covers the four named subagents (v1.47).
  Dot-sourced by tools\selftest.ps1 with $engine, $tmp and the Ok helper already defined.
  Also runnable STANDALONE:  powershell -NoProfile -ExecutionPolicy Bypass -File tools\selftest.d\agents.ps1
  (the fallbacks below supply $engine / $tmp / $ps / Ok and print their own summary).

  What it proves: every agent file parses as frontmatter + body; reviewer and verifier are
  structurally review-only (no Edit/Write/MultiEdit/NotebookEdit anywhere in their tool lists);
  the engine's .claude\agents copies do not drift from templates\agents; new_project scaffolds
  the agents into a project; and nothing personal leaked into these public files.
#>

# ---- standalone fallbacks (no-ops when dot-sourced by selftest.ps1) ----
$agStandalone = $false
if (-not (Get-Command Ok -ErrorAction SilentlyContinue)) {
  $agStandalone = $true
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

Write-Host "== agents. named subagents (reviewer / verifier / implementer / scout) =="

$agTplDir = Join-Path $engine 'templates\agents'
$agEngDir = Join-Path $engine '.claude\agents'
$agNames  = @('reviewer', 'verifier', 'implementer', 'scout')
$agReadOnly = @('reviewer', 'verifier')
$agBanned = @('Edit', 'Write', 'MultiEdit', 'NotebookEdit')
$agValidModels = @('opus', 'sonnet', 'haiku', 'fable', 'inherit')

# frontmatter parser: returns a hashtable of top-level "key: value" pairs from the leading --- block.
function Get-AgentFrontmatter($path) {
  $h = @{}
  if (-not (Test-Path $path)) { return $h }
  $raw = [System.IO.File]::ReadAllText($path)
  $m = [regex]::Match($raw, "(?s)\A---\r?\n(.*?)\r?\n---\r?\n")
  if (-not $m.Success) { return $h }
  foreach ($line in ($m.Groups[1].Value -split "\r?\n")) {
    $kv = [regex]::Match($line, '^([A-Za-z][A-Za-z0-9_]*)\s*:\s*(.*)$')
    if ($kv.Success) { $h[$kv.Groups[1].Value] = $kv.Groups[2].Value.Trim() }
  }
  return $h
}
function Get-ToolList($value) {
  if (-not $value) { return @() }
  return @(($value -replace '^\[|\]$', '') -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

Ok "templates\agents exists" (Test-Path $agTplDir)
Ok "engine .claude\agents exists" (Test-Path $agEngDir)

foreach ($n in $agNames) {
  $f  = Join-Path $agTplDir ($n + '.md')
  $fm = Get-AgentFrontmatter $f
  Ok ("agent file exists: " + $n)                 (Test-Path $f)
  Ok ("$n frontmatter parses (name/description/model)") ($fm.ContainsKey('name') -and $fm.ContainsKey('description') -and $fm.ContainsKey('model'))
  Ok ("$n name matches filename")                 ($fm['name'] -eq $n)
  Ok ("$n model is a valid value")                ($agValidModels -contains $fm['model'])
  Ok ("$n description is non-trivial (>40 chars)") ([string]$fm['description'] -and ([string]$fm['description']).Length -gt 40)
  $body = ''
  if (Test-Path $f) { $body = ([System.IO.File]::ReadAllText($f) -replace "(?s)\A---\r?\n.*?\r?\n---\r?\n", '') }
  Ok ("$n has a prompt body")                     ($body.Trim().Length -gt 200)
}

# the hard part: reviewer/verifier cannot edit. tools: is an allowlist, disallowedTools: is the second lock.
foreach ($n in $agReadOnly) {
  $fm    = Get-AgentFrontmatter (Join-Path $agTplDir ($n + '.md'))
  $tools = Get-ToolList $fm['tools']
  $dis   = Get-ToolList $fm['disallowedTools']
  Ok ("$n declares a tools allowlist")            ($tools.Count -gt 0)
  $leak = @($tools | Where-Object { $agBanned -contains $_ })
  Ok ("$n tools allowlist has NO Edit/Write/MultiEdit/NotebookEdit") ($leak.Count -eq 0)
  Ok ("$n can still read + search (Read/Grep/Glob)") (($tools -contains 'Read') -and ($tools -contains 'Grep') -and ($tools -contains 'Glob'))
  Ok ("$n can run commands for evidence (Bash)")  ($tools -contains 'Bash')
  Ok ("$n disallowedTools repeats the write ban") (($dis -contains 'Edit') -and ($dis -contains 'Write') -and ($dis -contains 'NotebookEdit'))
  Ok ("$n runs opus at effort high")              (($fm['model'] -eq 'opus') -and ($fm['effort'] -eq 'high'))
}

# implementer: the one that DOES write - full default tool set (no allowlist) + acceptEdits.
$fmImp = Get-AgentFrontmatter (Join-Path $agTplDir 'implementer.md')
Ok "implementer inherits the full tool set (no tools: allowlist)" (-not $fmImp.ContainsKey('tools'))
Ok "implementer runs opus"                       ($fmImp['model'] -eq 'opus')
Ok "implementer is permissionMode acceptEdits"   ($fmImp['permissionMode'] -eq 'acceptEdits')

# scout: cheap recon only - no shell at all.
$fmSc = Get-AgentFrontmatter (Join-Path $agTplDir 'scout.md')
$scTools = Get-ToolList $fmSc['tools']
Ok "scout is Read/Grep/Glob only (no Bash)"      ((($scTools | Sort-Object) -join ',') -eq 'Glob,Grep,Read')
Ok "scout is a cheap model"                      (@('haiku', 'sonnet') -contains $fmSc['model'])

# one source of truth: the engine's copies must equal the templates byte for byte.
$agDrift = @()
foreach ($n in $agNames) {
  $a = Join-Path $agTplDir ($n + '.md')
  $b = Join-Path $agEngDir ($n + '.md')
  if ((-not (Test-Path $b)) -or ((Get-FileHash $a).Hash -ne (Get-FileHash $b).Hash)) { $agDrift += $n }
}
Ok "engine .claude\agents match templates\agents (no drift)" ($agDrift.Count -eq 0)

# docs
$agDocs = Join-Path $engine 'docs\AGENTS.md'
$agDocTxt = ''
if (Test-Path $agDocs) { $agDocTxt = [System.IO.File]::ReadAllText($agDocs) }
Ok "docs\AGENTS.md exists"                       (Test-Path $agDocs)
Ok "docs\AGENTS.md covers all four agents"       (($agNames | Where-Object { $agDocTxt -match ('(?m)\b' + $_ + '\b') }).Count -eq 4)
Ok "docs\AGENTS.md shows the Workflow agentType call" ($agDocTxt -match "agentType:\s*'reviewer'")
Ok "docs\AGENTS.md shows the Agent subagent_type call" ($agDocTxt -match 'subagent_type')
$agDev = ''
if (Test-Path (Join-Path $engine 'docs\DEVELOPING.md')) { $agDev = [System.IO.File]::ReadAllText((Join-Path $engine 'docs\DEVELOPING.md')) }
Ok "docs\DEVELOPING.md documents the wave pattern" (($agDev -match '(?m)^##\s+Agents') -and ($agDev -match 'agentType') -and ($agDev -match 'DISJOINT'))

# scaffold: a brand-new (self-contained) project gets the agents tree.
Ok "new_project copies templates\agents" ((Get-Content (Join-Path $engine 'tools\new_project.ps1') -Raw) -match 'agentsSrc')
$agProj = Join-Path $tmp 'agents_scaffold'
if (Test-Path $agProj) { Remove-Item $agProj -Recurse -Force }
& $ps -ExecutionPolicy Bypass -File (Join-Path $engine 'tools\new_project.ps1') ag "Agents Scaffold" $agProj | Out-Null
Ok "scaffold new_project exit 0"                 ($LASTEXITCODE -eq 0)
$agScaffolded = $true
foreach ($n in $agNames) { if (-not (Test-Path (Join-Path $agProj ('.claude\agents\' + $n + '.md')))) { $agScaffolded = $false } }
Ok "new_project scaffolds .claude\agents into a project" $agScaffolded
$agCopyOk = $true
if ($agScaffolded) {
  foreach ($n in $agNames) {
    if ((Get-FileHash (Join-Path $agTplDir ($n + '.md'))).Hash -ne (Get-FileHash (Join-Path $agProj ('.claude\agents\' + $n + '.md'))).Hash) { $agCopyOk = $false }
  }
}
Ok "scaffolded agents are byte-identical to the templates" $agCopyOk

# public repo hygiene: no personal paths / emails in anything this section owns.
$agPublic = @()
foreach ($n in $agNames) { $agPublic += (Join-Path $agTplDir ($n + '.md')); $agPublic += (Join-Path $agEngDir ($n + '.md')) }
$agPublic += $agDocs
$agLeaks = @()
foreach ($p in $agPublic) {
  if (-not (Test-Path $p)) { continue }
  $t = [System.IO.File]::ReadAllText($p)
  if (($t -match '(?i)[A-Za-z]:\\Users\\') -or ($t -match '(?i)[A-Za-z]:/Users/') -or ($t -match '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}')) { $agLeaks += (Split-Path $p -Leaf) }
}
Ok "agent files + docs carry no personal paths or emails" ($agLeaks.Count -eq 0)

if ($agStandalone) {
  Write-Host ""
  Write-Host ("agents.ps1: {0} passed, {1} failed" -f $script:pass, $script:fail)
  if (Test-Path $agProj) { Remove-Item $agProj -Recurse -Force -ErrorAction SilentlyContinue }
  if ($script:fail -gt 0) { exit 1 } else { exit 0 }
}
