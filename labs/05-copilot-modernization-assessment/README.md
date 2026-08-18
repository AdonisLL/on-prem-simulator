# 05 - GitHub Copilot modernization assessment

This module creates and reviews a modernization plan. Milestone one stops before
target provisioning or cutover.

## Prepare

Review the Azure Migrate server, SQL, IIS, and dependency evidence. The
repository playbook in `.github\modernize\playbook` expresses intended
guardrails, but evidence can change the recommended migration sequence.

Install and select the current GitHub Copilot modernization tooling by following
[Microsoft's Copilot CLI guidance](https://learn.microsoft.com/dotnet/azure/migration/appmod/copilot-cli-support).
Organization policy must permit Copilot CLI and the modernization plugin.

From `src\LegacyWeb`, start the modernization agent and ask it to:

```text
Assess this .NET Framework application for modernization to Azure. Use the
repository playbook and the recorded Azure Migrate findings. Generate a plan,
but do not provision Azure resources or modify the source until the plan is
reviewed.
```

## Review

The plan should address:

- ASP.NET MVC 5 / `System.Web` to modern .NET;
- EF6 and SQL compatibility;
- Windows-integrated source identity to managed identity;
- local file storage to Blob Storage;
- in-process session/cache across multiple instances;
- configuration and secrets to App Configuration/Key Vault as appropriate;
- App Service deployment slots and Application Insights; and
- data migration, side-by-side validation, rollback, and cutover gates.

Do not accept a target merely because it was preselected. Compare App Service +
Azure SQL with the actual compatibility and dependency findings.

## Checkpoint

Save the generated assessment/plan in the tool's standard repository artifact
location. Review it with the instructor. Do not execute target deployment in
this milestone.
