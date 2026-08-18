[CmdletBinding()]
param([Parameter(Mandatory)][string]$ResourceGroupName)

$ErrorActionPreference = 'Stop'
$expected = 'dc01', 'web01', 'web02', 'sql01', 'migrate01'
$failures = [Collections.Generic.List[string]]::new()
foreach ($vmName in $expected) {
    $details = & az vm show --resource-group $ResourceGroupName --name $vmName --show-details --output json --only-show-errors | ConvertFrom-Json
    if (-not $details) {
        $failures.Add("$vmName does not exist.")
        continue
    }
    if ($details.publicIps) {
        $failures.Add("$vmName unexpectedly has a public IP.")
    }
}

foreach ($vmName in 'web01', 'web02') {
    $result = & az vm run-command invoke `
        --resource-group $ResourceGroupName `
        --name $vmName `
        --command-id RunPowerShellScript `
        --scripts 'Invoke-WebRequest http://localhost -UseBasicParsing -TimeoutSec 30 | Select-Object -ExpandProperty StatusCode' `
        --query 'value[0].message' `
        --output tsv `
        --only-show-errors
    if ($result -notmatch '200') {
        $failures.Add("$vmName did not return HTTP 200 locally.")
    }
}

$sqlResult = & az vm run-command invoke `
    --resource-group $ResourceGroupName `
    --name sql01 `
    --command-id RunPowerShellScript `
    --scripts 'sqlcmd.exe -S localhost -E -b -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM LegacyLab.dbo.Products"' `
    --query 'value[0].message' `
    --output tsv `
    --only-show-errors
if ($sqlResult -notmatch '\b4\b') {
    $failures.Add('SQL validation did not find the four seeded products.')
}

if ($failures.Count) {
    throw ($failures -join [Environment]::NewLine)
}
Write-Host 'Lab readiness checks passed.'
