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
function Ok($label, $cond) {
  if ($cond) { Write-Host ("  [PASS] {0}" -f $label) -ForegroundColor Green }
  else { Write-Host ("  [FAIL] {0}" -f $label) -ForegroundColor Red; $script:fail++ }
}

Write-Host "== 1. parse + ASCII (all .ps1) =="
Get-ChildItem $engine -Recurse -Filter *.ps1 | ForEach-Object {
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

Write-Host "== 2. scaffold into a temp hub =="
$tmp = Join-Path $env:TEMP 'luna_selftest'
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
Ok "project luna.check.ps1 created" (Test-Path (Join-Path $codePath 'luna.check.ps1'))
$vj = $true; try { [void](Get-Content (Join-Path $codePath '.claude\settings.json') -Raw | ConvertFrom-Json) } catch { $vj = $false }
Ok "project settings.json is valid JSON" $vj

Write-Host "== 3. check_pointers on temp hub =="
& $ps -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'check_pointers.ps1') -Hub $tmp | Out-Null
Ok "check_pointers exit 0"         ($LASTEXITCODE -eq 0)

Write-Host "== 4. doctor on temp hub =="
& $ps -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'doctor.ps1') -Hub $tmp | Out-Null
Ok "doctor healthy (exit 0)"       ($LASTEXITCODE -eq 0)

Write-Host "== 5. duplicate guard =="
& $ps -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'new_project.ps1') st "Dup" $codePath -Hub $tmp | Out-Null
Ok "duplicate rejected (exit 1)"   ($LASTEXITCODE -eq 1)

Write-Host "== 5b. multi-instance dry-run =="
& $ps -ExecutionPolicy Bypass -File (Join-Path $engine 'bin\luna_team.ps1') st -Lanes a=haiku,b -Hub $tmp -DryRun | Out-Null
Ok "luna_team dry-run exit 0"        ($LASTEXITCODE -eq 0)
Ok "lane board written"             (Test-Path (Join-Path $codePath '.luna\lanes\a.md'))
Ok "lane start script written"      (Test-Path (Join-Path $codePath '.luna\lanes\a.start.ps1'))
$le=$null;$lt=$null;[void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $codePath '.luna\lanes\a.start.ps1'),[ref]$lt,[ref]$le)
Ok "lane start script parses"       ($le.Count -eq 0)
Ok "lane per-model in start script" ((Get-Content (Join-Path $codePath '.luna\lanes\a.start.ps1') -Raw) -match '--model haiku')

Write-Host "== 6. check_pointers DETECTS a broken pointer (negative test) =="
Remove-Item $codePath -Recurse -Force
& $ps -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'check_pointers.ps1') -Hub $tmp | Out-Null
Ok "check_pointers exit 1 on a missing code path" ($LASTEXITCODE -eq 1)

Write-Host "== 7. .gitignore ignores the private paths =="
if (Get-Command git -ErrorAction SilentlyContinue) {
  foreach ($f in @('luna.config.json', 'memory/x.md', 'FOO_TODO.txt')) {
    Ok "gitignored: $f" ([bool](git -C $engine check-ignore $f))
  }
} else { Write-Host "  [skip] git not on PATH" -ForegroundColor DarkGray }

if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }

Write-Host ""
if ($script:fail -eq 0) { Write-Host "[selftest] ALL PASS" -ForegroundColor Green; exit 0 }
else { Write-Host ("[selftest] {0} FAIL" -f $script:fail) -ForegroundColor Red; exit 1 }
