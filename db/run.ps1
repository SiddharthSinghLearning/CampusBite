# Runs a SQL script as the CANTEEN user using the credentials in ..\.env
# Usage: .\db\run.ps1 install.sql      (path relative to the db folder)
param([Parameter(Mandatory = $true)][string]$Script)

$envFile = Join-Path $PSScriptRoot '..\.env'
$cfg = @{}
Get-Content $envFile | Where-Object { $_ -match '^\s*([A-Z_]+)=(.*)$' } | ForEach-Object { $cfg[$Matches[1]] = $Matches[2].Trim() }

Push-Location $PSScriptRoot
try {
  sqlplus -S -L "$($cfg.DB_USER)/`"$($cfg.DB_PASSWORD)`"@$($cfg.DB_CONNECT)" "@$Script"
} finally {
  Pop-Location
}
