# Modernization guardrails

Use Azure Migrate server, IIS, SQL, performance, and dependency evidence as
inputs. Do not invent production requirements or force a target that conflicts
with observed compatibility.

## Intended direction

- Upgrade the ASP.NET MVC 5 application from .NET Framework 4.8 to the current
  supported LTS .NET release.
- Prefer Azure App Service for the web workload unless assessment evidence
  demonstrates a requirement it cannot satisfy.
- Prefer Azure SQL Database when compatibility findings are remediated; document
  why Managed Instance or SQL VM is selected if they are required.
- Replace Windows-integrated SQL credentials with App Service managed identity
  and Microsoft Entra authentication.
- Move secrets out of configuration files and use Key Vault references or
  managed identity access.
- Replace machine-local uploads with Blob Storage.
- Remove or externalize in-process session/cache before scaling beyond one
  instance.
- Add Application Insights, structured logs, health checks, and deployment-slot
  validation.

## Delivery constraints

- Use side-by-side modernization with incremental, reviewable changes.
- Preserve source behavior until functional and data validation passes.
- Include unit, integration, migration, security, and rollback checks.
- Use IaC and GitHub Actions OIDC; never generate long-lived deployment secrets.
- Keep private connectivity and least privilege as target defaults.
- Do not deploy, migrate data, cut over traffic, or retire the source during the
  milestone-one assessment exercise.
