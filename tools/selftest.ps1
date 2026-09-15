<#
  selftest.ps1 - end-to-end engine self-test (dogfoods the tools into a temp hub).
  Verifies: every .ps1 parses + is pure ASCII; scaffold creates a full skeleton with no
  leftover placeholders; the registry row lands; check_pointers + doctor report healthy;
  the duplicate guard rejects a re-create. Leaves nothing behind.

  Usage:  .\selftest.ps1     Exit: 0 = all pass, 1 = any fail.
#>
$ErrorActionPreference = 'Stop'
$engine = Split-Path $PSScriptRoot -Parent
$ps     = (Get-Process -Id $PID).Path
$script:fail = 0
$script:pass = 0
function Ok($label, $cond) {
  if ($cond) { Write-Host ("  [PASS] {0}" -f $label) -ForegroundColor Green; $script:pass++ }
  else { Write-Host ("  [FAIL] {0}" -f $label) -ForegroundColor Red; $script:fail++ }
}

Write-Host "== 1. parse + ASCII (all .ps1) =="
# exclude the local .venv (third-party scripts like Activate.ps1 are not ours to ASCII-gate)
Get-ChildItem $engine -Recurse -Filter *.ps1 | Where-Object { $_.FullName -notmatch '\\\.venv\\' } | ForEach-Object {
  $e = $null; $t = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$t, [ref]$e)
  $na = ([System.IO.File]::ReadAllBytes($_.FullName) | Where-Object { $_ -gt 127 }).Count
  Ok ("parse " + $_.Name) ($e.Count -eq 0)
  Ok ("ascii " + $_.Name) ($na -eq 0)
}
foreach ($jf in @((Join-Path $engine '.claude\settings.json'), (Join-Path $engine 'templates\settings.template.json'))) {
  $okj = $true; try { [void](Get-Content $jf -Raw | ConvertFrom-Json) } catch { $okj = $false }
  Ok ("valid JSON: " + (Split-Path $jf -Leaf)) $okj
}
$slj = '{"model":{"display_name":"Opus"},"rate_limits":{"five_hour":{"used_percentage":50}},"cost":{"total_cost_usd":0}}'
$slOut = ($slj | & $ps -NoProfile -File (Join-Path $engine 'tools\statusline.ps1')) -replace "$([char]27)\[[0-9;]*m", ''
Ok "statusline renders usage" ($slOut -match 'sonelle.*5h 50%')

Write-Host "== 2. scaffold into a temp hub =="
$tmp = Join-Path $env:TEMP 'sonelle_selftest'
if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
Copy-Item (Join-Path $engine 'CLAUDE.md')   (Join-Path $tmp 'CLAUDE.md')   -Force
Copy-Item (Join-Path $engine 'PROJECTS.md') (Join-Path $tmp 'PROJECTS.md') -Force
$codePath = Join-Path $tmp 'code_st'
& $ps -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'new_project.ps1') st "Selftest Proj" $codePath -Hub $tmp | Out-Null
Ok "new_project exit 0"            ($LASTEXITCODE -eq 0)
Ok "TODO created"                  (Test-Path (Join-Path $tmp 'ST_TODO.txt'))
Ok "ledger created"                (Test-Path (Join-Path $tmp '_st_run_STATUS.md'))
Ok "project CLAUDE.md created"     (Test-Path (Join-Path $codePath 'CLAUDE.md'))
Ok "memory file created"           (Test-Path (Join-Path $tmp 'memory\project_st.md'))
Ok "registry row present"          ((Get-Content (Join-Path $tmp 'PROJECTS.md') -Raw) -match '(?m)^\|\s*st\s*\|')
$ph = (Select-String -Path (Join-Path $tmp 'ST_TODO.txt'), (Join-Path $codePath 'CLAUDE.md'), (Join-Path $tmp 'memory\project_st.md') -Pattern '\{\{' -ErrorAction SilentlyContinue).Count
Ok "no unfilled placeholders"      ($ph -eq 0)
Ok "project .claude/settings.json created" (Test-Path (Join-Path $codePath '.claude\settings.json'))
Ok "project Stop+SessionStart hooks created" ((Test-Path (Join-Path $codePath '.claude\hooks\stop.ps1')) -and (Test-Path (Join-Path $codePath '.claude\hooks\session_start.ps1')))
$ssTxt = Get-Content (Join-Path $codePath '.claude\hooks\session_start.ps1') -Raw
Ok "session_start hook surfaces memory (not just a reminder)" (($ssTxt -match 'MEMORY\.md') -and ($ssTxt -match 'Get-Content'))
Ok "project sonelle.check.ps1 created" (Test-Path (Join-Path $codePath 'sonelle.check.ps1'))
$chkTxt = Get-Content (Join-Path $codePath 'sonelle.check.ps1') -Raw
Ok "default check auto-detects + marks unconfigured" (($chkTxt -match 'pytest|npm test|dotnet test') -and ($chkTxt -match 'exit 2'))
$vj = $true; try { [void](Get-Content (Join-Path $codePath '.claude\settings.json') -Raw | ConvertFrom-Json) } catch { $vj = $false }
Ok "project settings.json is valid JSON" $vj
# scaffold inherits the PreToolUse guard hook + the /selftest /heal /ship /ritual slash commands
Ok "project PreToolUse guard hook created" (Test-Path (Join-Path $codePath '.claude\hooks\pretooluse_guard.ps1'))
Ok "project settings wires PreToolUse -> guard" ((Get-Content (Join-Path $codePath '.claude\settings.json') -Raw) -match 'pretooluse_guard\.ps1')
foreach ($c in @('selftest', 'heal', 'ship', 'ritual')) { Ok ("project /$c command created") (Test-Path (Join-Path $codePath ('.claude\commands\' + $c + '.md'))) }

# T2: golden snapshot - the template SET and the scaffold MANIFEST must stay stable, so an accidental
# template/scaffold change that would alter every new project trips this test (a conscious change updates it).
$tplDir  = Join-Path $engine 'templates'
$tplGot  = @(Get-ChildItem $tplDir -Recurse -File | ForEach-Object { $_.FullName.Substring($tplDir.Length + 1).Replace('\', '/') } | Sort-Object)
$tplWant = @('CLAUDE.template.md', 'TODO.template.txt', 'commands/heal.md', 'commands/ritual.md', 'commands/selftest.md', 'commands/ship.md', 'hooks/pretooluse_guard.ps1', 'hooks/session_start.ps1', 'hooks/stop.ps1', 'lesson.template.md', 'mcp.template.json', 'project_memory.template.md', 'run_STATUS.template.md', 'settings.template.json', 'skills/accessibility-audit/SKILL.md', 'skills/design-review/SKILL.md', 'skills/frontend-design/SKILL.md', 'skills/plan-before-build/SKILL.md', 'skills/systematic-debugging/SKILL.md', 'skills/verification-before-completion/SKILL.md') | Sort-Object
Ok "template set is exactly the known golden (T2)" (($tplGot -join '|') -eq ($tplWant -join '|'))
$manifestOk = $true
foreach ($f in @((Join-Path $tmp 'ST_TODO.txt'), (Join-Path $tmp '_st_run_STATUS.md'), (Join-Path $codePath 'CLAUDE.md'), (Join-Path $codePath 'sonelle.check.ps1'), (Join-Path $codePath '.claude\settings.json'), (Join-Path $codePath '.claude\hooks\session_start.ps1'), (Join-Path $codePath '.claude\hooks\stop.ps1'), (Join-Path $codePath '.claude\hooks\pretooluse_guard.ps1'), (Join-Path $codePath '.claude\commands\selftest.md'), (Join-Path $codePath '.claude\commands\heal.md'), (Join-Path $codePath '.claude\commands\ship.md'), (Join-Path $codePath '.claude\commands\ritual.md'), (Join-Path $codePath '.claude\skills\frontend-design\SKILL.md'), (Join-Path $codePath '.claude\skills\systematic-debugging\SKILL.md'), (Join-Path $tmp 'memory\project_st.md'), (Join-Path $tmp 'memory\MEMORY.md'))) {
  if (-not (Test-Path $f)) { $manifestOk = $false }
}
Ok "scaffold produces the full golden manifest (T2)" $manifestOk
# opt-in MCP (-Mcp): scaffolds a project .mcp.json with the recommended servers; default omits it
$mcpPath = Join-Path $tmp 'code_mc'
& $ps -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'new_project.ps1') mc "MCP Proj" $mcpPath -Hub $tmp -Mcp | Out-Null
Ok "new_project -Mcp scaffolds .mcp.json"       (Test-Path (Join-Path $mcpPath '.mcp.json'))
Ok "default scaffold (no -Mcp) omits .mcp.json" (-not (Test-Path (Join-Path $codePath '.mcp.json')))
$mcpValid = $false; try { $mj = Get-Content (Join-Path $mcpPath '.mcp.json') -Raw | ConvertFrom-Json; $mcpValid = [bool]$mj.mcpServers } catch {}
Ok ".mcp.json is valid JSON with an mcpServers block" $mcpValid

Write-Host "== 2c. self-contained default (no -Hub) + engine-root refusal (invariant #4) =="
# Default behavior: with NO -Hub, the project's OWN folder is its hub - all state lands inside it,
# nothing in the engine. This is what stops the split-brain bug (new_project writing to the engine
# while the tools read a different hub).
$scProj = Join-Path $tmp 'selfcontained'
& $ps -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'new_project.ps1') sc "Self Contained" $scProj | Out-Null
Ok "self-contained new_project exit 0"          ($LASTEXITCODE -eq 0)
Ok "self-contained seeds its OWN PROJECTS.md"   (Test-Path (Join-Path $scProj 'PROJECTS.md'))
Ok "self-contained registry row lands in the project" ((Test-Path (Join-Path $scProj 'PROJECTS.md')) -and ((Get-Content (Join-Path $scProj 'PROJECTS.md') -Raw) -match '(?m)^\|\s*sc\s*\|'))
Ok "self-contained TODO lands in the project"   (Test-Path (Join-Path $scProj 'SC_TODO.txt'))
Ok "self-contained ledger lands in the project" (Test-Path (Join-Path $scProj '_sc_run_STATUS.md'))
Ok "self-contained memory lands in the project" (Test-Path (Join-Path $scProj 'memory\project_sc.md'))
Ok "self-contained CLAUDE.md + check land in the project" ((Test-Path (Join-Path $scProj 'CLAUDE.md')) -and (Test-Path (Join-Path $scProj 'sonelle.check.ps1')))
Ok "self-contained wrote NOTHING to the engine (no SC_TODO at engine root)" (-not (Test-Path (Join-Path $engine 'SC_TODO.txt')))
Ok "self-contained added NO row to the engine registry" (-not ((Get-Content (Join-Path $engine 'PROJECTS.md') -Raw) -match '(?m)^\|\s*sc\s*\|'))
# a self-contained project is health-checkable by pointing -Hub at its own folder
& $ps -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'check_pointers.ps1') -Hub $scProj | Out-Null
Ok "check_pointers green on the self-contained hub" ($LASTEXITCODE -eq 0)
# refusal: scaffolding INTO the engine folder is blocked at the script level (belt to the guard hook)
& $ps -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'new_project.ps1') re "Refuse Engine" (Join-Path $tmp 'recode') -Hub $engine | Out-Null
Ok "new_project refuses -Hub == engine (exit 1)"   ($LASTEXITCODE -eq 1)
Ok "engine registry untouched by the refused run"  (-not ((Get-Content (Join-Path $engine 'PROJECTS.md') -Raw) -match '(?m)^\|\s*re\s*\|'))
Ok "engine root still clean after refusal (no RE_TODO)" (-not (Test-Path (Join-Path $engine 'RE_TODO.txt')))

Write-Host "== 3. check_pointers on temp hub =="
& $ps -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'check_pointers.ps1') -Hub $tmp | Out-Null
Ok "check_pointers exit 0"         ($LASTEXITCODE -eq 0)

Write-Host "== 4. doctor on temp hub =="
$docOut = & $ps -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'doctor.ps1') -Hub $tmp
Ok "doctor healthy (exit 0)"       ($LASTEXITCODE -eq 0)
Ok "doctor flags unconfigured check (not a fake all-clear)" ((($docOut -join "`n")) -match 'NOT configured')
# R2: doctor flags orphaned state (a TODO with no registry row) as a non-fatal warning
[System.IO.File]::WriteAllText((Join-Path $tmp 'ZZ_TODO.txt'), 'orphan')
$docOrph = & $ps -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'doctor.ps1') -Hub $tmp
Ok "doctor flags an orphan state file (R2)" ((($docOrph -join "`n")) -match 'orphan state: ZZ_TODO')
Ok "orphan is a warning, not a failure (exit 0)" ($LASTEXITCODE -eq 0)
Remove-Item (Join-Path $tmp 'ZZ_TODO.txt') -Force

Write-Host "== 5. duplicate guard =="
& $ps -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'new_project.ps1') st "Dup" $codePath -Hub $tmp | Out-Null
Ok "duplicate rejected (exit 1)"   ($LASTEXITCODE -eq 1)

Write-Host "== 5e. new_project rolls back a partial scaffold (R1) =="
# Point the code path at an existing FILE: the dir/index appends succeed, but writing CLAUDE.md INSIDE a
# file path fails mid-scaffold - so the run must roll back (delete the TODO/ledger it already wrote, no row).
$rbHub = Join-Path $env:TEMP 'sonelle_selftest_rb'
if (Test-Path $rbHub) { Remove-Item $rbHub -Recurse -Force }
New-Item -ItemType Directory -Path $rbHub -Force | Out-Null
Copy-Item (Join-Path $engine 'PROJECTS.md') (Join-Path $rbHub 'PROJECTS.md') -Force
$rbBad = Join-Path $rbHub 'iam_a_file'
Set-Content -Path $rbBad -Value 'x'
& $ps -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'new_project.ps1') rb "Rollback Proj" $rbBad -Hub $rbHub | Out-Null
Ok "scaffold fails on a bad code path (exit 1)" ($LASTEXITCODE -eq 1)
Ok "rollback left no TODO orphan"        (-not (Test-Path (Join-Path $rbHub 'RB_TODO.txt')))
Ok "rollback left no ledger orphan"      (-not (Test-Path (Join-Path $rbHub '_rb_run_STATUS.md')))
Ok "rollback left no registry row"       (-not ((Get-Content (Join-Path $rbHub 'PROJECTS.md') -Raw) -match '(?m)^\|\s*rb\s*\|'))
$rbIdx = Join-Path $rbHub 'memory\MEMORY.md'
Ok "rollback left no memory index line"  ((-not (Test-Path $rbIdx)) -or (-not ((Get-Content $rbIdx -Raw) -match 'project_rb')))
if (Test-Path $rbHub) { Remove-Item $rbHub -Recurse -Force }

Write-Host "== 5f. reserved shortcodes =="
# 'general' stays a reserved word in the registry: new_project must refuse to scaffold it.
& $ps -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'new_project.ps1') general "Should Fail" (Join-Path $tmp 'genfail') -Hub $tmp | Out-Null
Ok "new_project rejects the reserved 'general' shortcode" ($LASTEXITCODE -eq 1)

Write-Host "== 6. check_pointers DETECTS a broken pointer (negative test) =="
Remove-Item $codePath -Recurse -Force
& $ps -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'check_pointers.ps1') -Hub $tmp | Out-Null
Ok "check_pointers exit 1 on a missing code path" ($LASTEXITCODE -eq 1)

Write-Host "== 7. .gitignore ignores the private paths =="
if (Get-Command git -ErrorAction SilentlyContinue) {
  foreach ($f in @('sonelle.config.json', 'memory/x.md', 'FOO_TODO.txt', 'REPOMAP.md')) {
    Ok "gitignored: $f" ([bool](git -C $engine check-ignore $f))
  }
} else { Write-Host "  [skip] git not on PATH" -ForegroundColor DarkGray }

Write-Host "== 8. self-develop wiring =="
Ok "DEVELOPING.md exists"          (Test-Path (Join-Path $engine 'docs\DEVELOPING.md'))
Ok "dispatcher points to self-dev" ((Get-Content (Join-Path $engine 'CLAUDE.md') -Raw) -match 'DEVELOPING\.md')
# v1.46: the terminal launcher and its lane runner are gone for good - sonelle is a Claude Code
# workflow (CLAUDE.md + registry + tools + hooks + skills), not a launcher. Guard the removal.
Ok "terminal + launchers fully removed (v1.46)" ((-not (Test-Path (Join-Path $engine 'bin'))) -and (-not (Test-Path (Join-Path $engine 'app'))))

Write-Host "== 8b. engine root stays clean (invariant #4) =="
# invariant #4: the engine root must stay clean of hub state (no project TODO/ledger/memory)
$rootTodo = @(Get-ChildItem $engine -Filter '*_TODO.txt' -File -ErrorAction SilentlyContinue).Count
$rootLedg = @(Get-ChildItem $engine -Filter '_*_run_STATUS.md' -File -ErrorAction SilentlyContinue).Count
Ok "engine root clean (no hub state)" (($rootTodo -eq 0) -and ($rootLedg -eq 0) -and (-not (Test-Path (Join-Path $engine 'memory'))))

Write-Host "== 8h. PreToolUse guard + slash commands =="
$guardEng = Join-Path $engine '.claude\hooks\pretooluse_guard.ps1'
Ok "engine PreToolUse guard hook exists" (Test-Path $guardEng)
$srcGuard = if (Test-Path $guardEng) { Get-Content $guardEng -Raw } else { '' }
Ok "guard reads stdin as UTF-8, can block (exit 2), and fails open (exit 0)" (($srcGuard -match 'OpenStandardInput') -and ($srcGuard -match 'UTF8') -and ($srcGuard -match 'ReadToEnd') -and ($srcGuard -match 'exit 2') -and ($srcGuard -match 'exit 0'))
Ok "guard enforces ASCII-only .ps1 (house rule)" (($srcGuard -match '\.ps1') -and ($srcGuard -match '127'))
Ok "guard blocks hub state at the engine root, but allows log_lesson -Shared (invariant #4)" (($srcGuard -match 'new_project') -and ($srcGuard -match 'log_lesson') -and ($srcGuard -match '-Shared') -and ($srcGuard -match 'memory'))
Ok "guard blocks force-push" ($srcGuard -match 'force')
# behavioral: feed the guard real PreToolUse payloads as raw UTF-8 bytes (as claude does) and assert the
# block/allow decisions. 'cmd type' pipes the raw bytes, bypassing PS 5.1 $OutputEncoding (ASCII) which
# would otherwise mangle non-ASCII to '?' before the guard sees it.
$gi = Join-Path $tmp 'guard_in.json'
$u8 = New-Object System.Text.UTF8Encoding($false)
function Invoke-Guard($obj) {
  [System.IO.File]::WriteAllText($gi, ($obj | ConvertTo-Json -Compress -Depth 6), $u8)
  # discard the guard's stderr INSIDE cmd (its block message would otherwise surface as a terminating
  # NativeCommandError under $ErrorActionPreference=Stop); cmd /c still returns the guard's exit code.
  $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try { & cmd /c "type `"$gi`" 2>nul | `"$ps`" -NoProfile -ExecutionPolicy Bypass -File `"$guardEng`" 2>nul" | Out-Null }
  finally { $ErrorActionPreference = $eap }
  return $LASTEXITCODE
}
$gNonAscii = "Write-Host 'caf" + [char]0xE9 + "'"
Ok "guard BLOCKS non-ASCII into a .ps1 (exit 2)" ((Invoke-Guard @{tool_name = 'Write'; tool_input = @{file_path = 'C:\x\a.ps1'; content = $gNonAscii}}) -eq 2)
Ok "guard ALLOWS ASCII .ps1 (exit 0)"            ((Invoke-Guard @{tool_name = 'Write'; tool_input = @{file_path = 'C:\x\a.ps1'; content = 'Write-Host hi'}}) -eq 0)
Ok "guard ALLOWS non-ASCII in a .md (only .ps1 is gated)" ((Invoke-Guard @{tool_name = 'Write'; tool_input = @{file_path = 'C:\x\a.md'; content = $gNonAscii}}) -eq 0)
Ok "guard BLOCKS new_project (invariant #4)"     ((Invoke-Guard @{tool_name = 'Bash'; tool_input = @{command = 'powershell tools\new_project.ps1 a b c'}}) -eq 2)
Ok "guard ALLOWS log_lesson -Shared"             ((Invoke-Guard @{tool_name = 'Bash'; tool_input = @{command = 'powershell tools\log_lesson.ps1 -Shared x'}}) -eq 0)
Ok "guard BLOCKS git push --force"               ((Invoke-Guard @{tool_name = 'Bash'; tool_input = @{command = 'git push --force'}}) -eq 2)
Ok "guard ALLOWS an ordinary command"            ((Invoke-Guard @{tool_name = 'Bash'; tool_input = @{command = 'git status'}}) -eq 0)
Remove-Item $gi -Force -ErrorAction SilentlyContinue
$engSet = Get-Content (Join-Path $engine '.claude\settings.json') -Raw
Ok "engine settings.json wires PreToolUse -> guard" (($engSet -match 'PreToolUse') -and ($engSet -match 'pretooluse_guard\.ps1'))
foreach ($c in @('selftest', 'heal', 'ship', 'ritual')) { Ok ("engine /$c command exists") (Test-Path (Join-Path $engine ('.claude\commands\' + $c + '.md'))) }
Ok "/ship gates on selftest before committing" ((Get-Content (Join-Path $engine '.claude\commands\ship.md') -Raw) -match 'selftest')

Write-Host "== 8g. shared knowledge base =="
$kbIdx = Join-Path $engine 'knowledge\INDEX.md'
Ok "knowledge/INDEX.md exists"          (Test-Path $kbIdx)
foreach ($rel in @('knowledge\powershell-commit-heredoc.md', 'knowledge\powershell-pure-ascii.md')) {
  Ok ("seed lesson: " + $rel)           (Test-Path (Join-Path $engine $rel))
}
$srcKbIdx = if (Test-Path $kbIdx) { Get-Content $kbIdx -Raw } else { '' }
Ok "index links its seed lessons"       (($srcKbIdx -match 'powershell-commit-heredoc') -and ($srcKbIdx -match 'powershell-pure-ascii'))
Ok "knowledge: /rewind undo lesson is in the brain (committed + indexed)" ((Test-Path (Join-Path $engine 'knowledge\claude-rewind-undo.md')) -and ($srcKbIdx -match 'claude-rewind-undo'))
$srcLog = Get-Content (Join-Path $engine 'tools\log_lesson.ps1') -Raw
Ok "log_lesson -Shared targets knowledge/" (($srcLog -match '\[switch\]\$Shared') -and ($srcLog -match "Join-Path .* 'knowledge'"))
$srcSs = Get-Content (Join-Path $engine '.claude\hooks\session_start.ps1') -Raw
Ok "SessionStart recalls the knowledge base" ($srcSs -match 'knowledge/INDEX\.md')

Write-Host "== 8j. reusable Agent Skills (the project brain) =="
$skillTpl = Join-Path $engine 'templates\skills'
$skillEng = Join-Path $engine '.claude\skills'
# the project template ships all six skills (discipline + web); the engine itself carries the three
# DISCIPLINE skills so engine-dev sessions get the same investigate / verify / plan gates.
foreach ($s in @('systematic-debugging', 'verification-before-completion', 'plan-before-build', 'frontend-design', 'design-review', 'accessibility-audit')) {
  Ok ("template skill: " + $s) (Test-Path (Join-Path $skillTpl ($s + '\SKILL.md')))
}
foreach ($s in @('systematic-debugging', 'verification-before-completion', 'plan-before-build')) {
  Ok ("engine skill: " + $s)   (Test-Path (Join-Path $skillEng ($s + '\SKILL.md')))
}
# every skill must be model-invocable (name: + description: + a "Use when" trigger) and pure ASCII
$skillBad = @()
foreach ($f in (Get-ChildItem $skillTpl -Recurse -Filter 'SKILL.md')) {
  $sc = Get-Content $f.FullName -Raw
  $na = ([System.IO.File]::ReadAllBytes($f.FullName) | Where-Object { $_ -gt 127 }).Count
  if (-not (($sc -match '(?m)^name:\s*\S') -and ($sc -match '(?m)^description:\s*\S') -and ($sc -match 'Use (when|before)'))) { $skillBad += $f.FullName }
  if ($na -gt 0) { $skillBad += ($f.FullName + ' (non-ascii)') }
}
Ok "every template skill has name/description/Use-when frontmatter + is ASCII" ($skillBad.Count -eq 0)
# one source of truth: the engine's discipline skills stay byte-identical to the templates
$drift = @()
foreach ($s in @('systematic-debugging', 'verification-before-completion', 'plan-before-build')) {
  if ((Get-Content (Join-Path $skillTpl ($s + '\SKILL.md')) -Raw) -ne (Get-Content (Join-Path $skillEng ($s + '\SKILL.md')) -Raw)) { $drift += $s }
}
Ok "engine discipline skills match the templates (no drift)" ($drift.Count -eq 0)
# the flagship web skill carries its load-bearing substance
$fd = Get-Content (Join-Path $skillTpl 'frontend-design\SKILL.md') -Raw
Ok "frontend-design carries its substance (two-pass plan + banned defaults)" (($fd -match 'Design plan') -and ($fd -match 'Inter') -and ($fd -match 'prefers-reduced-motion'))
Ok "new_project scaffolds the skills tree into a project" ((Get-Content (Join-Path $engine 'tools\new_project.ps1') -Raw) -match 'skillsSrc')

Write-Host "== 9. config resolver (hub + memoryDir) =="
. (Join-Path $PSScriptRoot '_registry.ps1')
$fakeHub = Join-Path $env:TEMP 'sonelle_cfgtest_hub'   # real drive (Join-Path validates the drive); path need not exist
$fakeMem = Join-Path $env:TEMP 'sonelle_cfgtest_mem'
$r1 = Get-SonelleConfig -Engine $engine -HubOverride $fakeHub
Ok "hub override wins"                  ($r1.Hub -eq $fakeHub)
Ok "memory defaults to <override-hub>\memory" ($r1.MemoryDir -eq (Join-Path $fakeHub 'memory'))
$r2 = Get-SonelleConfig -Engine $engine -HubOverride $fakeHub -MemoryOverride $fakeMem
Ok "explicit -MemoryDir wins"           ($r2.MemoryDir -eq $fakeMem)
Ok "check_pointers accepts -MemoryDir"  ((Get-Content (Join-Path $PSScriptRoot 'check_pointers.ps1') -Raw) -match '\$MemoryDir')
Ok "doctor forwards -MemoryDir"         ((Get-Content (Join-Path $PSScriptRoot 'doctor.ps1') -Raw) -match 'check_pointers\.ps1.*-MemoryDir')
# Q3: ONE config resolver - Get-SonelleConfig in tools\_registry.ps1 is the only place that parses
# sonelle.config.json; no tool re-parses the JSON itself (9a enforces the same for the registry parser).
Ok "resolver also returns the Models block" ((Get-Content (Join-Path $PSScriptRoot '_registry.ps1') -Raw) -match 'Models\s*=\s*\$cfgModels')
$r3 = Get-SonelleConfig -Engine $engine
Ok "resolver exposes a Models property"  ($null -ne ($r3.PSObject.Properties.Name | Where-Object { $_ -eq 'Models' }))
# the NA-path sentinel lives in ONE predicate (Test-SonelleCodePath) so the call sites can't drift
Ok "Test-SonelleCodePath: real path true; empty/NA false" ((Test-SonelleCodePath 'C:\x') -and (-not (Test-SonelleCodePath '')) -and (-not (Test-SonelleCodePath '-')) -and (-not (Test-SonelleCodePath '(set later)')))
$sentinelHits = @(Select-String -Path (Join-Path $engine 'tools\doctor.ps1'), (Join-Path $engine 'tools\check_pointers.ps1') -Pattern '\^\[-\(\]' -ErrorAction SilentlyContinue)
Ok "NA-path sentinel centralized (no raw regex left in the consumers)" ($sentinelHits.Count -eq 0)
# a malformed config must WARN (visible) and fall back to defaults - never SILENTLY relocate the hub.
# Pointing $env:SONELLE_CONFIG at the bad file also proves the resolver honors that override.
$badCfg = Join-Path $tmp 'bad.config.json'
[System.IO.File]::WriteAllText($badCfg, '{ not valid json ')
$savedCfgB = $env:SONELLE_CONFIG; $env:SONELLE_CONFIG = $badCfg
try {
  $capW   = Get-SonelleConfig -Engine $engine 3>&1
  $rbObj  = @($capW | Where-Object { ($_ -isnot [System.Management.Automation.WarningRecord]) -and ($_.PSObject.Properties.Name -contains 'Hub') })[0]
  $rbWarn = ($capW | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } | ForEach-Object { [string]$_ }) -join ' '
  Ok "malformed config falls back to the engine hub (no silent relocate)" (($null -ne $rbObj) -and ($rbObj.Hub -eq $engine))
  Ok "malformed config emits a visible warning, not silent" ($rbWarn -match 'malformed|ignoring')
} finally { $env:SONELLE_CONFIG = $savedCfgB; Remove-Item $badCfg -Force -ErrorAction SilentlyContinue }

Write-Host "== 9a. one registry parser, and no second (Q2) =="
# Q2: nobody adds a SECOND parser. Grep every .ps1/.py (minus .venv) for the registry-row regex signature;
# the only file allowed to carry it is _registry.ps1.
$scanFiles = @(Get-ChildItem $engine -Recurse -Include *.ps1, *.py | Where-Object { $_.FullName -notmatch '\\\.venv\\' })
$psParserHits = @(Select-String -Path $scanFiles.FullName -Pattern '\^\\\|.*\(\[a-z0-9_' -ErrorAction SilentlyContinue | Where-Object { $_.Path -notmatch 'selftest\.ps1' })
$psUnsanctioned = @($psParserHits | Where-Object { $_.Path -notmatch '_registry\.ps1' })
Ok "the sanctioned PS registry parser exists" (@($psParserHits | Where-Object { $_.Path -match '_registry\.ps1' }).Count -ge 1)
Ok "no unsanctioned PS registry parser (Q2)" ($psUnsanctioned.Count -eq 0)
$pyParserHits = @(Select-String -Path $scanFiles.FullName -Pattern 'startswith\("\|"\)' -ErrorAction SilentlyContinue)
Ok "no Python registry parser at all (Q2)" ($pyParserHits.Count -eq 0)

Write-Host "== 9c. registry parser is robust to junk (T3) =="
# Feed Get-SonelleProjects malformed rows: it must neither throw nor return junk, and must trim cells.
$fuzzReg = Join-Path $env:TEMP 'sonelle_fuzz_PROJECTS.md'
$fuzzLines = @(
  '# Projects', '',
  '| Shortcode | Project | Code path |',          # capital header -> skipped
  '|---|---|---|',                                 # separator -> skipped
  '| good | Good Proj | C:\code\good |',           # valid
  '| bad ',                                        # missing cells / no closing pipe -> skipped
  '|   | Empty Short | C:\x |',                    # empty short -> skipped
  '| spaced |   Trimmed   |   C:\s\path   |',      # extra spaces -> trimmed
  'not a table row at all',                        # prose -> skipped
  '| piped | P | C:\a|b\c |',                      # pipe inside path -> must not throw
  '| UPPER | caps short | C:\u |')                 # uppercase short -> skipped by [a-z0-9_]
[System.IO.File]::WriteAllText($fuzzReg, ($fuzzLines -join "`r`n"))
$threw = $false; $fz = @()
try { $fz = Get-SonelleProjects $fuzzReg } catch { $threw = $true }
Ok "parser does not throw on malformed rows (T3)" (-not $threw)
$fzShorts = @($fz | ForEach-Object { $_.Short })
Ok "parser keeps only valid lowercase shorts" (($fzShorts -contains 'good') -and ($fzShorts -contains 'spaced') -and ($fzShorts -contains 'piped') -and (-not ($fzShorts -contains 'upper')) -and (-not ($fzShorts -contains 'shortcode')) -and (-not ($fzShorts -contains 'bad')))
$spacedRow = $fz | Where-Object { $_.Short -eq 'spaced' } | Select-Object -First 1
Ok "parser trims cells" (($spacedRow.Name -eq 'Trimmed') -and ($spacedRow.CodePath -eq 'C:\s\path'))
Remove-Item $fuzzReg -Force -ErrorAction SilentlyContinue

Write-Host "== 10. cost report (reads local transcript usage) =="
# hermetic: point cost.ps1 at a FAKE ~/.claude/projects via SONELLE_CLAUDE_PROJECTS and drop one
# usage line in the encoded folder for the 'mc' project, then assert the tallies + dollar estimate.
$fakeProj = Join-Path $tmp 'claude_projects'
$encMc = ($mcpPath -replace '[:\\/]', '-')
$encDir = Join-Path $fakeProj $encMc
New-Item -ItemType Directory -Path $encDir -Force | Out-Null
$usageLine = '{"type":"assistant","message":{"model":"claude-opus-4-x","usage":{"input_tokens":1000,"output_tokens":500,"cache_creation_input_tokens":0,"cache_read_input_tokens":200}}}'
[System.IO.File]::WriteAllText((Join-Path $encDir 'sess.jsonl'), $usageLine + "`n")
$savedCP = $env:SONELLE_CLAUDE_PROJECTS
$env:SONELLE_CLAUDE_PROJECTS = $fakeProj
try {
  $costOut  = (& $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $engine 'tools\cost.ps1') -Short mc -Hub $tmp) -join "`n"
  $costOut2 = (& $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $engine 'tools\cost.ps1') -Short st -Hub $tmp) -join "`n"
} finally { $env:SONELLE_CLAUDE_PROJECTS = $savedCP }
Ok "cost reports the project + token totals"    (($costOut -match '(?m)\bmc\b') -and ($costOut -match '1,000') -and ($costOut -match '500'))
Ok "cost estimates a dollar figure (opus rates)" ($costOut -match '\$0\.0176')
Ok "cost handles a project with no transcript"   ($costOut2 -match 'no transcript')

Write-Host "== 11. repo map (structural primer) =="
$rmDir = Join-Path $tmp 'repomap_src'
New-Item -ItemType Directory -Path (Join-Path $rmDir 'sub') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $rmDir 'node_modules') -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $rmDir 'app.py'), "class Server:`n    def handle(self):`n        pass`ndef main():`n    pass`n")
[System.IO.File]::WriteAllText((Join-Path $rmDir 'sub\util.js'), "export function parse(x) {`n  return x`n}`nconst run = () => 1`n")
[System.IO.File]::WriteAllText((Join-Path $rmDir 'tool.ps1'), "function Get-Thing { 'x' }`n")
[System.IO.File]::WriteAllText((Join-Path $rmDir 'README.md'), "# not code`n")
[System.IO.File]::WriteAllText((Join-Path $rmDir 'node_modules\dep.js'), "function shouldBeSkipped() {}`n")
$rmOut = (& $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $engine 'tools\repomap.ps1') -Path $rmDir) -join "`n"
Ok "repomap finds python defs/classes"  (($rmOut -match 'app\.py') -and ($rmOut -match 'class Server') -and ($rmOut -match 'def main'))
Ok "repomap finds js functions"         (($rmOut -match 'util\.js') -and ($rmOut -match 'parse'))
Ok "repomap finds powershell functions" (($rmOut -match 'tool\.ps1') -and ($rmOut -match 'Get-Thing'))
Ok "repomap skips non-code (README.md)" (-not ($rmOut -match 'README\.md'))
Ok "repomap prunes node_modules"        (-not ($rmOut -match 'shouldBeSkipped'))
$rmFile = Join-Path $tmp 'RM.md'
& $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $engine 'tools\repomap.ps1') -Path $rmDir -Out $rmFile | Out-Null
Ok "repomap -Out writes a map file"     ((Test-Path $rmFile) -and ((Get-Content $rmFile -Raw) -match 'app\.py'))

Write-Host "== 12. Claude Code plugin (portable skills, installable via marketplace) =="
$plugRoot = Join-Path $engine 'plugin'
$mkt = Join-Path $engine '.claude-plugin\marketplace.json'
Ok "repo is a plugin marketplace"                  (Test-Path $mkt)
$mktObj = $null; try { $mktObj = Get-Content $mkt -Raw | ConvertFrom-Json } catch {}
Ok "marketplace.json valid + lists sonelle-skills" ($mktObj -and $mktObj.name -and (@($mktObj.plugins | Where-Object { $_.name -eq 'sonelle-skills' }).Count -eq 1))
$pm = $null; try { $pm = Get-Content (Join-Path $plugRoot '.claude-plugin\plugin.json') -Raw | ConvertFrom-Json } catch {}
Ok "plugin.json valid + has the required name"     ($pm -and $pm.name)
Ok "plugin bundles all six skills"                 (@(Get-ChildItem (Join-Path $plugRoot 'skills') -Directory -ErrorAction SilentlyContinue).Count -eq 6)
# single source of truth: the committed plugin skills must equal a fresh build from templates\skills
$built = Join-Path $tmp 'plugin_build'
& $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $engine 'tools\build_plugin.ps1') -Out $built | Out-Null
$pdrift = @()
foreach ($sk in (Get-ChildItem (Join-Path $engine 'templates\skills') -Directory)) {
  $a = Join-Path $plugRoot ('skills\' + $sk.Name + '\SKILL.md')
  $b = Join-Path $built ('skills\' + $sk.Name + '\SKILL.md')
  if (-not (Test-Path $a)) { $pdrift += ($sk.Name + ' missing'); continue }
  if ((Get-Content $a -Raw) -ne (Get-Content $b -Raw)) { $pdrift += $sk.Name }
}
Ok "committed plugin matches a fresh build (run build_plugin to resync)" ($pdrift.Count -eq 0)

if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }

Write-Host ""
if ($script:fail -eq 0) { Write-Host ("[selftest] ALL PASS ({0} checks)" -f $script:pass) -ForegroundColor Green; exit 0 }
else { Write-Host ("[selftest] {0} FAIL / {1} pass" -f $script:fail, $script:pass) -ForegroundColor Red; exit 1 }
