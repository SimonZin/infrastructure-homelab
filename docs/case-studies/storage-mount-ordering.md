# Case study: preventing Docker from starting before application storage

## Problem

The Ubuntu Server VM stores persistent application data on a separately mounted filesystem at `/srv/library`.

Many Docker workloads use bind mounts beneath that path. This creates an important boot-order failure mode: if Docker starts before the filesystem is mounted, the bind-mount path can exist as an ordinary directory on the root filesystem. Containers may then start against empty or incorrect state.

## Risk

The immediate symptom can look like an application problem rather than a storage problem—for example, an application may appear to have lost its configuration and present a first-run setup screen.

Simply restarting the affected application is not a sufficient control because the underlying mount ordering remains incorrect.

## Control

A systemd drop-in was added to the Docker service:

```ini
[Unit]
RequiresMountsFor=/srv/library
After=srv-library.mount
```

The `RequiresMountsFor=` directive makes the filesystem requirement explicit, while `After=` expresses the ordering relationship with the generated mount unit.

The published sanitized drop-in is available at [`configs/docker-mount-dependency.conf`](../../configs/docker-mount-dependency.conf).

## Validation

The collected systemd evidence showed the drop-in in the effective Docker unit configuration and the generated `/srv/library` mount unit active. The private project changelog also records that the dependency behaviour was verified after reboot.

## Operational recovery rule

If an application unexpectedly appears unconfigured:

1. do not immediately recreate its configuration;
2. verify that `/srv/library` is mounted;
3. restore the correct mount state first;
4. recreate the affected container if it was started against the wrong bind-mount state;
5. confirm that the original application state is visible.

## What this demonstrated

The important lesson was not the syntax of one systemd directive. It was recognising that a service can be technically "running" while its storage dependency is wrong, and converting an implicit assumption into an explicit boot-time dependency.
