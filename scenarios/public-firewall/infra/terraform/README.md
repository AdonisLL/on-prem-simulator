# Terraform deployment

This implementation mirrors the Azure-native lab estate while placing ingress
and default egress behind Azure Firewall Standard. The five workload VMs remain
private-only and Azure Firewall owns three Standard static public IPs:

- `web01`: TCP 80 DNAT to `10.50.3.4:80`
- `web02`: TCP 80 DNAT to `10.50.3.5:80`
- `sql01`: TCP 1633 DNAT to `10.50.4.4:1433`

`deployer_address_prefix` is mandatory and is the only public DNAT / exposed
NSG source. Key Vault stays RBAC-enabled with purge protection, Storage keeps
shared-key access disabled, and both services default to private access with
private endpoints. `enable_temporary_deployment_access=true` turns on limited
public access for the deployer plus the firewall public IP set during bootstrap.

```powershell
$env:ARM_SUBSCRIPTION_ID = az account show --query id --output tsv
$env:TF_VAR_admin_password = '<generated secure value>'
terraform -chdir=scenarios\public-firewall\infra\terraform init
terraform -chdir=scenarios\public-firewall\infra\terraform plan -out lab.tfplan
terraform -chdir=scenarios\public-firewall\infra\terraform apply lab.tfplan
```

Do not commit `.tfstate`, plan files, or variable files containing secrets.
