# Expected database assessment findings

The database remains functional on SQL Server 2016 while exposing a small,
teachable modernization backlog:

| Finding | Why it appears | Intended remediation |
|---|---|---|
| Cross-database view in `LegacyReporting` | Azure SQL Database does not support traditional three-part cross-database references | Consolidate the reporting view into `LegacyLab`, or evaluate an alternative only if the assessment justifies it |
| Windows-integrated application connection | The source uses an AD service identity | Use App Service managed identity and Microsoft Entra authentication for Azure SQL |
| SQL certificate trust bypass | The legacy connection encrypts transport but trusts the source SQL certificate without chain validation | Use a publicly trusted/private-CA certificate as appropriate and enforce target TLS validation |
| SQL Server 2016 compatibility baseline | The source represents an aging platform | Test at the current Azure SQL compatibility level and address query regressions |

Do not add artificial blockers that prevent the source application from running.
Assessment output can change as Microsoft updates rules; instructor guidance
should compare observed results with this intent rather than demand exact text.
