# On-Premises Modernization Lab

This repository creates a connected Windows source estate for an Azure Migrate
and GitHub Copilot modernization workshop:

- `dc01`: AD DS, DNS, AD CS, and synthetic workload
- `web01` and `web02`: ASP.NET MVC 5 / .NET Framework 4.8 on IIS
- `sql01`: SQL Server 2016 SP3 Developer
- `migrate01`: Azure Migrate appliance

The source application and database are intentionally legacy but runnable. The
lab stops after discovery, assessment, dependency analysis, and an
evidence-driven modernization plan; target migration and cutover are later
milestones.

## Choose a deployment strategy

| Strategy | Azure Migrate discovery | Azure topology | Best fit |
|---|---|---|---|
| `AzureNative` | Physical-server workflow with explicit FQDN/IP or generated CSV | Five private Azure VMs | Lower complexity, predictable workshops, and lower host requirements |
| `NestedVirtualization` | Hyper-V workflow querying the outer host to enumerate inner VMs | One large private nested-capable Hyper-V host containing all five logical VMs | Greater hypervisor-discovery realism when quota, cost, media, and policy allow it |

Both scenarios support Bicep and Terraform. They share the application,
database, guest configuration, participant labs, and instructor material while
keeping scenario infrastructure and lifecycle implementation isolated.

> [!IMPORTANT]
> The Azure-native physical-server appliance does not scan a VNet. Servers must
> be supplied explicitly. The nested scenario instead uses genuine Hyper-V host
> discovery. Neither scenario represents a production migration topology.

## Repository layout

| Path | Purpose |
|---|---|
| `scenarios\azure-native\` | Five-Azure-VM infrastructure, lifecycle, parity contract, and physical discovery support |
| `scenarios\nested-virtualization\` | Hyper-V host infrastructure, inner-estate lifecycle, parity contract, and Hyper-V discovery support |
| `scripts\` | Stable root dispatchers and shared validation |
| `src\` | Legacy ASP.NET MVC application and tests |
| `database\` | SQL schema, seed data, and expected assessment findings |
| `configuration\` | Shared idempotent Windows role configuration |
| `labs\` | Participant modules with scenario branches |
| `instructor\` | Delivery checkpoints, troubleshooting, and expected evidence |
| `docs\` | Shared architecture and parameter contracts |

## Prerequisites

- Azure commercial subscription and permission to create the selected
  scenario's resource group, networking, VMs, disks, identities, role
  assignments, and Azure Migrate project
- PowerShell 7 and Azure CLI with Bicep support
- Visual Studio 2022 Build Tools with .NET Framework 4.8 targeting and web build
  tools
- Terraform 1.10 or later when using Terraform
- Region/SKU/image quota for the selected scenario
- For nested virtualization, a supported nested-capable VM size and approved
  Windows, SQL Developer, and appliance media required by the scenario contract

Never commit ISO/VHD media, credentials, appliance keys, local parameter files,
Terraform state, or plans.

## Deploy

Authenticate and select the intended subscription:

```powershell
az login
az account set --subscription '<subscription-id-or-name>'
az account show --query '{name:name, id:id}' --output table
```

Azure-native with Bicep:

```powershell
.\scripts\Deploy-Lab.ps1 `
  -Scenario AzureNative `
  -Iac Bicep `
  -ResourceGroupName rg-opmlab-source `
  -Location eastus2
```

Nested virtualization with Terraform:

```powershell
.\scripts\Deploy-Lab.ps1 `
  -Scenario NestedVirtualization `
  -Iac Terraform `
  -ResourceGroupName rg-opmlab-nested `
  -Location eastus2 `
  -GuestMediaManifestPath C:\LabPrivate\guest-media-manifest.json
```

Terraform prompts for approval unless `-AutoApprove` is supplied. Nested
deployment performs capability/resource/media preflight before creating the
inner estate.

### Private Key Vault checkpoint

The Azure-native scenario keeps Key Vault and staging Storage private-only. If
the deployment workstation is outside the private-link path, a Key Vault
`ForbiddenByConnection` error means secret creation must resume from the
authorized in-VNet bootstrap described in
`labs\01-deploy-source\README.md`. Do not enable public access, add the
workstation IP, use a storage key, or mint a SAS as a workaround.

## Validate and continue

```powershell
.\scripts\Test-Lab.ps1 `
  -Scenario AzureNative `
  -ResourceGroupName rg-opmlab-source
```

Replace the scenario/resource group for nested virtualization. Then follow
`labs\README.md`. Appliance registration and project keys remain interactive.

## Reset and teardown

```powershell
.\scripts\Reset-Lab.ps1 `
  -Scenario AzureNative `
  -ResourceGroupName rg-opmlab-source

.\scripts\Remove-Lab.ps1 `
  -Scenario AzureNative `
  -ResourceGroupName rg-opmlab-source `
  -Confirm:$false
```

Auto-shutdown does not remove disks, networking, Bastion, NAT, or other billable
resources. Verify resource-group deletion after every workshop. Nested
virtualization can be especially expensive because the outer host must support
all inner VMs, including the Azure Migrate appliance.

## Security boundaries

- No inner or Azure-native workload receives a public IP.
- WinRM uses HTTPS; HTTP fallback is not the default.
- Secrets are generated/provided at deployment time and never written to source,
  logs, outputs, or examples.
- Private Key Vault/Storage controls are not weakened for workstation access.
- GitHub Actions deployments use OIDC and environment approval.
- Azure Migrate registration material is never automated or committed.

See `docs\architecture.md` and `docs\parameter-contract.md` for the detailed
scenario contracts.
