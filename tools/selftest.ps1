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

# T2: golden snapshot - the template SET and the scaffold MANIFEST must stay stable, so an accidental
# template/scaffold change that would alter every new project trips this test (a conscious change updates it).
$tplDir  = Join-Path $engine 'templates'
$tplGot  = @(Get-ChildItem $tplDir -Recurse -File | ForEach-Object { $_.FullName.Substring($tplDir.Length + 1).Replace('\', '/') } | Sort-Object)
$tplWant = @('CLAUDE.template.md', 'TODO.template.txt', 'hooks/session_start.ps1', 'hooks/stop.ps1', 'lesson.template.md', 'project_memory.template.md', 'run_STATUS.template.md', 'settings.template.json') | Sort-Object
Ok "template set is exactly the known golden (T2)" (($tplGot -join '|') -eq ($tplWant -join '|'))
$manifestOk = $true
foreach ($f in @((Join-Path $tmp 'ST_TODO.txt'), (Join-Path $tmp '_st_run_STATUS.md'), (Join-Path $codePath 'CLAUDE.md'), (Join-Path $codePath 'sonelle.check.ps1'), (Join-Path $codePath '.claude\settings.json'), (Join-Path $codePath '.claude\hooks\session_start.ps1'), (Join-Path $codePath '.claude\hooks\stop.ps1'), (Join-Path $tmp 'memory\project_st.md'), (Join-Path $tmp 'memory\MEMORY.md'))) {
  if (-not (Test-Path $f)) { $manifestOk = $false }
}
Ok "scaffold produces the full golden manifest (T2)" $manifestOk

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

Write-Host "== 5b. multi-instance dry-run =="
& $ps -ExecutionPolicy Bypass -File (Join-Path $engine 'bin\sonelle_team.ps1') st -Lanes a=haiku,b -Hub $tmp -DryRun | Out-Null
Ok "sonelle_team dry-run exit 0"        ($LASTEXITCODE -eq 0)
Ok "lane board written"             (Test-Path (Join-Path $codePath '.sonelle\lanes\a.md'))
Ok "lane start script written"      (Test-Path (Join-Path $codePath '.sonelle\lanes\a.start.ps1'))
$le=$null;$lt=$null;[void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $codePath '.sonelle\lanes\a.start.ps1'),[ref]$lt,[ref]$le)
Ok "lane start script parses"       ($le.Count -eq 0)
Ok "lane per-model in start script" ((Get-Content (Join-Path $codePath '.sonelle\lanes\a.start.ps1') -Raw) -match '--model haiku')
Ok "lane permission-mode in start script" ((Get-Content (Join-Path $codePath '.sonelle\lanes\a.start.ps1') -Raw) -match '--permission-mode')
# R3: -Verify catches overlapping ownership before a launch can clobber files.
$laneA = Join-Path $codePath '.sonelle\lanes\a.md'
$laneB = Join-Path $codePath '.sonelle\lanes\b.md'
((Get-Content $laneA -Raw) -replace '(?m)^owns:.*$', 'owns: src/, docs/api.md') | Set-Content $laneA
((Get-Content $laneB -Raw) -replace '(?m)^owns:.*$', 'owns: src/components/, README.md') | Set-Content $laneB
$verOut = & $ps -ExecutionPolicy Bypass -File (Join-Path $engine 'bin\sonelle_team.ps1') st -Verify -Hub $tmp
Ok "lane -Verify flags overlapping ownership (R3)" ((($verOut -join "`n")) -match 'CONFLICT')
Ok "lane -Verify exits 1 on conflict"      ($LASTEXITCODE -eq 1)
((Get-Content $laneA -Raw) -replace '(?m)^owns:.*$', 'owns: src/, docs/api.md') | Set-Content $laneA
((Get-Content $laneB -Raw) -replace '(?m)^owns:.*$', 'owns: tests/, README.md') | Set-Content $laneB
$verOk = & $ps -ExecutionPolicy Bypass -File (Join-Path $engine 'bin\sonelle_team.ps1') st -Verify -Hub $tmp
Ok "lane -Verify passes when ownership is disjoint" (($LASTEXITCODE -eq 0) -and ((($verOk -join "`n")) -match 'no ownership overlap'))

Write-Host "== 5c. app (multi-terminal shell) =="
$appPath = Join-Path $engine 'bin\sonelle_app.ps1'
Ok "sonelle_app.ps1 exists"      (Test-Path $appPath)
$srcApp = if (Test-Path $appPath) { Get-Content $appPath -Raw } else { '' }
Ok "app embeds via SetParent"    ($srcApp -match 'SetParent')
Ok "app hosts the sonelle terminal" ($srcApp -match "bin\\\\sonelle\.ps1|'bin\\\\sonelle\.ps1'|sonelle\.ps1")
Ok "app has New-Terminal"        ($srcApp -match 'function New-Terminal')
Ok "app has a -SelfTest mode"    ($srcApp -match '\[switch\]\$SelfTest')
Ok "app themed clay accent"      ($srcApp -match '204,\s*120,\s*92')
$appOut = & $ps -NoProfile -Sta -ExecutionPolicy Bypass -File $appPath -SelfTest 2>&1
Ok "app -SelfTest exit 0"        ($LASTEXITCODE -eq 0)
Ok "app -SelfTest builds the UI" (($appOut -join "`n") -match 'SELFTEST (OK|SKIP)')

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

Write-Host "== 5d. routing invokes claude correctly (behavioral, T1/T4) =="
# Put a fake `claude` on PATH that records its argv + cwd, drive the terminal over stdin, and assert it
# handed claude the right model/effort, cd'd into the project, and honored -Yolo. Env that would leak
# (SONELLE_YOLO / SONELLE_NARRATE_SETTINGS from a live session) is neutralized so the test is deterministic.
$stub = Join-Path $tmp 'stub'; New-Item -ItemType Directory -Path $stub -Force | Out-Null
$cap  = Join-Path $stub 'cap.txt'
$stubLines = @('@echo off', 'echo %*> "%SONELLE_STUB_CAP%"', 'cd >> "%SONELLE_STUB_CAP%"', 'exit 0')
[System.IO.File]::WriteAllText((Join-Path $stub 'claude.cmd'), ($stubLines -join "`r`n") + "`r`n")
$savedPath = $env:Path; $savedYolo = $env:SONELLE_YOLO; $savedNarr = $env:SONELLE_NARRATE_SETTINGS
$env:SONELLE_YOLO = ''; $env:SONELLE_NARRATE_SETTINGS = ''; $env:Path = "$stub;$env:Path"; $env:SONELLE_STUB_CAP = $cap
try {
  if (Test-Path $cap) { Remove-Item $cap -Force }
  "st: hello`r`n:q`r`n" | & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $engine 'bin\sonelle.ps1') -Hub $tmp -Bare | Out-Null
  $capTxt = if (Test-Path $cap) { Get-Content $cap -Raw } else { '' }
  Ok "routing passes --model opus --effort xhigh" (($capTxt -match '--model') -and ($capTxt -match 'opus') -and ($capTxt -match '--effort') -and ($capTxt -match 'xhigh'))
  Ok "routing cd's into the project code path"     ($capTxt -match [regex]::Escape($codePath))
  Ok "no yolo => no bypassPermissions"             (-not ($capTxt -match 'bypassPermissions'))
  if (Test-Path $cap) { Remove-Item $cap -Force }
  "st: hello`r`n:q`r`n" | & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $engine 'bin\sonelle.ps1') -Hub $tmp -Bare -Yolo | Out-Null
  $capYolo = if (Test-Path $cap) { Get-Content $cap -Raw } else { '' }
  Ok "yolo => --permission-mode bypassPermissions" (($capYolo -match '--permission-mode') -and ($capYolo -match 'bypassPermissions'))
} finally {
  $env:Path = $savedPath; $env:SONELLE_YOLO = $savedYolo; $env:SONELLE_NARRATE_SETTINGS = $savedNarr
  Remove-Item Env:\SONELLE_STUB_CAP -ErrorAction SilentlyContinue
}

Write-Host "== 6. check_pointers DETECTS a broken pointer (negative test) =="
Remove-Item $codePath -Recurse -Force
& $ps -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'check_pointers.ps1') -Hub $tmp | Out-Null
Ok "check_pointers exit 1 on a missing code path" ($LASTEXITCODE -eq 1)

Write-Host "== 7. .gitignore ignores the private paths =="
if (Get-Command git -ErrorAction SilentlyContinue) {
  foreach ($f in @('sonelle.config.json', 'memory/x.md', 'FOO_TODO.txt')) {
    Ok "gitignored: $f" ([bool](git -C $engine check-ignore $f))
  }
} else { Write-Host "  [skip] git not on PATH" -ForegroundColor DarkGray }

Write-Host "== 8. self-develop wiring =="
$srcTerm = Get-Content (Join-Path $engine 'bin\sonelle.ps1') -Raw
Ok "terminal has a :dev handler"   ($srcTerm -match '\^:dev')
Ok "terminal has DevSelf function" ($srcTerm -match 'function DevSelf')
Ok "DEVELOPING.md exists"          (Test-Path (Join-Path $engine 'docs\DEVELOPING.md'))
Ok "dispatcher points to self-dev" ((Get-Content (Join-Path $engine 'CLAUDE.md') -Raw) -match 'DEVELOPING\.md|:dev')
Ok "DevSelf seeds + guards engine"  (($srcTerm -match 'IGNORE its dispatcher') -and ($srcTerm -match 'hub-state'))
Ok "self shortcode from folder name" ($srcTerm -match 'selfShort\s*=\s*\(Split-Path')
Ok "self-name routes to engine dev"  ($srcTerm -match '\$short -eq \$script:selfShort')
Ok "terminal has an :app handler"    ($srcTerm -match "'?:app'?")
Ok "terminal has AppLaunch function" ($srcTerm -match 'function AppLaunch')
Ok "AppLaunch opens the glass app"   ($srcTerm -match 'sonelle_gui\.ps1')
Ok "AppLaunch caches the dep probe (P1)" (($srcTerm -match '\.deps_ok') -and ($srcTerm -match 'requirements\.txt'))
Ok "terminal has an :app-classic handler" ($srcTerm -match ':app-classic')
Ok "AppLaunchClassic opens WinForms -Sta" (($srcTerm -match 'function AppLaunchClassic') -and ($srcTerm -match 'sonelle_app\.ps1') -and ($srcTerm -match "'-Sta'"))
Ok "terminal has a -Yolo switch"      ($srcTerm -match '\[switch\]\$Yolo')
Ok "terminal has a :yolo toggle"      ($srcTerm -match '\^:yolo')
Ok "-Yolo / SONELLE_YOLO sets bypass" (($srcTerm -match '\$Yolo -or \$env:SONELLE_YOLO') -and ($srcTerm -match 'bypassPermissions'))
$srcLnk = Get-Content (Join-Path $engine 'bin\make_launcher.ps1') -Raw
Ok "make_launcher default opens the glass app" ($srcLnk -match 'sonelle_gui\.ps1')
Ok "make_launcher -Classic opens WinForms" ($srcLnk -match 'sonelle_app\.ps1')
Ok "make_launcher has -Terminal + -Classic" (($srcLnk -match '\[switch\]\$Terminal') -and ($srcLnk -match '\[switch\]\$Classic'))

Write-Host "== 8b. terminal welcome + help (UI) =="
$demoOut = & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $engine 'bin\sonelle.ps1') -Demo
$demoExit = $LASTEXITCODE
$demoStr  = (($demoOut -join "`n") -replace "$([char]27)\[[0-9;]*m", '')
Ok "terminal -Demo exit 0"             ($demoExit -eq 0)
Ok "welcome shows brand + tagline"     (($demoStr -match 'sonelle') -and ($demoStr -match 'your projects, one orchestrator'))
Ok "welcome no longer dumps all commands" (-not ($demoStr -match ':projects'))
$bareOut = & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $engine 'bin\sonelle.ps1') -Demo -Bare
$bareStr = (($bareOut -join "`n") -replace "$([char]27)\[[0-9;]*m", '')
Ok "bare mode suppresses the welcome" (-not ($bareStr -match 'orchestrator'))
Ok "terminal has a Welcome function"   ($srcTerm -match 'function Welcome')
Ok "welcome uses runtime box glyphs"   (($srcTerm -match '0x256D') -and ($srcTerm -match '0x2570'))
Ok ":help lists every command"         (($srcTerm -match 'function ShowHelp') -and (@(':projects',':new',':heal',':team',':status',':app',':dev',':yolo',':attach',':clear',':help',':q') | Where-Object { $srcTerm -notmatch [regex]::Escape($_) }).Count -eq 0)
# invariant #4: the engine root must stay clean of hub state (no project TODO/ledger/memory)
$rootTodo = @(Get-ChildItem $engine -Filter '*_TODO.txt' -File -ErrorAction SilentlyContinue).Count
$rootLedg = @(Get-ChildItem $engine -Filter '_*_run_STATUS.md' -File -ErrorAction SilentlyContinue).Count
Ok "engine root clean (no hub state)" (($rootTodo -eq 0) -and ($rootLedg -eq 0) -and (-not (Test-Path (Join-Path $engine 'memory'))))

Write-Host "== 8e. python glass app (sonelle_gui) =="
$appDir = Join-Path $engine 'app'
$guiPy  = Join-Path $appDir 'sonelle_gui.py'
foreach ($rel in @(
  'app\sonelle_gui.py', 'app\requirements.txt', 'app\ui\index.html', 'app\ui\app.js', 'app\ui\app.css',
  'app\ui\vendor\xterm.js', 'app\ui\vendor\xterm.css', 'app\ui\vendor\addon-fit.js', 'app\ui\vendor\addon-webgl.js',
  'bin\sonelle_gui.ps1', 'assets\icon\sonelle.ico')) {
  Ok ("exists: " + $rel) (Test-Path (Join-Path $engine $rel))
}
$srcGui = if (Test-Path $guiPy) { Get-Content $guiPy -Raw } else { '' }
Ok "backend exposes the api contract" (($srcGui -match 'def new_tab') -and ($srcGui -match 'def send_input') -and ($srcGui -match 'def resize') -and ($srcGui -match 'def close_tab') -and ($srcGui -match 'def list_projects'))
Ok "backend pushes via __ptyOutput"   ($srcGui -match '__ptyOutput')
Ok "backend spawns sonelle.ps1 -Bare" ($srcGui -match '"-Bare"')
Ok "backend kills the process tree"   ($srcGui -match 'taskkill')
Ok "backend brands window with sonelle icon" (($srcGui -match 'sonelle\.ico') -and ($srcGui -match '"icon"'))
Ok "backend claims its taskbar identity" ($srcGui -match 'SetCurrentProcessExplicitAppUserModelID')
Ok "backend saves pasted images"      ($srcGui -match 'def save_paste_image')
Ok "backend setwinsize(rows, cols)"   ($srcGui -match 'setwinsize\(rows, cols\)')
Ok "backend forwards -Yolo on SONELLE_YOLO" (($srcGui -match 'SONELLE_YOLO') -and ($srcGui -match '"-Yolo"'))
Ok "backend has a _dbg trail at swallow sites (R4)" (($srcGui -match 'def _dbg') -and (@([regex]::Matches($srcGui, '_dbg\(')).Count -ge 6))
$srcJs = Get-Content (Join-Path $appDir 'ui\app.js') -Raw
Ok "frontend has output sink + ready gate" (($srcJs -match 'window\.__ptyOutput') -and ($srcJs -match 'pywebviewready'))
Ok "frontend uses FitAddon.FitAddon"  ($srcJs -match 'new FitAddon\.FitAddon\(\)')
Ok "frontend mounts the WebGL renderer" (($srcJs -match 'WebglAddon\.WebglAddon') -and ($srcJs -match 'function mountWebgl'))
Ok "frontend debounces resize fits"   ($srcJs -match 'function scheduleFit')
Ok "frontend scrollback is configurable (P2)" (($srcJs -match 'const SCROLLBACK') -and ($srcJs -match "localStorage\.getItem\(`"sonelle\.scrollback`"\)") -and ($srcJs -match 'scrollback: SCROLLBACK') -and (-not ($srcJs -match 'scrollback: 5000')))
Ok "frontend decodes base64 in one pass (P3)" (($srcJs -match 'Uint8Array\.from\(atob') -and (-not ($srcJs -match 'for \(let i = 0; i < bin\.length')))
Ok "frontend numbers tabs (1, 2, 3...)" (($srcJs -match 'function nextTabName') -and ($srcJs -match 'String\(\+\+tabSeq\)') -and (-not ($srcJs -match 'pickName')) -and (-not ($srcJs -match 'SONELLE_NAMES')))
Ok "frontend pastes images via save_paste_image" (($srcJs -match 'save_paste_image') -and ($srcJs -match '"paste"'))
Ok "frontend guards titlebar drag"    ($srcJs -match "closest\(`"\.nodrag`"\)")
$srcCss = Get-Content (Join-Path $appDir 'ui\app.css') -Raw
Ok "css gives the terminal a scrollbar gutter" (($srcCss -match '\.pane \.xterm\{ padding-right') -and ($srcCss -match 'xterm-viewport::-webkit-scrollbar'))
$srcHtml = Get-Content (Join-Path $appDir 'ui\index.html') -Raw
Ok "index loads vendored xterm + app.js" (($srcHtml -match 'vendor/xterm\.js') -and ($srcHtml -match 'app\.js'))
Ok "index loads the WebGL addon"      ($srcHtml -match 'vendor/addon-webgl\.js')
Ok "the women's-name pool is gone"    ((-not (Test-Path (Join-Path $appDir 'ui\names.js'))) -and (-not ($srcHtml -match 'names\.js')))
Ok "titlebar is a pywebview drag region" ($srcHtml -match 'pywebview-drag-region')
Ok "brand marks render the app icon (svg, not gradient cubes)" (($srcHtml -match '<svg class="mark"') -and ($srcHtml -match '<svg class="w-mark"') -and ($srcHtml -match 'stroke="#FF9B85"') -and (-not ($srcCss -match '\.brand \.mark\{[^}]*linear-gradient')) -and (-not ($srcCss -match '\.welcome \.w-mark\{[^}]*linear-gradient')))
Ok "brand loop gif is a transparent-fill, soft bordered card" (($srcHtml -match 'id="brandloop"') -and ($srcHtml -match 'src="brandloop\.gif"') -and (Test-Path (Join-Path $appDir 'ui\brandloop.gif')) -and ($srcCss -match '\.brandloop\{') -and ($srcCss -match '\.brandloop\{[^}]*background:transparent') -and ($srcCss -match '\.brandloop\{[^}]*border-radius') -and ($srcCss -match '\.brandloop\{[^}]*pointer-events:auto'))
Ok "brand loop drags with throw/bounce + drifts home" (($srcJs -match 'function wireBrandloopDrag') -and ($srcJs -match 'function throwLoop') -and ($srcJs -match 'RESTITUTION') -and ($srcJs -match 'function returnLoopHome') -and ($srcJs -match 'function scheduleLoopReturn'))
# the gif sits LOW (small bottom, over the send-button corner) and the pane reserves a big bottom band
# so the terminal grid stops ABOVE it (text stops before the gif, never drawn/hidden under it). It is
# also pulled IN off the right edge (right > scrollbar lane) so the scrollbar is never under it.
$loopLow = ($srcCss -match '\.brandloop\{[^}]*bottom:\s*(\d+)px') -and ([int]$Matches[1] -le 24)
$loopOffScrollbar = ($srcCss -match '\.brandloop\{[^}]*right:\s*(\d+)px') -and ([int]$Matches[1] -ge 24)
$paneReserve = ($srcCss -match '\.pane\{[^}]*padding:\s*\d+px\s+\d+px\s+(\d+)px\s+\d+px') -and ([int]$Matches[1] -ge 40)
Ok "terminal reserves a bottom band so text stops above the low brand loop" ($loopLow -and $paneReserve)
Ok "brand loop is pulled in off the scrollbar lane" $loopOffScrollbar
# the command-bar PANEL stops before the gif: #bar reserves a right band so the whole glass cmdbar
# (input + send button) parks to the LEFT of the gif - it sits in its own corner, nothing under it
$barReserve = ($srcCss -match '#bar\{[^}]*padding-right:\s*(\d+)px') -and ([int]$Matches[1] -ge 120)
Ok "command bar panel stops before the brand loop (its own clear corner)" $barReserve
$srcGuiPs = Get-Content (Join-Path $engine 'bin\sonelle_gui.ps1') -Raw
Ok "launcher installs deps + runs pythonw" (($srcGuiPs -match 'requirements\.txt') -and ($srcGuiPs -match 'pythonw'))
$pyCmd = Get-Command py -ErrorAction SilentlyContinue
if (-not $pyCmd) { $pyCmd = Get-Command python -ErrorAction SilentlyContinue }
if ($pyCmd -and (Test-Path $guiPy)) {
  $pyArgs = @(); if ($pyCmd.Source -match '\\py\.exe$') { $pyArgs += '-3' }
  & $pyCmd.Source @pyArgs -m py_compile $guiPy 2>$null
  Ok "sonelle_gui.py compiles"        ($LASTEXITCODE -eq 0)
} else {
  Write-Host "  [skip] no python on PATH for py_compile" -ForegroundColor DarkGray
}
$venvPy = Join-Path $engine '.venv\Scripts\python.exe'
if (Test-Path $venvPy) {
  & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $engine 'bin\sonelle_gui.ps1') -NoLaunch | Out-Null
  Ok "launcher -NoLaunch verifies deps (exit 0)" ($LASTEXITCODE -eq 0)
} else {
  Write-Host "  [skip] no .venv for launcher -NoLaunch check" -ForegroundColor DarkGray
}

Write-Host "== 8f. voice narrator =="
$narrPy = Join-Path $engine 'app\narrator.py'
$ttsPy  = Join-Path $engine 'app\tts.py'
$hookPs = Join-Path $engine 'app\narrate_hook.ps1'
foreach ($rel in @('app\narrator.py', 'app\tts.py', 'app\narrate_hook.ps1')) {
  Ok ("exists: " + $rel) (Test-Path (Join-Path $engine $rel))
}
$srcHook = if (Test-Path $hookPs) { Get-Content $hookPs -Raw } else { '' }
Ok "hook appends events to SONELLE_NARRATE_FILE" (($srcHook -match 'SONELLE_NARRATE_FILE') -and ($srcHook -match 'Add-Content') -and ($srcHook -match 'exit 0'))
$srcNarr = if (Test-Path $narrPy) { Get-Content $narrPy -Raw } else { '' }
Ok "narrator builds hooks settings, gated on --settings support" (($srcNarr -match 'def setup') -and ($srcNarr -match '_claude_supports_settings') -and ($srcNarr -match '--settings'))
Ok "narrator writes first-person texting lines, tagged voice/status" (($srcNarr -match 'class TabNarrator') -and ($srcNarr -match 'def build_line') -and ($srcNarr -match '_PHRASES') -and ($srcNarr -match '_VOICE_CATS'))
Ok "narrator maps the claude hook events"  (($srcNarr -match 'PreToolUse') -and ($srcNarr -match 'PostToolUse') -and ($srcNarr -match 'Notification') -and ($srcNarr -match 'Stop') -and ($srcNarr -match 'def events_file_for'))
Ok "narrator speaks short answers (last_assistant_message)" (($srcNarr -match 'last_assistant_message') -and ($srcNarr -match 'def _clean_speech'))
$srcTts = if (Test-Path $ttsPy) { Get-Content $ttsPy -Raw } else { '' }
Ok "tts has kokoro (local neural) + edge + sapi engines" (($srcTts -match 'def synth') -and ($srcTts -match '_synth_kokoro') -and ($srcTts -match '_synth_edge') -and ($srcTts -match '_synth_sapi'))
Ok "tts loads the kokoro model bundled in the repo (no download)" (($srcTts -match 'def _kokoro_files') -and ($srcTts -match 'kokoro-v1\.0\.int8\.onnx') -and (-not ($srcTts -match 'urllib')) -and (-not ($srcTts -match 'def _download')))
Ok "kokoro voice model is vendored in the repo" ((Test-Path (Join-Path $engine 'app\voice\kokoro-v1.0.int8.onnx')) -and (Test-Path (Join-Path $engine 'app\voice\voices-v1.0.bin')))
Ok "backend imports + wires the narrator" (($srcGui -match 'import narrator') -and ($srcGui -match 'def set_narration') -and ($srcGui -match 'def _narrate_emit') -and ($srcGui -match '__narrate'))
Ok "backend passes the voice/status kind to __narrate" ($srcGui -match '__narrate\(%s,%s,%s,%s,%s\)')
Ok "backend sets the per-tab events env"  ($srcGui -match 'SONELLE_NARRATE_FILE')
Ok "backend runs narrator.setup + publishes settings" (($srcGui -match 'narrator\.setup') -and ($srcGui -match 'SONELLE_NARRATE_SETTINGS'))
Ok "terminal attaches --settings on the narrate env" (($srcTerm -match 'SONELLE_NARRATE_SETTINGS') -and ($srcTerm -match "'--settings'"))
Ok "frontend has the narrate sink + per-tab voice toggle" (($srcJs -match 'window\.__narrate') -and ($srcJs -match 'function toggleTabVoice') -and ($srcJs -match 'function updateTabVoiceEl') -and ($srcJs -match 'set_narration'))
Ok "voice toggle is per-tab (speaker on each pill)" (($srcJs -match 'spk\.className = "spk"') -and ($srcCss -match '\.tab \.spk\{') -and (-not ($srcHtml -match 'id="btn-voice"')))
Ok "narration types into the terminal: pink voice / white status" (($srcJs -match 'function typeNarration') -and ($srcJs -match 'PINK_SGR') -and ($srcJs -match '255;121;198') -and ($srcJs -match 'STATUS_SGR') -and (-not ($srcCss -match '\.narration \.line\{')))
Ok "narration is serialized against pty output (no interleave)" (($srcJs -match 'function writeOrHold') -and ($srcJs -match 'holdback') -and ($srcJs -match 'function runNarrQueue'))
# the bug fixes shipped in this round
Ok "pusher survives the shutdown poison pill" ($srcGui -match 'poisoned')
Ok "ctrl+c respects a composer selection" ($srcJs -match 'inp\.selectionStart')
Ok "ctrl+t opens a new terminal"          ($srcJs -match 'key === "t"')
Ok "read-only pane wheel scrolls scrollback" (($srcJs -match '"wheel"') -and ($srcJs -match 'scrollLines') -and ($srcJs -match 'capture: true'))
Ok "requirements pin edge-tts"            ((Get-Content (Join-Path $engine 'app\requirements.txt') -Raw) -match 'edge-tts')
Ok "kokoro voice req exists + launcher installs it" ((Test-Path (Join-Path $engine 'app\requirements-voice.txt')) -and ((Get-Content (Join-Path $engine 'app\requirements-voice.txt') -Raw) -match 'kokoro-onnx') -and ($srcGuiPs -match 'requirements-voice'))
if ($pyCmd -and (Test-Path $narrPy)) {
  $pyArgs = @(); if ($pyCmd.Source -match '\\py\.exe$') { $pyArgs += '-3' }
  & $pyCmd.Source @pyArgs -m py_compile $narrPy $ttsPy 2>$null
  Ok "narrator.py + tts.py compile"       ($LASTEXITCODE -eq 0)
} else {
  Write-Host "  [skip] no python on PATH for py_compile" -ForegroundColor DarkGray
}

Write-Host "== 8g. shared knowledge base =="
$kbIdx = Join-Path $engine 'knowledge\INDEX.md'
Ok "knowledge/INDEX.md exists"          (Test-Path $kbIdx)
foreach ($rel in @('knowledge\powershell-commit-heredoc.md', 'knowledge\powershell-pure-ascii.md')) {
  Ok ("seed lesson: " + $rel)           (Test-Path (Join-Path $engine $rel))
}
$srcKbIdx = if (Test-Path $kbIdx) { Get-Content $kbIdx -Raw } else { '' }
Ok "index links its seed lessons"       (($srcKbIdx -match 'powershell-commit-heredoc') -and ($srcKbIdx -match 'powershell-pure-ascii'))
$srcLog = Get-Content (Join-Path $engine 'tools\log_lesson.ps1') -Raw
Ok "log_lesson -Shared targets knowledge/" (($srcLog -match '\[switch\]\$Shared') -and ($srcLog -match "Join-Path .* 'knowledge'"))
$srcSs = Get-Content (Join-Path $engine '.claude\hooks\session_start.ps1') -Raw
Ok "SessionStart recalls the knowledge base" ($srcSs -match 'knowledge/INDEX\.md')

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
# Q3: one config resolver - the terminal + team must use Get-SonelleConfig, not re-parse the JSON themselves.
Ok "resolver also returns the Models block" ((Get-Content (Join-Path $PSScriptRoot '_registry.ps1') -Raw) -match 'Models\s*=\s*\$cfgModels')
$r3 = Get-SonelleConfig -Engine $engine
Ok "resolver exposes a Models property"  ($null -ne ($r3.PSObject.Properties.Name | Where-Object { $_ -eq 'Models' }))
Ok "sonelle.ps1 uses the canonical resolver (no inline cfg parse)" (($srcTerm -match 'Get-SonelleConfig') -and (-not ($srcTerm -match "Join-Path \`$root 'sonelle\.config\.json'")))
$srcTeam = Get-Content (Join-Path $engine 'bin\sonelle_team.ps1') -Raw
Ok "sonelle_team.ps1 uses the canonical resolver (no inline cfg parse)" (($srcTeam -match 'Get-SonelleConfig') -and (-not ($srcTeam -match "Join-Path \`$engine 'sonelle\.config\.json'")))

Write-Host "== 9a. one registry parser: PS == Python, and no third (Q1/Q2) =="
# Q1: the PowerShell parser (Get-SonelleProjects) and the Python parser (parse_projects) must agree on
# the SAME registry, or they will silently drift. Compare their shorts on the temp hub's PROJECTS.md.
$regPath = Join-Path $tmp 'PROJECTS.md'
$venvPy = Join-Path $engine '.venv\Scripts\python.exe'
if (Test-Path $venvPy) {
  $psShorts = ((Get-SonelleProjects $regPath) | ForEach-Object { $_.Short }) -join ','
  $pyCode = "import sys; sys.path.insert(0, r'{0}'); import sonelle_gui as g; print(','.join(p['shortcut'] for p in g.parse_projects(r'{1}')))" -f (Join-Path $engine 'app'), $regPath
  $pyShorts = (& $venvPy -c $pyCode 2>$null | Out-String).Trim()
  Ok "PS and Python registry parsers agree (Q1)" (($psShorts -eq $pyShorts) -and ($psShorts.Length -gt 0))
} else {
  Write-Host "  [skip] no .venv python for the cross-parser equivalence test" -ForegroundColor DarkGray
}
# Q2: nobody adds a THIRD parser. Grep every .ps1/.py (minus .venv) for the registry-row regex signature;
# the only PS file allowed to carry it is _registry.ps1, and the only Python file is sonelle_gui.py.
$scanFiles = @(Get-ChildItem $engine -Recurse -Include *.ps1, *.py | Where-Object { $_.FullName -notmatch '\\\.venv\\' })
$psParserHits = @(Select-String -Path $scanFiles.FullName -Pattern '\^\\\|.*\(\[a-z0-9_' -ErrorAction SilentlyContinue | Where-Object { $_.Path -notmatch 'selftest\.ps1' })
$psUnsanctioned = @($psParserHits | Where-Object { $_.Path -notmatch '_registry\.ps1' })
Ok "the sanctioned PS registry parser exists" (@($psParserHits | Where-Object { $_.Path -match '_registry\.ps1' }).Count -ge 1)
Ok "no unsanctioned PS registry parser (Q2)" ($psUnsanctioned.Count -eq 0)
$pyParserHits = @(Select-String -Path $scanFiles.FullName -Pattern 'startswith\("\|"\)' -ErrorAction SilentlyContinue | Where-Object { $_.Path -notmatch 'sonelle_gui\.py' })
Ok "no unsanctioned Python registry parser (Q2)" ($pyParserHits.Count -eq 0)

Write-Host "== 9b. terminal honors -Hub (Q4) =="
Ok "sonelle.ps1 has a -Hub param that wins over config" (($srcTerm -match '\[string\]\$Hub') -and ($srcTerm -match 'hubOverride'))
$hubDemo = & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $engine 'bin\sonelle.ps1') -Demo -Hub $tmp
$hubStr  = (($hubDemo -join "`n") -replace "$([char]27)\[[0-9;]*m", '')
Ok "terminal -Hub points the welcome at the override hub" ($hubStr -match '(?m)\bst\b')

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

if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }

Write-Host ""
if ($script:fail -eq 0) { Write-Host "[selftest] ALL PASS" -ForegroundColor Green; exit 0 }
else { Write-Host ("[selftest] {0} FAIL" -f $script:fail) -ForegroundColor Red; exit 1 }
