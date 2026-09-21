# Sanitized configuration examples

These files are selected, sanitized examples derived from captured active configuration. They are included because they demonstrate specific infrastructure decisions; they are not intended as a complete deployment bundle.

- `proxmox-networking.interfaces.example` — static Proxmox bridge configuration plus persistent TSO workaround.
- `proxmox-storage.cfg.example` — dedicated live-data and backup mountpoint-backed storage definitions.
- `ubuntu-netplan.example.yaml` — static guest addressing on the homelab VLAN.
- `docker-mount-dependency.conf` — systemd dependency preventing Docker from starting before application data is mounted.

Addresses and paths are documentation values.
