# Case studies

These short notes focus on specific engineering decisions rather than general homelab setup.

- [Intel `e1000e` hardware hangs](nic-hardware-hangs.md) — driver-level network troubleshooting, persistent mitigation, and validation against later logs.
- [Storage mount ordering](storage-mount-ordering.md) — converting a filesystem assumption into an explicit systemd dependency for Docker.
- [Persistent systemd timer boot-readiness race](backup-boot-readiness.md) — diagnosing a missed-schedule startup race, adding bounded readiness checks, and reproducing the original failure condition to validate the fix.
