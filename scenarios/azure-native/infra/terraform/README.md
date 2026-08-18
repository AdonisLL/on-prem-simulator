# Terraform deployment

This implementation mirrors the Bicep source estate and reuses the shared guest
configuration. It intentionally leaves backend configuration to the operator so
local workshops and managed remote state can use the same root module.

Key Vault and the staging storage account have public network access disabled;
Storage shared-key access is also disabled. Terraform creates the Key Vault
private endpoint, `privatelink.vaultcore.azure.net` zone, VNet link, and DNS zone
group. Follow the private secret-seeding, manual artifact staging, and resume
procedure in `labs\01-deploy-source\README.md`; do not add a deployer IP to an
NSG, enable account keys, or mint a SAS.

```powershell
$env:ARM_SUBSCRIPTION_ID = az account show --query id --output tsv
$env:TF_VAR_admin_password = '<generated secure value>'
terraform -chdir=scenarios\azure-native\infra\terraform init
terraform -chdir=scenarios\azure-native\infra\terraform plan -out lab.tfplan
terraform -chdir=scenarios\azure-native\infra\terraform apply lab.tfplan
```

Do not commit `.tfstate`, plan files, or variable files containing secrets.
Verify regional VM sizes and the SQL Server 2016 SP3 Developer marketplace image
before planning. Use a new `deployment_id` after deleting a lab so a soft-deleted
purge-protected Key Vault name is not reused. Appliance registration remains an
interactive lab step.
