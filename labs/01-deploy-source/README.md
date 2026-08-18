# 01 - Deploy the source estate

Use the scenario selected in module 00. The root dispatcher requires the
strategy explicitly and preserves the independent Bicep/Terraform choice.

## Azure-native

```powershell
.\scripts\Deploy-Lab.ps1 `
  -Scenario AzureNative `
  -Iac Bicep `
  -ResourceGroupName rg-opmlab-source `
  -Location eastus2
```

Use `-Iac Terraform` for the equivalent Terraform implementation.

This path creates `dc01`, `web01`, `web02`, `sql01`, and `migrate01` as private
Azure VMs. It builds the application and assigns managed-identity access before
guest configuration.

### Private Key Vault checkpoint

Key Vault and staging Storage have public access disabled. A deployment
workstation without approved private-link connectivity cannot write secrets.
An error containing `ForbiddenByConnection` and `Public network access is
disabled` is the expected network boundary, not a reason to enable public
access, add a workstation IP, create a SAS, or use a storage key.

Prepare the private endpoint and grant `dc01` temporary secret-seeding access:

```powershell
.\scenarios\azure-native\scripts\Repair-KeyVaultAccess.ps1 `
  -ResourceGroupName rg-opmlab-source
```

Through Bastion or another approved private management path, copy
`artifacts\lab.zip` to `C:\ProgramData\OnPremLab\lab.zip` on all five VMs and
copy `configuration\powershell\Set-LabKeyVaultSecrets.ps1` to `dc01`. On
`dc01`, run:

```powershell
.\Set-LabKeyVaultSecrets.ps1 -KeyVaultName <key-vault-name>
```

Return to the workstation and restore least-privilege access:

```powershell
.\scenarios\azure-native\scripts\Repair-KeyVaultAccess.ps1 `
  -ResourceGroupName rg-opmlab-source `
  -Finalize
```

Resolve the generated Storage/Key Vault names and resume:

```powershell
$resourceGroup = 'rg-opmlab-source'
$storageAccount = az storage account list `
  --resource-group $resourceGroup `
  --query "[?tags.workload=='on-prem-modernization-lab'].name | [0]" `
  --output tsv
$keyVault = az keyvault list `
  --resource-group $resourceGroup `
  --query '[0].name' `
  --output tsv

.\scenarios\azure-native\scripts\Initialize-Lab.ps1 `
  -ResourceGroupName $resourceGroup `
  -StorageAccountName $storageAccount `
  -KeyVaultName $keyVault `
  -ArtifactSource Local

.\scenarios\azure-native\scripts\Export-DiscoveryInventory.ps1 `
  -ResourceGroupName $resourceGroup
```

## Nested virtualization

Review `scenarios\nested-virtualization\README.md` before deployment. Confirm the
host SKU, quota, approved guest/media inputs, disk budget, and expected cost.

```powershell
.\scripts\Deploy-Lab.ps1 `
  -Scenario NestedVirtualization `
  -Iac Bicep `
  -ResourceGroupName rg-opmlab-nested `
  -Location eastus2 `
  -GuestMediaManifestPath C:\LabPrivate\guest-media-manifest.json
```

Use `-Iac Terraform` for the equivalent Terraform implementation. The scenario
deploys one private nested-capable `hyperv01` Azure VM, then creates/configures
inner `dc01`, `web01`, `web02`, `sql01`, and `migrate01` in dependency order.
Missing media or an unsupported/undersized host is an actionable preflight
failure, not a condition the script bypasses.

The Hyper-V provisioning phases are restartable. Follow the scenario command's
checkpoint output if approved media or interactive appliance preparation must
be completed before resuming.

## Validate

```powershell
.\scripts\Test-Lab.ps1 `
  -Scenario <AzureNative-or-NestedVirtualization> `
  -ResourceGroupName <resource-group>
```

For either scenario, verify both IIS sites read the shared SQL inventory, SQL
contains four seeded products, synthetic traffic runs, and no workload is
exposed through a public IP.

## Checkpoint

- The selected scenario and IaC engine are recorded.
- All five logical roles are ready.
- Both sites return inventory and share updates.
- SQL and synthetic traffic checks pass.
- The matching discovery workflow is ready for module 02.
