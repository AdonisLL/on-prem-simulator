# 02 - Configure the Azure Migrate appliance

Create an Azure Migrate project in the selected commercial subscription and
geography, add **Discovery and assessment**, and use the discovery path that
matches the deployed scenario. Appliance registration, project keys, and device
sign-in are intentionally interactive and are never stored by this repository.

Follow the detailed
[scenario startup guide](../../docs/azure-migrate-scenario-guide.md). The
summary below identifies the correct discovery model.

## Azure-native and public-firewall: physical-server discovery

1. Choose discovery for physical or other virtualized servers.
2. Connect to `migrate01` through the scenario's approved management path.
3. Follow Microsoft's current
   [physical-server discovery tutorial](https://learn.microsoft.com/azure/migrate/tutorial-discover-physical).
4. Add `CONTOSO\svc-migrate` and the separate `migrate_discovery` SQL
   credential through the approved secure handoff.
5. Prefer **Add multiple items** with
   `artifacts\azure-migrate-discovery-sources.txt`.
6. Keep `artifacts\azure-migrate-source-inventory.csv` as the backup source for
   the appliance's current CSV template.
7. Keep software inventory and dependency analysis enabled and require WinRM
   HTTPS.

Azure Migrate does not accept a subnet or IP range for this workflow. Both
artifacts explicitly identify the four source servers; `migrate01` is excluded.

## Nested virtualization: Hyper-V discovery

This path uses genuine Hyper-V discovery. The appliance queries `hyperv01` and
enumerates its inner VMs; do not import the Azure-native physical-server CSV.

1. Choose discovery for **Hyper-V**.
2. Connect privately to inner `migrate01` and complete appliance registration.
3. Follow Microsoft's current Azure Migrate Hyper-V discovery requirements.
4. Add `hyperv01` using the scenario's least-privilege host credential.
5. Verify host validation succeeds and the appliance enumerates inner `dc01`,
   `web01`, `web02`, and `sql01`.
6. Enable software inventory and dependency analysis and add the separate
   Windows/SQL discovery credentials where requested.

If discovery fails, validate inner DNS/routing, the Hyper-V host credential and
required management services, appliance-to-host connectivity, and outbound
HTTPS before changing security controls.

## Checkpoint

- The appliance is registered to the intended project.
- Azure-native and public-firewall list exactly four explicitly supplied source
  servers.
- Nested virtualization shows the accepted Hyper-V host and its four source
  inner VMs.
- Credentials pass validation.
- Software inventory and dependency analysis are enabled.
