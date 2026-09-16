<#
  reviewer_guard.ps1 - PreToolUse hook. Matcher: Bash|PowerShell|Write|Edit|MultiEdit|NotebookEdit.

  The reviewer/verifier subagents are review-only: their frontmatter `tools:` allowlist already omits
  Write/Edit, and this guard closes the other door - side effects through a shell. It only ever looks at
  calls whose agent_type is "reviewer" or "verifier".

    Write/Edit/MultiEdit/NotebookEdit  -> denied outright.
    Bash/PowerShell                    -> denied when the command mutates (rm/mv/cp/mkdir/git add|commit|
                                          push|checkout|reset|..., npm install, pip install, Set-Content,
                                          Out-File, Remove-Item, find -delete/-exec, ...) or redirects
                                          (> , >> , | tee).

  Four things the deny patterns handle on purpose (each was a real bypass):
    * chaining      - `pytest && rm -rf build`, `git status; git push`: the deny patterns are evaluated
                      for EVERY command in the chain, and a test-runner word no longer exempts the rest.
    * newlines      - a multi-line command is one call; `\r\n` counts as a command separator.
    * nested shells - `sh -c "rm -rf build"`, `powershell -Command "Remove-Item x"`, `echo "$(rm -rf x)"`:
                      when a shell/interpreter (or a substitution) is actually invoked, the patterns are
                      also matched against a copy in which quotes and the `-c`-style flag are separators.
    * launchers     - `sudo rm -rf x`, `find . | xargs rm`, `time rm -rf x`: a prefix word keeps the verb
                      off the start of its segment, so those words are turned into separators too.
  A test runner (npm test, pytest, go test, dotnet test, a *selftest* PowerShell file) matches none of the
  deny patterns and so stays allowed - a reviewer that cannot run the test it is judging is useless - but
  only as long as it is the whole command. Quoting a verb as EVIDENCE (`grep -rn "Remove-Item" .`) stays
  allowed, which is why the quote flattening only happens when a shell is really being invoked. Known
  limit: this is a regex over a shell string, so an interpreter one-liner writing through its own runtime
  (`python -c "...shutil.rmtree..."`) is not recognized; see docs\ENFORCEMENT.md.

  Exit 2 = blocked (stderr goes back to Claude). Fail-OPEN on any parse problem.
#>
$ErrorActionPreference = 'SilentlyContinue'

try { $raw = (New-Object System.IO.StreamReader([Console]::OpenStandardInput(), [System.Text.Encoding]::UTF8)).ReadToEnd() } catch { exit 0 }
if (-not $raw) { exit 0 }
try { $j = $raw | ConvertFrom-Json } catch { exit 0 }

$agentTy = [string]$j.agent_type
if (-not $agentTy) { $agentTy = [string]$j.agentType }
if (-not $agentTy) { $agentTy = [string]$j.subagent_type }
$agentTy = $agentTy.Trim()
if ($agentTy -notmatch '(?i)^(reviewer|verifier)$') { exit 0 }

$tool = [string]$j.tool_name
$ti   = $j.tool_input

function Deny([string]$msg) {
  [Console]::Error.WriteLine('sonelle: ' + $msg)
  exit 2
}

if ($tool -match '^(Write|Edit|MultiEdit|NotebookEdit)$') {
  $path = [string]$ti.file_path
  if (-not $path) { $path = [string]$ti.notebook_path }
  Deny ($agentTy + ' is a review-only agent: it reports findings, it does not edit (' + $tool + ' ' + $path + '). Hand the fix to an implementer.')
}

if ($tool -match '^(Bash|PowerShell)$') {
  $cmd = [string]$ti.command
  if (-not $cmd) { exit 0 }

  # The deny patterns below are ANCHORED to a command boundary (start of the line or after ; & |), which
  # is what keeps them from firing on a quoted mention of a verb. Three shapes hide a real verb from that
  # anchor, so the command is normalized into a $norm copy before matching - the patterns stay anchored:
  #   a nested shell     sh -c "rm -rf x" / powershell -Command "Remove-Item x"  -> quotes become separators
  #   a substitution     echo "$(rm -rf x)", backticks, <<<                      -> same
  #   a launcher prefix  sudo rm -rf x, find . | xargs rm, time rm               -> the word becomes a separator
  # The quote flattening is CONDITIONAL on a shell/interpreter actually being invoked: a review gathers
  # evidence with commands that quote these verbs (`grep -rn "Remove-Item" .`), and those must still run.
  $isShellCall = $cmd -match '(?i)(^|[\s;&|(])(sh|bash|zsh|dash|ksh|cmd|powershell|pwsh|python3?|perl|ruby|node|deno|eval)(\.exe)?\b'
  $norm = $cmd
  if ($isShellCall -or ($cmd -match '\x24\(|[\x60]|<<<')) { $norm = $norm -replace '[\x22\x27\x60()\x24]', ';' }
  $norm = $norm -replace '(?i)\b(sudo|doas|env|nohup|nice|ionice|stdbuf|setsid|timeout|time|command|builtin|exec|xargs|wsl)\b', ';'
  if ($isShellCall) { $norm = $norm -replace '(?i)(^|[\s;])(-{1,2}[a-z]*c|/c|/k)([\s;]|$)', '; ' }
  # discarding output is not a side effect
  $noNull = $cmd -replace '(?i)\d?>>?\s*(/dev/null|nul|\$null)', ' '

  $mutating = '(?m)(^|[;&|\r\n]\s*)(rm|mv|cp|del|rmdir|mkdir|touch|sed\s+-i|git\s+(add|commit|push|checkout|switch|reset|rebase|merge|stash|clean|restore)|npm\s+(i|install|ci|run\s+build)|pip\s+install|Set-Content|Out-File|Add-Content|Remove-Item|Move-Item|Copy-Item|Rename-Item|New-Item)\b'
  # find's own destructive actions carry no verb of their own
  $findAct  = '(?i)(^|\s)-(delete|exec|execdir|ok)\b'
  # a real redirect, not an arrow (->, =>), a comparison (>=) or a stream dup (2>&1)
  $redirect = '(^|[^-=<>!])>{1,2}\s*[^&\s=]|\|\s*tee\b'

  if (($cmd -match $mutating) -or ($norm -match $mutating) -or ($cmd -match $findAct) -or ($noNull -match $redirect)) {
    $excerpt = $cmd
    if ($excerpt.Length -gt 100) { $excerpt = $excerpt.Substring(0, 100) + '...' }
    Deny ($agentTy + ' is a review-only agent: no side effects. Blocked command: ' + $excerpt + ' - read, run tests, and report findings instead.')
  }
}

exit 0
