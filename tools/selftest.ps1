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
Ok "project sonelle.check.ps1 created" (Test-Path (Join-Path $codePath 'sonelle.check.ps1'))
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
& $ps -ExecutionPolicy Bypass -File (Join-Path $engine 'bin\sonelle_team.ps1') st -Lanes a=haiku,b -Hub $tmp -DryRun | Out-Null
Ok "sonelle_team dry-run exit 0"        ($LASTEXITCODE -eq 0)
Ok "lane board written"             (Test-Path (Join-Path $codePath '.sonelle\lanes\a.md'))
Ok "lane start script written"      (Test-Path (Join-Path $codePath '.sonelle\lanes\a.start.ps1'))
$le=$null;$lt=$null;[void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $codePath '.sonelle\lanes\a.start.ps1'),[ref]$lt,[ref]$le)
Ok "lane start script parses"       ($le.Count -eq 0)
Ok "lane per-model in start script" ((Get-Content (Join-Path $codePath '.sonelle\lanes\a.start.ps1') -Raw) -match '--model haiku')
Ok "lane permission-mode in start script" ((Get-Content (Join-Path $codePath '.sonelle\lanes\a.start.ps1') -Raw) -match '--permission-mode')

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
  'app\ui\names.js',
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
$srcJs = Get-Content (Join-Path $appDir 'ui\app.js') -Raw
Ok "frontend has output sink + ready gate" (($srcJs -match 'window\.__ptyOutput') -and ($srcJs -match 'pywebviewready'))
Ok "frontend uses FitAddon.FitAddon"  ($srcJs -match 'new FitAddon\.FitAddon\(\)')
Ok "frontend mounts the WebGL renderer" (($srcJs -match 'WebglAddon\.WebglAddon') -and ($srcJs -match 'function mountWebgl'))
Ok "frontend debounces resize fits"   ($srcJs -match 'function scheduleFit')
Ok "frontend names tabs from the pool" (($srcJs -match 'function pickName') -and ($srcJs -match 'SONELLE_NAMES') -and (-not ($srcJs -match '"sonelle " \+')))
Ok "frontend pastes images via save_paste_image" (($srcJs -match 'save_paste_image') -and ($srcJs -match '"paste"'))
Ok "frontend guards titlebar drag"    ($srcJs -match "closest\(`"\.nodrag`"\)")
$srcNames = Get-Content (Join-Path $appDir 'ui\names.js') -Raw
$nameCount = ([regex]::Matches($srcNames, '"[A-Za-z]+"')).Count
Ok "names pool is sizable (>=200)"    (($srcNames -match 'window\.SONELLE_NAMES') -and ($nameCount -ge 200))
$srcCss = Get-Content (Join-Path $appDir 'ui\app.css') -Raw
Ok "css gives the terminal a scrollbar gutter" (($srcCss -match '\.pane \.xterm\{ padding-right') -and ($srcCss -match 'xterm-viewport::-webkit-scrollbar'))
$srcHtml = Get-Content (Join-Path $appDir 'ui\index.html') -Raw
Ok "index loads vendored xterm + app.js" (($srcHtml -match 'vendor/xterm\.js') -and ($srcHtml -match 'app\.js'))
Ok "index loads the WebGL addon"      ($srcHtml -match 'vendor/addon-webgl\.js')
Ok "index loads the tab-name pool"    ($srcHtml -match 'names\.js')
Ok "titlebar is a pywebview drag region" ($srcHtml -match 'pywebview-drag-region')
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

if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }

Write-Host ""
if ($script:fail -eq 0) { Write-Host "[selftest] ALL PASS" -ForegroundColor Green; exit 0 }
else { Write-Host ("[selftest] {0} FAIL" -f $script:fail) -ForegroundColor Red; exit 1 }
