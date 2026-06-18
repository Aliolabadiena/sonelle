<#
  sonelle_app.ps1 - the sonelle APP: a single Claude-styled window that hosts MANY sonelle
  terminals as tabs. Each tab embeds a REAL console running bin\sonelle.ps1 (reparented into the
  window via Win32 SetParent), so you get the same terminal as `sonelle.ps1` - just several at once,
  in one branded frame. No Windows Terminal dependency (self-contained WinForms host).

  Usage:
    powershell -Sta -File bin\sonelle_app.ps1            open the app (one terminal tab)
    powershell -Sta -File bin\sonelle_app.ps1 -SelfTest  build the UI headless + verify, then exit
                                                         (no window shown, no terminal spawned)

  Inside the app:  [ + new ] adds a terminal tab; click a tab to switch; the tab's [x] closes it.
  Consoles attach ASYNCHRONOUSLY (a Forms.Timer polls for the window handle) so the UI never blocks
  and never re-enters the message loop - that is what keeps it from crashing on close/click.
  Source is pure ASCII; the only non-ASCII glyph (the close mark) is built at runtime via [char].
  WinForms needs STA - the script re-launches itself with -Sta if started in MTA.
#>
[CmdletBinding()]
param([switch]$SelfTest)

$ErrorActionPreference = 'Stop'
$root  = Split-Path $PSScriptRoot -Parent
$term  = Join-Path $root 'bin\sonelle.ps1'
$ico   = Join-Path $root 'assets\icon\sonelle.ico'
$psExe = (Get-Process -Id $PID).Path

# WinForms requires a single-threaded apartment; re-launch under -Sta if we are not in one.
if ([string]([System.Threading.Thread]::CurrentThread.GetApartmentState()) -ne 'STA') {
  $a = @('-NoProfile', '-Sta', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
  if ($SelfTest) { $a += '-SelfTest' }
  & $psExe @a
  exit $LASTEXITCODE
}

# ---- load UI + Win32 interop (skip cleanly in -SelfTest on a host that cannot do WinForms) ----
try {
  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -AssemblyName System.Drawing
  if (-not ([System.Management.Automation.PSTypeName]'Sonelle.Win').Type) {
    Add-Type -Namespace Sonelle -Name Win -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll", SetLastError=true)] public static extern System.IntPtr SetParent(System.IntPtr hWndChild, System.IntPtr hWndNewParent);
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern int GetWindowLong(System.IntPtr hWnd, int nIndex);
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern int SetWindowLong(System.IntPtr hWnd, int nIndex, int dwNewLong);
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool MoveWindow(System.IntPtr hWnd, int X, int Y, int w, int h, bool repaint);
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);
[System.Runtime.InteropServices.DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(System.IntPtr hwnd, int attr, ref int val, int sz);
const int GWL_STYLE = -16;
const int WS_CHILD = 0x40000000;
const int WS_VISIBLE = 0x10000000;
const int WS_POPUP = unchecked((int)0x80000000);
const int WS_CAPTION = 0x00C00000;
const int WS_THICKFRAME = 0x00040000;
const int WS_MINIMIZE = 0x20000000;
const int WS_MAXIMIZE = 0x01000000;
const int WS_MINIMIZEBOX = 0x00020000;
const int WS_MAXIMIZEBOX = 0x00010000;
const int WS_SYSMENU = 0x00080000;
const int WS_BORDER = 0x00800000;
const int WS_DLGFRAME = 0x00400000;
const int SW_SHOWNORMAL = 1;
public static void Embed(System.IntPtr child, System.IntPtr parent, int w, int h) {
  int style = GetWindowLong(child, GWL_STYLE);
  style = style & ~(WS_CAPTION | WS_THICKFRAME | WS_MINIMIZE | WS_MAXIMIZE | WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_SYSMENU | WS_POPUP | WS_BORDER | WS_DLGFRAME);
  style = style | WS_CHILD | WS_VISIBLE;
  SetWindowLong(child, GWL_STYLE, style);
  SetParent(child, parent);
  ShowWindow(child, SW_SHOWNORMAL);
  MoveWindow(child, 0, 0, w, h, true);
}
public static void Fit(System.IntPtr child, int w, int h) { MoveWindow(child, 0, 0, w, h, true); }
public static void DarkTitleBar(System.IntPtr hwnd) {
  int yes = 1;
  if (DwmSetWindowAttribute(hwnd, 20, ref yes, 4) != 0) { DwmSetWindowAttribute(hwnd, 19, ref yes, 4); }
}
'@
  }
} catch {
  if ($SelfTest) { Write-Host ("SELFTEST SKIP: " + $_.Exception.Message); exit 0 }
  throw
}

# ---- palette (Claude: clay accent, cream text on warm dark) ----
$cBg        = [System.Drawing.Color]::FromArgb(22, 21, 20)
$cStrip     = [System.Drawing.Color]::FromArgb(30, 28, 27)
$cHover     = [System.Drawing.Color]::FromArgb(40, 36, 34)
$cActiveTab = [System.Drawing.Color]::FromArgb(48, 42, 39)
$cClay      = [System.Drawing.Color]::FromArgb(204, 120, 92)
$cCream     = [System.Drawing.Color]::FromArgb(235, 232, 222)
$cDim       = [System.Drawing.Color]::FromArgb(150, 146, 140)
$glX        = [string][char]0x00D7   # multiplication sign as a tidy close mark (built at runtime; source stays ASCII)

$script:terms       = New-Object System.Collections.ArrayList
$script:active       = $null
$script:nextId       = 1
$script:firstOpened  = $false

# ---- helpers (every handler body is wrapped in try/catch so a stray error never kills the app) ----
function Resize-Active {
  if ($script:active -and $script:active.Hwnd -ne [System.IntPtr]::Zero -and -not $script:active.Pane.IsDisposed) {
    $w = [Math]::Max($script:hostPanel.ClientSize.Width, 1)
    $h = [Math]::Max($script:hostPanel.ClientSize.Height, 1)
    try { [Sonelle.Win]::Fit($script:active.Hwnd, $w, $h) } catch {}
  }
}
function Style-Tab($entry, $hover) {
  if (-not $entry -or $entry.Tab.IsDisposed) { return }
  $isActive = ($script:active -eq $entry)
  if ($isActive)   { $entry.Tab.BackColor = $cActiveTab; $entry.Label.ForeColor = $cCream; $entry.Label.Font = $script:tabFontOn;  $entry.Under.BackColor = $cClay }
  elseif ($hover)  { $entry.Tab.BackColor = $cHover;     $entry.Label.ForeColor = $cCream; $entry.Label.Font = $script:tabFontOff; $entry.Under.BackColor = $cStrip }
  else             { $entry.Tab.BackColor = $cStrip;     $entry.Label.ForeColor = $cDim;   $entry.Label.Font = $script:tabFontOff; $entry.Under.BackColor = $cStrip }
}
function Show-Terminal($entry) {
  $script:active = $entry
  foreach ($t in $script:terms) {
    if (-not $t.Pane.IsDisposed) { $t.Pane.Visible = ($t -eq $entry) }
    Style-Tab $t $false
  }
  if ($entry -and -not $entry.Pane.IsDisposed) { $entry.Pane.Visible = $true; $entry.Pane.BringToFront(); Resize-Active }
}
function Show-AttachFail($entry) {
  if ($entry.Pane.IsDisposed) { return }
  $msg = New-Object System.Windows.Forms.Label
  $msg.Text = "could not attach this terminal (it may have exited). close the tab and try + new."
  $msg.ForeColor = $cDim; $msg.Dock = 'Top'; $msg.AutoSize = $true
  $msg.Padding = New-Object System.Windows.Forms.Padding(14)
  $entry.Pane.Controls.Add($msg)
}
function Close-Terminal($entry) {
  if (-not $entry) { return }
  try { if ($entry.Timer) { $entry.Timer.Stop(); $entry.Timer.Dispose() } } catch {}
  try { if ($entry.Proc -and -not $entry.Proc.HasExited) { & taskkill /PID $entry.Proc.Id /T /F 2>$null | Out-Null } } catch {}
  try { $script:tabsFlow.Controls.Remove($entry.Tab); $entry.Tab.Dispose() } catch {}
  try { $script:hostPanel.Controls.Remove($entry.Pane); $entry.Pane.Dispose() } catch {}
  try { $script:terms.Remove($entry) } catch {}
  if ($script:active -eq $entry) {
    $script:active = $null
    if ($script:terms.Count -gt 0) { Show-Terminal $script:terms[$script:terms.Count - 1] }
    else { $script:emptyLabel.Visible = $true }
  }
}
# Forms.Timer tick: poll the spawned console for its window handle, then reparent it. No DoEvents,
# no blocking - so closing/clicking during attach can never re-enter or touch disposed controls.
function Attach-Tick($timer) {
  $entry = $timer.Tag
  if (-not $entry -or $entry.Pane.IsDisposed) { try { $timer.Stop(); $timer.Dispose() } catch {}; return }
  $entry.Tries++
  if ($entry.Tries -gt 120) { $timer.Stop(); $timer.Dispose(); if (-not $entry.Attached) { Show-AttachFail $entry }; return }
  $p = $entry.Proc
  try { $p.Refresh() } catch {}
  if ($p.HasExited) { $timer.Stop(); $timer.Dispose(); Show-AttachFail $entry; return }
  $h = $p.MainWindowHandle
  if ($h -ne [System.IntPtr]::Zero) {
    $timer.Stop(); $timer.Dispose()
    try {
      $w  = [Math]::Max($entry.Pane.ClientSize.Width, 1)
      $hh = [Math]::Max($entry.Pane.ClientSize.Height, 1)
      [Sonelle.Win]::Embed($h, $entry.Pane.Handle, $w, $hh)
      $entry.Hwnd = $h; $entry.Attached = $true
      if ($script:active -eq $entry) { Resize-Active }
    } catch {}
  }
}
function New-Terminal {
  try {
    $id = $script:nextId; $script:nextId++
    $script:emptyLabel.Visible = $false

    # pane that will host the embedded console
    $pane = New-Object System.Windows.Forms.Panel
    $pane.Dock = 'Fill'; $pane.BackColor = $cBg
    $script:hostPanel.Controls.Add($pane); $pane.BringToFront()

    # tab chip: [ label .......... x ] with a clay underline when active
    $tab = New-Object System.Windows.Forms.Panel
    $tab.Height = 28; $tab.Width = 140; $tab.BackColor = $cStrip
    $tab.Margin = New-Object System.Windows.Forms.Padding(6, 7, 0, 0)
    $under = New-Object System.Windows.Forms.Panel
    $under.Dock = 'Bottom'; $under.Height = 2; $under.BackColor = $cStrip
    $cls = New-Object System.Windows.Forms.Label
    $cls.Text = $glX; $cls.Dock = 'Right'; $cls.Width = 24; $cls.TextAlign = 'MiddleCenter'
    $cls.ForeColor = $cDim; $cls.Cursor = 'Hand'; $cls.Font = $script:tabFontOff
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = ("sonelle " + $id); $lbl.Dock = 'Fill'; $lbl.TextAlign = 'MiddleLeft'
    $lbl.ForeColor = $cDim; $lbl.Font = $script:tabFontOff; $lbl.Cursor = 'Hand'
    $lbl.Padding = New-Object System.Windows.Forms.Padding(10, 0, 0, 0)
    $tab.Controls.Add($under); $tab.Controls.Add($cls); $tab.Controls.Add($lbl)
    $script:tabsFlow.Controls.Add($tab)

    # start a real sonelle terminal (minimized); a timer reparents it into the pane
    $pargs = @('-NoExit', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $term)
    $proc = Start-Process -FilePath $psExe -ArgumentList $pargs -WorkingDirectory $root -WindowStyle Minimized -PassThru

    $entry = [pscustomobject]@{ Id = $id; Proc = $proc; Hwnd = [System.IntPtr]::Zero; Pane = $pane; Tab = $tab; Label = $lbl; Close = $cls; Under = $under; Timer = $null; Tries = 0; Attached = $false }
    [void]$script:terms.Add($entry)

    foreach ($c in @($lbl, $tab, $under)) {
      $c.Tag = $entry
      $c.Add_Click({ param($s, $e) try { Show-Terminal $s.Tag } catch {} })
      $c.Add_MouseEnter({ param($s, $e) try { Style-Tab $s.Tag $true } catch {} })
      $c.Add_MouseLeave({ param($s, $e) try { Style-Tab $s.Tag $false } catch {} })
    }
    $cls.Tag = $entry
    $cls.Add_Click({ param($s, $e) try { Close-Terminal $s.Tag } catch {} })
    $cls.Add_MouseEnter({ param($s, $e) try { $s.ForeColor = $cClay } catch {} })
    $cls.Add_MouseLeave({ param($s, $e) try { $s.ForeColor = $cDim } catch {} })

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 60; $timer.Tag = $entry
    $timer.Add_Tick({ param($s, $e) try { Attach-Tick $s } catch {} })
    $entry.Timer = $timer
    Show-Terminal $entry
    $timer.Start()
  } catch {}
}

# ---- build the window ----
[System.Windows.Forms.Application]::EnableVisualStyles()
$script:form = New-Object System.Windows.Forms.Form
$script:form.Text = 'sonelle'
$script:form.StartPosition = 'CenterScreen'
$script:form.Size = New-Object System.Drawing.Size(1100, 720)
$script:form.MinimumSize = New-Object System.Drawing.Size(680, 440)
$script:form.BackColor = $cBg
if (Test-Path $ico) { try { $script:form.Icon = New-Object System.Drawing.Icon($ico) } catch {} }
$script:tabFontOff = New-Object System.Drawing.Font('Segoe UI', 9)
$script:tabFontOn  = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)

# root: row 0 = strip (42), row 1 = clay accent (2), row 2 = content (fill)
$rootTable = New-Object System.Windows.Forms.TableLayoutPanel
$rootTable.Dock = 'Fill'; $rootTable.ColumnCount = 1; $rootTable.RowCount = 3; $rootTable.BackColor = $cBg
[void]$rootTable.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 44)))
[void]$rootTable.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 2)))
[void]$rootTable.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$script:form.Controls.Add($rootTable)

# strip: [ brand ][ tabs (fill) ][ + new ]
$strip = New-Object System.Windows.Forms.TableLayoutPanel
$strip.Dock = 'Fill'; $strip.ColumnCount = 3; $strip.RowCount = 1; $strip.BackColor = $cStrip
[void]$strip.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize)))
[void]$strip.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$strip.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize)))

$brand = New-Object System.Windows.Forms.Label
$brand.Text = 'sonelle'; $brand.AutoSize = $true; $brand.ForeColor = $cClay
$brand.Font = New-Object System.Drawing.Font('Consolas', 13, [System.Drawing.FontStyle]::Bold)
$brand.Anchor = 'Left'; $brand.Padding = New-Object System.Windows.Forms.Padding(14, 0, 14, 0)
$strip.Controls.Add($brand, 0, 0)

$script:tabsFlow = New-Object System.Windows.Forms.FlowLayoutPanel
$script:tabsFlow.Dock = 'Fill'; $script:tabsFlow.WrapContents = $false; $script:tabsFlow.AutoScroll = $true
$script:tabsFlow.BackColor = $cStrip
$strip.Controls.Add($script:tabsFlow, 1, 0)

$newBtn = New-Object System.Windows.Forms.Button
$newBtn.Text = '+ new'; $newBtn.AutoSize = $true; $newBtn.FlatStyle = 'Flat'
$newBtn.ForeColor = $cClay; $newBtn.BackColor = $cStrip; $newBtn.FlatAppearance.BorderSize = 0
$newBtn.FlatAppearance.MouseOverBackColor = $cHover
$newBtn.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$newBtn.Anchor = 'Right'; $newBtn.Margin = New-Object System.Windows.Forms.Padding(8, 7, 14, 7)
$newBtn.Cursor = 'Hand'
$newBtn.Add_Click({ try { New-Terminal } catch {} })
$newBtn.Add_MouseEnter({ try { $newBtn.ForeColor = $cCream } catch {} })
$newBtn.Add_MouseLeave({ try { $newBtn.ForeColor = $cClay } catch {} })
$strip.Controls.Add($newBtn, 2, 0)

$rootTable.Controls.Add($strip, 0, 0)

$accent = New-Object System.Windows.Forms.Panel
$accent.Dock = 'Fill'; $accent.BackColor = $cClay
$rootTable.Controls.Add($accent, 0, 1)

# content host (the active tab's console fills this)
$script:hostPanel = New-Object System.Windows.Forms.Panel
$script:hostPanel.Dock = 'Fill'; $script:hostPanel.BackColor = $cBg
$script:hostPanel.Add_SizeChanged({ try { Resize-Active } catch {} })
$rootTable.Controls.Add($script:hostPanel, 0, 2)

$script:emptyLabel = New-Object System.Windows.Forms.Label
$script:emptyLabel.Text = "no terminals open" + [Environment]::NewLine + [Environment]::NewLine + "click  + new  to start one  " + ([char]0x00B7) + "  each tab is a full sonelle"
$script:emptyLabel.ForeColor = $cDim; $script:emptyLabel.Dock = 'Fill'; $script:emptyLabel.TextAlign = 'MiddleCenter'
$script:emptyLabel.Font = New-Object System.Drawing.Font('Segoe UI', 11)
$script:hostPanel.Controls.Add($script:emptyLabel)

$script:form.Add_FormClosing({
  param($s, $e)
  foreach ($t in @($script:terms)) {
    try { if ($t.Timer) { $t.Timer.Stop(); $t.Timer.Dispose() } } catch {}
    try { if ($t.Proc -and -not $t.Proc.HasExited) { & taskkill /PID $t.Proc.Id /T /F 2>$null | Out-Null } } catch {}
  }
})

# ---- headless self-test: prove the UI + interop build, spawn nothing, show nothing ----
if ($SelfTest) {
  $okType = [bool]([Sonelle.Win].GetMethod('Embed')) -and [bool]([Sonelle.Win].GetMethod('Fit')) -and [bool]([Sonelle.Win].GetMethod('DarkTitleBar'))
  $okUi   = ($null -ne $script:form) -and ($null -ne $script:hostPanel) -and ($null -ne $script:tabsFlow) -and ($null -ne $newBtn)
  try { $script:form.Dispose() } catch {}
  if ($okType -and $okUi) { Write-Host 'SELFTEST OK'; exit 0 } else { Write-Host 'SELFTEST FAIL'; exit 1 }
}

# ---- run: never let a stray runtime error tear the window down ----
$ErrorActionPreference = 'Continue'
$script:form.Add_Shown({
  param($s, $e)
  try { [Sonelle.Win]::DarkTitleBar($script:form.Handle) } catch {}
  if (-not $script:firstOpened) { $script:firstOpened = $true; try { New-Terminal } catch {} }
})
[void]$script:form.ShowDialog()
