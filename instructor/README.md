# Instructor guide

## Recommended delivery model

Deploy and register a reference environment at least 24 hours before the
workshop. Azure Migrate collection intervals make a same-hour deployment
unsuitable for every assessment screenshot. Keep a clean participant deployment
available for hands-on configuration and a pre-warmed project for analysis.

Select and record `AzureNative` or `NestedVirtualization` before deployment.
Pre-warm each discovery mode separately: physical-server CSV evidence is not a
substitute for Hyper-V host discovery.

## Expected estate

| Host | Role | Azure-native private IP |
|---|---|---:|
| `dc01` | AD DS, DNS, AD CS, synthetic client | `10.50.2.4` |
| `web01` | IIS / ASP.NET MVC 5 | `10.50.3.4` |
| `web02` | IIS / ASP.NET MVC 5 | `10.50.3.5` |
| `sql01` | SQL Server 2016 SP3 Developer | `10.50.4.4` |
| `migrate01` | Azure Migrate appliance host | `10.50.1.4` |

The nested scenario preserves these logical names but uses deterministic inner
addresses defined by its parity contract. Azure contains only the outer
`hyperv01` VM for that scenario.

Expected runtime edges are `dc01 -> web01`, `dc01 -> web02`, both web servers to
`sql01`, and domain/DNS traffic to `dc01`.

## Expected findings

- Classic ASP.NET MVC 5 and .NET Framework 4.8.
- `System.Web`, `web.config`, in-process session, and machine-local uploads.
- Windows-integrated SQL connection under a domain service account.
- SQL Server 2016 and a cross-database reporting view.
- Two separate IIS instances without a load balancer or shared session/files.

Assessment rule text changes. Grade the participant's evidence and reasoning,
not an exact count or sentence.

## Secure credential handoff

Deployment-generated discovery credentials live in Key Vault. Use an approved
ephemeral handoff mechanism. Never paste them into slides, repository files,
chat transcripts, screenshots, or lab exports.

## Troubleshooting order

1. Confirm deployment and VM power state.
2. Run `scripts\Test-Lab.ps1 -Scenario <selected-scenario>`.
3. Check domain DNS and membership.
4. Validate certificate chain/name and WinRM 5986.
5. Validate discovery group/IIS permissions.
6. Validate SQL 1433 and the SQL discovery login.
7. Check appliance outbound HTTPS and portal-reported issues.
8. Check collection time before changing configuration.

Do not enable workload public IPs or WinRM HTTP as a workaround.

## Reset and teardown

Use `scripts\Reset-Lab.ps1 -Scenario <selected-scenario>` to reseed products and
restart synthetic traffic. Use `scripts\Remove-Lab.ps1 -Scenario
<selected-scenario>` after delivery. Confirm the resource group is actually
deleted; auto-shutdown alone leaves billable resources and nested guest disks.

## Delivery checkpoints

- Prerequisite/quota check before participants deploy.
- Source validation before appliance setup.
- Azure-native: four explicitly imported source hosts, not a claimed VNet scan.
- Nested virtualization: the Hyper-V host is accepted and its four source inner
  VMs are enumerated through Hyper-V discovery.
- Successful credentials and enabled inventory/dependencies.
- Pre-warmed data available before assessment exercises.
- Modernization plan reviewed before any source modification.
- Teardown owner named and deletion verified.
