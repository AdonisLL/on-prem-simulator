# Starting Azure Migrate by scenario

This guide explains how to register and start Azure Migrate discovery for each
lab scenario. Microsoft currently supports individual or multiple IP/FQDN
entries and CSV import for physical-server discovery. It does not accept a
subnet or IP range and search it automatically.

Appliance registration, project keys, device sign-in, and credentials remain
interactive. Never store them in the repository.

## Common preparation

1. Create or select an Azure Migrate project in the intended subscription and
   geography.
2. Add **Azure Migrate: Discovery and assessment**.
3. Generate the project key for the discovery type used by the scenario.
4. Open the appliance configuration manager and complete prerequisites,
   updates, project-key registration, and device sign-in.
5. Confirm the appliance clock is correct and it can reach the required Azure
   service URLs.
6. Add `CONTOSO\svc-migrate` as the Windows discovery credential and add the
   separate SQL discovery credential through the approved secure handoff.

The lab configures WinRM HTTPS on TCP 5986. Keep the appliance's HTTPS protocol
option enabled so it does not fall back to WinRM HTTP.

## AzureNative

Choose **Physical or other (AWS, GCP, Xen, etc.)** when generating the project
key and configuring discovery.

1. Use Azure Bastion or another approved private management path to open
   `https://migrate01:44368`.
2. Run the exporter if deployment did not already generate the artifacts:

   ```powershell
   .\scenarios\azure-native\scripts\Export-DiscoveryInventory.ps1 `
     -ResourceGroupName rg-opmlab-source
   ```

3. Prefer **Add multiple items** in the appliance. Paste the four FQDNs from
   `artifacts\azure-migrate-discovery-sources.txt` and select the
   `CONTOSO\svc-migrate` credential.
4. If bulk entry is unavailable or validation is easier in a spreadsheet,
   download the appliance's current CSV template and copy values from
   `artifacts\azure-migrate-source-inventory.csv`. The generated file is source
   data, not a replacement for Microsoft's current template.
5. Validate all four servers and then select **Start discovery**.

Do not add `migrate01`; it hosts the appliance and is not a migration source.

## PublicFirewall

Choose **Physical or other (AWS, GCP, Xen, etc.)**. Server discovery is the same
as `AzureNative`; Azure Firewall changes operator ingress, not the Azure Migrate
discovery model.

1. Establish an approved management path to `migrate01` and open
   `https://migrate01:44368`. The scenario's public DNAT rules expose only the
   two web sites and SQL endpoint. They deliberately do not expose RDP or the
   appliance configuration UI. Use an approved private path or separately
   governed Azure Bastion deployment.
2. Run the exporter if needed:

   ```powershell
   .\scenarios\public-firewall\scripts\Export-DiscoveryInventory.ps1 `
     -ResourceGroupName rg-opmlab-public
   ```

3. Prefer **Add multiple items** using
   `artifacts\azure-migrate-discovery-sources.txt`.
4. Retain `artifacts\azure-migrate-source-inventory.csv` as the backup input for
   the appliance's current CSV template.
5. Validate `dc01`, `web01`, `web02`, and `sql01`, then start discovery.

The deployer's public `/32` controls access to published application endpoints;
it does not make the appliance UI publicly reachable.

## NestedVirtualization

Choose **Hyper-V** when generating the project key. Do not use either
physical-server artifact.

1. Use the approved private management path to connect to inner `migrate01` and
   complete appliance registration.
2. Add `hyperv01` as the Hyper-V host using the scenario's least-privilege host
   credential.
3. Validate the host and confirm Azure Migrate enumerates inner `dc01`,
   `web01`, `web02`, and `sql01`.
4. Add the Windows and SQL discovery credentials when prompted.
5. Enable software inventory and agentless dependency analysis, then start
   discovery.

This path queries Hyper-V's inventory. It does not scan an address range.

## Completion checks

- The appliance is registered to the intended Azure Migrate project.
- Exactly four source servers appear; `migrate01` is excluded.
- Credentials and connectivity validate successfully.
- Software inventory and agentless dependency analysis are enabled.
- No public RDP or broad discovery firewall rule was added to make setup work.

Use Microsoft's current
[physical-server discovery procedure](https://learn.microsoft.com/azure/migrate/tutorial-discover-physical)
or
[Hyper-V discovery procedure](https://learn.microsoft.com/azure/migrate/tutorial-discover-hyper-v)
if appliance labels or prerequisites differ from this lab.
