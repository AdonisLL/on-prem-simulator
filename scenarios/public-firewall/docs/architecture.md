# Public firewall architecture

The logical estate remains `dc01`, `web01`, `web02`, `sql01`, and `migrate01`.
All VM NICs stay private. Azure Firewall Standard owns the only public ingress.

| Public endpoint | Translation | Purpose |
|---|---|---|
| `web01` TCP 80 | public TCP 80 -> `web01` private TCP 80 | Independent IIS endpoint |
| `web02` TCP 80 | public TCP 80 -> `web02` private TCP 80 | Independent IIS endpoint |
| `sql01` TCP 1633 | public TCP 1633 -> `sql01` private TCP 1433 | External SQL reachability check without exposing 1433 directly |

Only `DeployerAddressPrefix` is accepted on the firewall DNAT rules. There is
no public RDP rule and no VM public IP.

Azure Firewall is also the controlled egress path used while guest bootstrap
downloads `lab.zip` from Storage and reads secrets from Key Vault. Those PaaS
network ACLs are limited to:

- the explicit deployer CIDR; and
- the Azure Firewall public IP addresses.

This topology is intentionally more expensive than the private-only Azure-native
scenario because it adds:

- Azure Firewall Standard hourly processing charges; and
- three Standard public IPs in addition to the usual VM, disk, and network cost.

Tear the resource group down as soon as the workshop ends.
