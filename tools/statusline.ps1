<#
  statusline.ps1 - luna usage status line. Reads Claude Code's statusLine JSON from stdin and prints a
  one-line indicator: model+effort | 5h% | 7d% | ctx%. Colour by load (green/amber/red).
  Wire in settings.json:
    "statusLine": { "type": "command", "command": "powershell -NoProfile -File C:/Users/you/Desktop/luna/tools/statusline.ps1", "refreshInterval": 10 }
  NOTE: 5h%/7d% appear only for Pro/Max subscribers and only after the first API response in a session.
#>
$raw = [Console]::In.ReadToEnd()
try { $j = $raw | ConvertFrom-Json } catch { Write-Output 'luna'; exit 0 }

$E = [char]27
$clay = "$E[38;2;204;120;92m"; $dim = "$E[38;2;140;140;140m"; $R = "$E[0m"
function Col($p) { if ($p -ge 85) { "$E[38;2;222;90;70m" } elseif ($p -ge 60) { "$E[38;2;230;170;70m" } else { "$E[38;2;150;190;90m" } }

$parts = @("$clay" + 'luna' + $R)

$model = if ($j.model.display_name) { $j.model.display_name } else { 'claude' }
$eff = if ($j.effort.level) { ' ' + $j.effort.level } else { '' }
$parts += "$dim$model$eff$R"

if ($null -ne $j.rate_limits.five_hour.used_percentage) {
  $p = [math]::Round([double]$j.rate_limits.five_hour.used_percentage)
  $parts += (Col $p) + "5h ${p}%" + $R
}
if ($null -ne $j.rate_limits.seven_day.used_percentage) {
  $p = [math]::Round([double]$j.rate_limits.seven_day.used_percentage)
  $parts += (Col $p) + "7d ${p}%" + $R
}
if ($null -ne $j.context_window.used_percentage) {
  $parts += "$dim" + ('ctx ' + [math]::Round([double]$j.context_window.used_percentage) + '%') + $R
}

Write-Output (($parts) -join "$dim | $R")
