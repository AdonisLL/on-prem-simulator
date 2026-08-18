# Guest media contract

`GuestMediaManifestPath` is required unless deployment uses
`-SkipGuestConfiguration`. The manifest provides host and optional workstation
validation paths for:

- an approved, generalized Windows Server base VHDX;
- the current Azure Migrate Hyper-V appliance VHD; and
- staged copies of shared root `src`, `database`, and `configuration` content.

Provide SHA-256 hashes for immutable media. Initialization verifies host
existence and configured hashes before copying disks. Do not commit media,
registration keys, local manifests, or credentials.

The scenario creates and starts deterministic inner VM definitions. Because
licensed media preparation differs by organization, it does not pretend to
automate image specialization. Complete guest specialization, apply the
addresses in `scenario-definition.json`, run the shared role configuration, and
register the appliance through the documented checkpoints.
