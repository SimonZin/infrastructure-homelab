# Case study: Intel `e1000e` hardware hangs

## Problem

The Proxmox host experienced periods where it became unreachable over the network.

Kernel journal evidence from one incident window showed repeated messages from the Intel `e1000e` driver:

```text
kernel: e1000e ... nic0: Detected Hardware Unit Hang:
```

The captured evidence contained **439** hardware-hang messages between approximately 14:30 and 20:26 on the incident day.

## Investigation

The investigation focused on the host network interface rather than immediately treating the problem as a switch, VM, or application failure.

Relevant checks included:

- reviewing kernel/journal history for `e1000e` events;
- confirming the physical interface and driver;
- reviewing link and offload state;
- checking whether the failure pattern recurred across boots;
- locating the persistent host networking configuration.

The repeated driver-level hardware-hang messages made the NIC/offload path the strongest lead.

## Change

TCP segmentation offload was disabled on the physical interface and the workaround was made persistent in the Proxmox network configuration:

```text
iface nic0 inet manual
        pre-up /usr/sbin/ethtool -K nic0 tso off
```

A sanitized version of the surrounding configuration is published at [`configs/proxmox-networking.interfaces.example`](../../configs/proxmox-networking.interfaces.example).

## Validation

Current offload evidence confirmed:

```text
tcp-segmentation-offload: off
```

No further `Detected Hardware Unit Hang` entries appeared in the subsequently captured journal evidence through the evidence-collection date.

That supports the workaround as effective in the observed period, but it is deliberately not presented as proof that the underlying hardware/driver issue has been permanently eliminated.

## What this demonstrated

This incident was useful practice in:

- starting from host/kernel evidence rather than application symptoms;
- distinguishing network-stack problems from service failures;
- applying a targeted workaround;
- making the change persistent rather than relying on an interactive command;
- validating the result over later logs rather than stopping at "the command worked".
