[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$schema = Get-Content "$root\database\schema\001-LegacyLab.sql" -Raw
$seed = Get-Content "$root\database\seed\001-Products.sql" -Raw
$requirements = @{
    'schema guards LegacyLab creation' = $schema -match "IF DB_ID\(N'LegacyLab'\) IS NULL"
    'schema guards Products creation'  = $schema -match "IF OBJECT_ID\(N'dbo.Products'"
    'schema uses replaceable trigger'  = $schema -match 'CREATE OR ALTER TRIGGER'
    'seed is idempotent'               = $seed -match 'MERGE dbo.Products'
    'scripts do not contain passwords' = "$schema`n$seed" -notmatch '(?i)password\s*='
}
$failed = $requirements.GetEnumerator() | Where-Object { -not $_.Value }
if ($failed) {
    throw (($failed | ForEach-Object Key) -join [Environment]::NewLine)
}
Write-Host 'SQL scripts satisfy idempotency and secret-safety checks.'
