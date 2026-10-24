# Runs each report script in SQL*Plus (not silent, so prompts and banner show)
# and saves the console output next to it as <name>.txt
param([string[]]$Scripts = @())

$cfg = @{}
Get-Content (Join-Path $PSScriptRoot '..\..\.env') | Where-Object { $_ -match '^\s*([A-Z_]+)=(.*)$' } |
  ForEach-Object { $cfg[$Matches[1]] = $Matches[2].Trim() }
$login = "$($cfg.DB_USER)/`"$($cfg.DB_PASSWORD)`"@$($cfg.DB_CONNECT)"

if (-not $Scripts.Count) { $Scripts = Get-ChildItem $PSScriptRoot -Filter 'd*.sql' | Sort-Object Name | ForEach-Object Name }
Push-Location $PSScriptRoot
try {
  foreach ($s in $Scripts) {
    $out = [IO.Path]::ChangeExtension($s, '.txt')
    sqlplus -L $login "@$s" | Out-File -Encoding utf8 $out
    Write-Output "captured $out"
  }
} finally {
  Pop-Location
}
