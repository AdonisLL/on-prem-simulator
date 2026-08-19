# 00 - Prerequisites

## Objectives

- Select an Azure commercial subscription and region.
- Confirm permissions and local tools.
- Understand cost, security, and teardown responsibilities.

## Select a scenario

| Scenario | Discovery | Azure footprint | Choose when |
|---|---|---|---|
| `AzureNative` | Physical-server inventory with explicit FQDN/IP or CSV | Five workload VMs plus private networking | Cost and repeatability matter most |
| `NestedVirtualization` | Hyper-V host discovery enumerates inner VMs | One large nested-capable Hyper-V host plus private networking | Hypervisor discovery realism justifies the higher host requirements |
| `PublicFirewall` | Physical-server inventory with explicit FQDN/IP or CSV | Five private VMs plus Azure Firewall and three public IPs | Private management connectivity is unavailable and a deployer `/32` can be allowlisted |

Record the choice. Every root lifecycle command requires `-Scenario`.

## Required access

You need permission to create a resource group, role assignments, virtual
machines, networking, Bastion, NAT, storage, role assignments, and an Azure
Migrate project. The Azure-native path also uses private Key Vault. You need
permission to register required resource providers.

Authenticate and confirm the intended subscription:

```powershell
az login
az account show --output table
```

Install PowerShell 7, Azure CLI with Bicep, Visual Studio 2022 Build Tools with
the .NET Framework 4.8 targeting pack and web build tools, and Terraform 1.10 or
later if using Terraform. From an elevated PowerShell session, install Build
Tools with:

```powershell
winget install --id Microsoft.VisualStudio.2022.BuildTools --exact `
  --override "--wait --passive --add Microsoft.VisualStudio.Workload.WebBuildTools --add Microsoft.Net.Component.4.8.TargetingPack --includeRecommended"
```

Restart PowerShell after installation. The deployment script locates MSBuild
through Visual Studio Installer and uses it to restore the legacy NuGet
`packages.config`; a separate `nuget.exe` installation is not required.

## Regional preflight

The deployment script verifies the SQL Server image. You can check it directly:

```powershell
az vm image show `
  --location eastus2 `
  --urn MicrosoftSQLServer:sql2016sp3-ws2019:sqldev:latest
```

Also confirm quota for the chosen sizes. For `NestedVirtualization`, confirm the
outer VM SKU advertises nested virtualization and has enough vCPU, memory, and
disk for all five inner VMs. Prepare approved Windows guest, SQL Developer, and
Azure Migrate appliance media as required by the scenario README. Never commit
ISO, VHD, VHDX, or registration-key files.

For `PublicFirewall`, determine the deployer's public IPv4 address through an
approved method and append `/32`. Do not use `0.0.0.0/0`, a broad corporate
range, or an automatically discovered address that the operator has not
reviewed.

## Cost agreement

All scenarios generate charges. Azure-native uses five workload VMs; nested
virtualization uses a much larger host and several inner disks. Auto-shutdown
does not remove every charge. `PublicFirewall` also incurs Azure Firewall and
three Standard public-IP charges. Record the source resource-group name and keep the
matching teardown command available:

```powershell
.\scripts\Remove-Lab.ps1 `
  -Scenario AzureNative `
  -ResourceGroupName rg-opmlab-source
```

## Checkpoint

- Correct subscription selected.
- Required tools respond on the command line.
- SQL image and VM quota are available.
- The selected scenario's image, media, nested-capability, and resource checks
  pass.
- You can create role assignments.
- You know who will verify resource-group deletion.
