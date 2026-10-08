# Validate an Astra review JSON and print an ASCII summary (verdict, counts, issue ids).
# Exit 1 if the file is not valid JSON or misses required keys.
param([Parameter(Mandatory = $true)][string]$Path)
$ErrorActionPreference = 'Stop'
try {
  $r = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
} catch {
  Write-Output "INVALID JSON: $Path"
  exit 1
}
foreach ($k in 'round', 'verdict', 'summary', 'issues', 'previous_issues', 'verified', 'not_checked') {
  if ($r.PSObject.Properties.Name -notcontains $k) { Write-Output "MISSING KEY: $k"; exit 1 }
}
$issues = @($r.issues)
$prev = @($r.previous_issues)
$count = { param($items, $field, $value) @($items | Where-Object { $_.$field -eq $value }).Count }
Write-Output ("verdict: {0} (round {1})" -f $r.verdict, $r.round)
Write-Output ("issues: {0} | critical={1} major={2} minor={3}" -f $issues.Count,
  (& $count $issues 'severity' 'critical'), (& $count $issues 'severity' 'major'), (& $count $issues 'severity' 'minor'))
if ($issues.Count -gt 0) {
  Write-Output ("ids: " + (($issues | ForEach-Object { "{0}({1},{2})" -f $_.id, $_.severity, $_.confidence }) -join ' '))
}
if ($prev.Count -gt 0) {
  $groups = $prev | Group-Object status | ForEach-Object { "{0}={1}" -f $_.Name, $_.Count }
  Write-Output ("previous: " + ($groups -join ' '))
}
Write-Output ("verified claims: {0} | not checked: {1}" -f @($r.verified).Count, @($r.not_checked).Count)
