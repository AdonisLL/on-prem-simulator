[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param([Parameter(Mandatory)][string]$ResourceGroupName)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($PSCmdlet.ShouldProcess($ResourceGroupName, 'Reseed the database and restart synthetic traffic')) {
    & az vm run-command invoke `
        --resource-group $ResourceGroupName `
        --name sql01 `
        --command-id RunPowerShellScript `
        --scripts 'sqlcmd.exe -S localhost -E -b -i C:\ProgramData\OnPremLab\content\database\seed\001-Products.sql' `
        --only-show-errors `
        --output none
    if ($LASTEXITCODE -ne 0) {
        throw 'Database reset failed.'
    }

    & az vm run-command invoke `
        --resource-group $ResourceGroupName `
        --name dc01 `
        --command-id RunPowerShellScript `
        --scripts 'Start-ScheduledTask -TaskName OnPremLab-SyntheticTraffic' `
        --only-show-errors `
        --output none
    if ($LASTEXITCODE -ne 0) {
        throw 'Synthetic traffic restart failed.'
    }
}
