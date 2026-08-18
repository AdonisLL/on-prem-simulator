# Guest configuration

These scripts configure the Windows guests after IaC creates the VM shells.
They intentionally do not register the Azure Migrate appliance because current
registration requires a project-specific key and interactive device login.

## Phases

1. `DomainController` promotes `dc01` and installs DNS.
2. `CertificateAuthority` installs the lab enterprise root CA.
3. `DomainMember` points a VM at lab DNS and joins the domain.
4. `Sql` enables fixed TCP 1433, deploys idempotent schema/seed scripts, and
   grants the web service identity.
5. `Web` installs IIS/.NET Framework and expands the built web package.
6. `Traffic` creates a scheduled synthetic request across both sites.

After domain certificate auto-enrollment, `Enable-LabWinRmHttps` requires a
CA-issued Server Authentication certificate and removes the HTTP listener. It
fails rather than silently falling back to insecure WinRM.

Credentials are accepted as `SecureString` or `PSCredential`. Lifecycle scripts
must retrieve them from Key Vault without printing them. Do not put passwords in
extension command lines, public settings, or deployment outputs.

Run the parser check with:

```powershell
.\configuration\powershell\Test-ConfigurationScripts.ps1
```
