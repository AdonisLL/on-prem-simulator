# Nested architecture

The Azure footprint is one system-assigned-identity Windows Server VM with a
private NIC and dedicated Premium SSD. It has no public IP. Operators must
provide approved private connectivity.

The Hyper-V switch `NestedLabInternal` and NAT `NestedLabNat` use
`192.168.100.0/24`:

| Inner VM | Address | vCPU | Startup memory |
|---|---:|---:|---:|
| `dc01` | `192.168.100.10` | 2 | 4 GB |
| `sql01` | `192.168.100.20` | 4 | 8 GB |
| `web01` | `192.168.100.30` | 2 | 4 GB |
| `web02` | `192.168.100.31` | 2 | 4 GB |
| `migrate01` | `192.168.100.40` | 8 | 32 GB |

The appliance queries `hyperv01` using the Azure Migrate Hyper-V discovery
workflow and enumerates the inner source VMs. Registration keys and device login
are manual and never stored by this repository.
