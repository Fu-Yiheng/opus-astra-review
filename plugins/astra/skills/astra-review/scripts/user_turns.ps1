# Extract the messages the user actually typed from a Claude Code transcript (.jsonl)
# into a Markdown file. Tool results, meta messages and subagent turns are skipped;
# <system-reminder> blocks are stripped.
param(
  [Parameter(Mandatory = $true)][string]$Transcript,
  [Parameter(Mandatory = $true)][string]$Out
)
$ErrorActionPreference = 'Stop'
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('# User messages')
[void]$sb.AppendLine('')
[void]$sb.AppendLine("Extracted from: $Transcript")
$i = 0
$skipped = 0
foreach ($line in [System.IO.File]::ReadLines($Transcript, [System.Text.Encoding]::UTF8)) {
  # cheap pre-filter: assistant turns and big tool outputs never need parsing
  if (-not $line.Contains('"type":"user"')) { continue }
  try { $o = $line | ConvertFrom-Json } catch { $skipped++; continue }
  if ($o.type -ne 'user' -or $o.isMeta -or $o.isSidechain) { continue }
  $c = $o.message.content
  if ($c -is [string]) {
    $txt = $c
  } else {
    if (@($c | Where-Object { $_.type -eq 'tool_result' }).Count -gt 0) { continue }
    $txt = (@($c | Where-Object { $_.type -eq 'text' } | ForEach-Object { $_.text })) -join "`n"
  }
  $txt = [regex]::Replace([string]$txt, '(?s)<system-reminder>.*?</system-reminder>', '').Trim()
  if (-not $txt) { continue }
  $i++
  $label = ''
  if ($o.isCompactSummary) { $label = ' (compaction summary, not typed by the user)' }
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine("## $i - $($o.timestamp)$label")
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine($txt)
}
[System.IO.File]::WriteAllText($Out, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
Write-Output "$i user messages -> $Out"
if ($skipped -gt 0) { Write-Output "WARNING: $skipped lines could not be parsed (probably too large)" }
