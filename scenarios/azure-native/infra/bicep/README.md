# Bicep deployment

The template creates the private source estate but deliberately does not
register the Azure Migrate appliance or put credentials in VM extension command
lines. The root `scripts\Deploy-Lab.ps1 -Scenario AzureNative` command performs preflight, deploys this template, and
then invokes the shared guest-configuration phases.

Key Vault and the staging storage account have public network access disabled;
Storage shared-key access is also disabled. The template creates the Key Vault
private endpoint, `privatelink.vaultcore.azure.net` zone, VNet link, and DNS zone
group. Follow the private secret-seeding, manual artifact staging, and resume
procedure in `labs\01-deploy-source\README.md`; do not add a deployer IP to an
NSG, enable account keys, or mint a SAS.

```powershell
$env:ONPREM_LAB_ADMIN_PASSWORD = '<generated secure value>'
az deployment group what-if --resource-group <rg> --parameters .\scenarios\azure-native\infra\bicep\main.bicepparam
az deployment group create --resource-group <rg> --parameters .\scenarios\azure-native\infra\bicep\main.bicepparam
```

Verify the SQL 2016 SP3 Developer image and all VM sizes in the selected region
before deployment. The SQL image intentionally has Trusted Launch disabled
because legacy marketplace image capabilities vary; the Windows Server roles
enable it by default.
