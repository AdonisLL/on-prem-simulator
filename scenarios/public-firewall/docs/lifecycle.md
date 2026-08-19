# Public firewall lifecycle contract

`Deploy-Lab.ps1` accepts the shared deployment parameters plus mandatory
`DeployerAddressPrefix`.

## Address validation

- IPv4 CIDR syntax is required.
- `/32` is enforced by default.
- A broader CIDR is allowed only when `-AllowNon32DeployerPrefix` is provided
  explicitly to the scenario-local deploy or test script.
- The lifecycle never auto-discovers or silently widens the deployer address.

## Temporary deployment access

This scenario assumes no private workstation connectivity. During deployment:

1. the resource group is tagged with `SecurityControl=Ignore` when the approved
   temporary exemption path is active;
2. scenario IaC enables Key Vault and Storage public access with `defaultAction`
   still set to `Deny`;
3. IaC limits those network ACLs to the deployer CIDR and Azure Firewall public
   addresses;
4. `lab.zip` is uploaded, secrets are seeded with RBAC retry, and guest
   configuration runs automatically.

## Guaranteed cleanup

The outer `finally` block always attempts to:

- disable Key Vault public network access and keep `defaultAction=Deny`;
- disable Storage public network access and keep `defaultAction=Deny`; and
- remove `SecurityControl=Ignore`, or restore the previous tag value.

Cleanup failures are appended to the primary deployment error instead of hiding
it. Successful validation also checks that the resource-group tag is no longer
left at `Ignore`.
