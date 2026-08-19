# Scenario parameter contracts

Root lifecycle commands require an explicit scenario:

```powershell
.\scripts\Deploy-Lab.ps1 -Scenario AzureNative -Iac Bicep
.\scripts\Deploy-Lab.ps1 -Scenario NestedVirtualization -Iac Terraform
.\scripts\Deploy-Lab.ps1 -Scenario PublicFirewall -Iac Bicep -DeployerAddressPrefix 203.0.113.10/32
```

The root command dispatches to scenario-local implementations. It never chooses
a scenario implicitly.

## Shared parameters

| Parameter | Default | Requirement |
|---|---|---|
| `Scenario` | none | Required: `AzureNative`, `NestedVirtualization`, or `PublicFirewall` |
| `Iac` | `Bicep` | `Bicep` or `Terraform` |
| `ResourceGroupName` | `rg-opmlab-source` | One disposable lab resource group |
| `Location` | `eastus2` | Azure commercial region validated by preflight |
| `NamePrefix` | `opmlab` | Lowercase prefix valid for derived resource names |
| `AdminPassword` | secure prompt | Never written to source, output, or logs |
| `SkipGuestConfiguration` | false | Stops after infrastructure for staged recovery |
| `AutoApprove` | false | Terraform approval remains explicit by default |
| `UseTemporaryPolicyExemption` | false | Azure-native/public-firewall; temporarily applies the approved `SecurityControl=Ignore` resource-group tag and deployment access, then locks down and restores/removes the tag in `finally` |
| `DeployerAddressPrefix` | none | Required for `PublicFirewall`; an explicit IPv4 CIDR, normally the deployer's current `/32`, used as the only public DNAT and NSG source |

All scenarios use `corp.contoso.local`, NetBIOS name `CONTOSO`, deterministic
logical host names, VM auto-shutdown, private workload access, and nonsecret
outputs.

## Azure-native additions

The Azure-native scenario exposes the existing subnet, VM-size, SQL image,
Bastion, diagnostics, and artifact parameters in
`scenarios\azure-native\infra`. Its shared output includes an explicit
physical-server discovery inventory. Key Vault and staging Storage remain
private-only; secret bootstrap occurs from an authorized in-VNet machine.

## Nested-virtualization additions

The nested scenario exposes the outer Hyper-V host size/image, host and inner
address ranges, switch/NAT configuration, disk/resource budgets, and approved
guest/appliance media inputs in `scenarios\nested-virtualization\infra` and its
lifecycle scripts. Preflight verifies nested-virtualization capability, regional
SKU availability, quota, image/media existence, and minimum resource budgets.

## Public-firewall additions

The public-firewall scenario keeps all VM NICs private and places Azure Firewall
Standard at the ingress/egress boundary. Three firewall public IPs provide:

- `web01`: TCP 80 to private TCP 80;
- `web02`: TCP 80 to private TCP 80; and
- `sql01`: public TCP 1633 to private TCP 1433.

DNAT and NSG rules accept only `DeployerAddressPrefix`. There is no public RDP
rule. Key Vault and Storage deployment access is temporary and restricted; the
lifecycle cleanup restores default-deny and policy enforcement.

## Parity rules

Bicep and Terraform must be equivalent within each scenario. The scenarios
intentionally have different Azure resource topologies and therefore use
separate parity contracts. CI checks:

- Azure resource roles and subnet intent;
- private/public IP posture;
- VM image, disk, identity, and shutdown intent;
- scenario configuration phases and logical inner roles;
- shared outputs and secure/sensitive inputs; and
- lifecycle and teardown behavior.

Outputs must never contain passwords, connection strings, storage keys, SAS
tokens, appliance project keys, or Terraform backend credentials.
