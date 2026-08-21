# Public firewall scenario

This scenario keeps all five lab VMs private and publishes only three
allowlisted Azure Firewall DNAT endpoints: `web01` on TCP 80, `web02` on TCP
80, and `sql01` on public TCP 1633 translated to private TCP 1433.

## Before you deploy

- Provide the deployer's public IPv4 address explicitly as
  `-DeployerAddressPrefix`. A `/32` is required by default; pass
  `-AllowNon32DeployerPrefix` only when you intentionally need a broader CIDR
  and call the scenario-local script directly.
- If a managed runner uses destination-specific egress for Azure traffic, pass
  each verified Azure-visible `/32` through
  `-AdditionalDeployerAddressPrefix`. Do not replace the primary public address;
  browser and runner traffic can use different paths.
- Plan for Azure Firewall Standard plus three Standard public IPs. This is one
  of the lab's more expensive topologies and should be torn down immediately
  after use.
- Expect the lifecycle to apply `SecurityControl=Ignore` during deployment
  access, then remove or restore that tag after guest configuration and cleanup.

## Deploy

The root dispatcher can launch this scenario directly:

```powershell
.\scripts\Deploy-Lab.ps1 `
  -Scenario PublicFirewall `
  -Iac Bicep `
  -ResourceGroupName rg-opmlab-public `
  -Location eastus2 `
  -DeployerAddressPrefix '203.0.113.10/32' `
  -AdditionalDeployerAddressPrefix @('198.51.100.20/32', '198.51.100.21/32') `
  -UseTemporaryPolicyExemption
```

The checked-in scenario infrastructure currently lives under
`infra\bicep` and `infra\terraform`. The scenario-local deploy script defaults
to `-Iac Bicep` and keeps `UseTemporaryPolicyExemption` enabled by default
because temporary restricted public access is part of this scenario's normal
lifecycle:

```powershell
.\scenarios\public-firewall\scripts\Deploy-Lab.ps1 `
  -Iac Terraform `
  -ResourceGroupName rg-opmlab-public `
  -Location eastus2 `
  -DeployerAddressPrefix '203.0.113.10/32' `
  -AdditionalDeployerAddressPrefix @('198.51.100.20/32', '198.51.100.21/32')
```

`LegacyWeb.zip` and `lab.zip` are rebuilt on every deployment. The upload and
secret-seeding phases require Key Vault and Storage public access to remain
enabled only long enough for the deployer and Azure Firewall public addresses to
reach them. The outer `finally` block then:

1. disables Key Vault public network access and enforces `defaultAction=Deny`;
2. disables Storage public network access and enforces `defaultAction=Deny`; and
3. removes `SecurityControl=Ignore`, or restores the prior value if one existed.

If you run with `-SkipGuestConfiguration`, re-run the same deploy command
without that switch to reopen the restricted deployment window and complete
guest configuration automatically.

If Storage returns `AuthorizationFailure` even though the configured deployer
IP rule is correct, the runner may reach Azure data-plane services through a
same-region or private path that IP rules cannot match. With
`-UseTemporaryPolicyExemption`, the script automatically retries using
authenticated public access only during artifact upload and secret bootstrap.
Pass `-AllowUnrestrictedTemporaryDeploymentAccess` only to force that fallback
before the first restricted request. The script disables each endpoint
immediately afterward and repeats lock-down in `finally`.

## Validate, reset, and remove

```powershell
.\scripts\Test-Lab.ps1 `
  -Scenario PublicFirewall `
  -ResourceGroupName rg-opmlab-public `
  -DeployerAddressPrefix '203.0.113.10/32' `
  -AdditionalDeployerAddressPrefix @('198.51.100.20/32', '198.51.100.21/32')

.\scripts\Reset-Lab.ps1 `
  -Scenario PublicFirewall `
  -ResourceGroupName rg-opmlab-public

.\scripts\Remove-Lab.ps1 `
  -Scenario PublicFirewall `
  -ResourceGroupName rg-opmlab-public
```

Validation confirms:

- no VM has a public IP;
- Azure Firewall publishes the expected three endpoints;
- both web endpoints return HTTP 200 from the allowlisted deployer; and
- the SQL public endpoint is reachable on TCP 1633 without using credentials.

See `docs\architecture.md` and `docs\lifecycle.md` for the endpoint map,
cleanup contract, and operational caveats. Follow
`../../docs/azure-migrate-scenario-guide.md` to register the appliance and use
the generated bulk discovery list with CSV as a backup.
