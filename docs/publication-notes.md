# Publication and sanitization notes

This repository is a curated public representation of a live personal homelab. It is designed to demonstrate technical work without publishing the environment itself.

## Sanitization model

The public repository replaces or omits information that is unnecessary to the engineering story.

| Private data type | Public treatment |
|---|---|
| Internal IP addresses | Replaced with example `10.10.x.0/24` addressing |
| Public/Dynamic-DNS names | Replaced with `example.net`-style names or omitted |
| Host/device names | Generalized |
| Usernames and personal paths | Replaced with generic paths |
| MAC addresses / UUIDs / serials | Omitted |
| SSH keys / passwords / API values | Never included |
| Raw logs | Excluded; only short non-sensitive excerpts are quoted in case studies |
| Full router/firewall exports | Excluded |
| Complete application configuration | Excluded unless it directly supports an infrastructure claim |

The example subnets are documentation values and do not represent the live network.

## Relationship to the live implementation

The architecture and case studies are based on the project's private documentation and captured server-side evidence.

The scripts in `scripts/` are **sanitized publication-oriented versions** of the deployed backup workflows. They retain the core control flow and validation design while replacing environment-specific values. The public Proxmox configuration backup script also deliberately narrows the host-file allowlist and excludes credential material.

Configuration files in `configs/` are sanitized from captured active configuration where that source material was available.

## Evidence boundaries

This project supports claims of hands-on experience with:

- Linux and systemd administration;
- Proxmox VE and virtualisation;
- Docker-based workloads;
- VLAN/network design and Linux host networking;
- storage and mount management;
- Bash automation;
- backup creation, integrity checking, and representative scoped recovery;
- troubleshooting based on logs and runtime state.

It should **not** be read as evidence of:

- enterprise-scale production ownership;
- clustered/high-availability Proxmox;
- complete bare-metal disaster recovery;
- production cloud engineering;
- enterprise security operations.

The environment is intentionally presented at its real scale.
