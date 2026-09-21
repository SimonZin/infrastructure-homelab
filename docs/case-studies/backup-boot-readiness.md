# Case study: persistent systemd timer boot-readiness race

## Problem

The homelab uses systemd calendar timers for application-state and Proxmox-configuration backups. The timers are persistent so a scheduled run missed while the host is powered off can be caught up after the host starts again.

Captured boot journals showed that this catch-up behaviour exposed a race: the backup services could start before the dependencies they used were actually ready.

For the application-state backup, the sequence was effectively:

```text
backup service starts
SSH connection attempted -> no route to guest yet
Proxmox guest startup begins
Ubuntu VM starts
```

The Proxmox-configuration job exhibited a related failure during early boot, with Proxmox CLI calls returning connection errors before the required host services were ready.

Normal scheduled runs after the system was fully booted were succeeding, which helped isolate the fault to startup ordering/readiness rather than the backup payload itself.

## Cause

`Persistent=true` was doing what it was configured to do: catch up missed calendar events when the timer became active again.

The original backup jobs implicitly assumed that timer activation meant the environment was ready. That assumption was false during early boot:

- a started VM process does not mean the guest network and SSH service are already reachable;
- a started host does not mean every Proxmox command required by the backup is immediately usable.

Service ordering could reduce the race, but ordering alone was not sufficient for guest SSH readiness.

## Change

The correction used two layers.

### Systemd ordering

The application-state service is ordered after network-online and Proxmox guest startup. The Proxmox-configuration service is ordered after the relevant Proxmox cluster/daemon/status services.

### Bounded readiness checks

The application-state script now probes SSH in a bounded retry loop **before** creating a backup generation or stopping containers.

The Proxmox-configuration script similarly waits until the Proxmox storage and VM-configuration commands it depends on succeed.

The public scripts demonstrate these command-level readiness checks:

- [`scripts/app-state-backup.sh`](../../scripts/app-state-backup.sh)
- [`scripts/pve-config-backup.sh`](../../scripts/pve-config-backup.sh)

Moving readiness ahead of `.incomplete-*` creation also prevents an expected transient boot condition from leaving empty failed-generation directories.

## Validation

The missed-schedule condition was deliberately recreated and the Proxmox host rebooted.

On the validation boot:

- the Proxmox-configuration backup caught up after boot, waited for its dependencies, and completed successfully;
- the application-state backup caught up after boot, waited approximately 15 seconds until guest SSH became available, then completed its normal backup/validation sequence;
- both systemd services reported `Result=success` and `ExecMainStatus=0`.

The previous failure condition was therefore reproduced under controlled conditions and no longer caused either backup job to fail.

## What this demonstrated

This issue was useful practice in:

- comparing successful scheduled runs with failed boot-time runs;
- using systemd and journal timing to identify an ordering/readiness race;
- distinguishing service ordering from actual application/protocol readiness;
- using bounded retries rather than an arbitrary fixed sleep;
- validating the correction by recreating the original triggering condition rather than testing only on an already-running system.
