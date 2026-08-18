# 03 - Discover and assess

## Allow collection time

Server configuration/performance, software inventory, dependency data, IIS
configuration, and SQL performance use different collection schedules in both
discovery modes.
IIS/SQL configuration can require up to 24 hours. Do not diagnose an empty
application inventory as failure immediately after registration.

Use the appliance status and Azure Migrate portal issue details to distinguish
collection still in progress from credential or connectivity failure.

## Review inventory

Confirm Azure Migrate reports:

- four Windows source servers;
- IIS and the ASP.NET application on `web01` and `web02`;
- SQL Server 2016 and the `LegacyLab`/`LegacyReporting` databases on `sql01`;
- installed roles and software consistent with each machine.

## Assess

1. Create a server assessment for the four-server application group.
2. Use performance-based sizing and record the observation duration.
3. Create an Azure SQL assessment with **Recommended** target type first.
4. Compare readiness for Azure SQL Database, Managed Instance, and SQL VM.
5. Export both assessment results.

Expected observations include aging Windows/SQL software, a cross-database
reference, and an application that needs identity/configuration changes. Tool
rules evolve, so record observed evidence instead of copying expected wording.

## Checkpoint

- Server assessment has a documented sizing basis and confidence rating.
- SQL assessment contains a recommendation and concrete compatibility evidence.
- Exports are saved outside the repository if they contain subscription data.
