# Backup automation

These are sanitized publication-oriented versions of two Bash workflows used in the homelab.

They are included to demonstrate the operational controls rather than as turnkey scripts for another environment. Before use, review all paths, IDs, retention values, remote access settings, and restore requirements.

## `app-state-backup.sh`

Backs up selected state from the Ubuntu Docker VM over SSH. Core behaviours include:

- backup-mount verification;
- bounded SSH-readiness check before container shutdown or generation creation;
- incomplete-work directory only after readiness succeeds and until validation completes;
- metadata capture;
- controlled stop/restart of currently running containers;
- Compose/application-data/Docker-volume capture;
- `EXIT`-trap recovery behaviour;
- SHA-256 checksums and `zstd` archive tests;
- generation-based retention.

## `pve-config-backup.sh`

Captures Proxmox configuration state. Core behaviours include:

- backup-mount verification;
- bounded Proxmox command-readiness checks for boot-time catch-up runs;
- environment manifest;
- consistent SQLite backup of the Proxmox `config.db` database;
- `PRAGMA integrity_check` validation;
- selected host-configuration archive;
- archive and checksum validation;
- generation-based retention.

The public version intentionally excludes SSH private keys and uses a narrow host-file allowlist. Full credential/offsite recovery remains a separate design concern.
