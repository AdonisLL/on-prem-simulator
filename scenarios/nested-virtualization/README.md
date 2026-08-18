# Nested virtualization scenario

This scenario deploys one private Azure Windows Server Datacenter host,
`hyperv01`, then enables Hyper-V and creates inner `dc01`, `web01`, `web02`,
`sql01`, and `migrate01` VMs. Azure Migrate uses Hyper-V host discovery rather
than the Azure-native physical-server CSV workflow.

## Prerequisites

- A region with a nested-capable SKU and sufficient quota. The default
  `Standard_D32s_v5` accommodates the configured 22 inner/host vCPU floor,
  60-GB memory floor, and the 32-GB/8-vCPU appliance allocation.
- Azure CLI authentication. Terraform additionally requires Terraform 1.10+,
  the `Az.Compute` PowerShell module, and an authenticated `Connect-AzAccount`
  context for its ephemeral host provisioner.
- An existing private management path to the VNet. The scenario creates no
  public IP or public RDP rule.
- The outer VM uses Azure security type **Standard**, which Microsoft requires
  for nested virtualization. The default Dsv5 family is documented as
  supporting nested virtualization.
- Approved, staged Windows Server base VHDX, Azure Migrate Hyper-V appliance
  VHD, and copies of root `src`, `database`, and `configuration` content.

Copy `contracts\guest-media-manifest.example.json` outside tracked source,
replace its paths/hashes, and stage those paths on `hyperv01`. Media files and
local manifests are ignored and must not be committed.

## Deploy

```powershell
.\scripts\Deploy-Lab.ps1 `
  -Scenario NestedVirtualization `
  -Iac Bicep `
  -ResourceGroupName rg-opmlab-nested `
  -Location eastus2 `
  -GuestMediaManifestPath C:\LabPrivate\guest-media-manifest.json
```

Use `-Iac Terraform` for the equivalent Terraform infrastructure path.
`-SkipGuestConfiguration` deploys only Azure infrastructure, allowing approved
media to be staged before running:

```powershell
.\scenarios\nested-virtualization\scripts\Initialize-Lab.ps1 `
  -ResourceGroupName rg-opmlab-nested `
  -GuestMediaManifestPath C:\LabPrivate\guest-media-manifest.json
```

The inner VM definitions and disks are idempotent. Supplied images must be
prepared/specialized according to their licenses; the repository does not
download media. Guest specialization, static IP application, shared role
configuration, and appliance registration remain explicit checkpoints rather
than success-shaped automation.

## Validate and remove

```powershell
.\scripts\Test-Lab.ps1 `
  -Scenario NestedVirtualization `
  -ResourceGroupName rg-opmlab-nested

.\scripts\Remove-Lab.ps1 `
  -Scenario NestedVirtualization `
  -ResourceGroupName rg-opmlab-nested
```

Validation checks the Hyper-V feature, internal switch/NAT, and all five running
inner VMs. Azure Migrate project registration remains interactive.
