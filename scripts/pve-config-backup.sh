#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# Sanitized, publication-oriented version of the live homelab workflow.
# It intentionally excludes SSH private keys and uses a narrow host-file allowlist.
BACKUP_MOUNT="${BACKUP_MOUNT:-/mnt/backup}"
BACKUP_ROOT="${BACKUP_ROOT:-$BACKUP_MOUNT/pve-config}"
PVE_GUEST_ID="${PVE_GUEST_ID:-100}"
RETENTION="${RETENTION:-8}"
STAMP="$(date '+%Y-%m-%d_%H%M%S')"
TMP="$BACKUP_ROOT/.incomplete-$STAMP"
FINAL="$BACKUP_ROOT/$STAMP"

if ! mountpoint -q "$BACKUP_MOUNT"; then
    echo "ERROR: $BACKUP_MOUNT is not a mountpoint" >&2
    exit 1
fi

# Persistent timers can catch up immediately after host boot. Wait until the
# Proxmox commands used by this workflow are actually ready before creating a
# backup generation.
echo "Waiting for Proxmox services to become ready..."
PVE_READY=0

for attempt in $(seq 1 30); do
    if pvesm status >/dev/null 2>&1 \
       && qm config "$PVE_GUEST_ID" >/dev/null 2>&1; then
        PVE_READY=1
        break
    fi

    if [[ "$attempt" -lt 30 ]]; then
        sleep 5
    fi
done

if [[ "$PVE_READY" -ne 1 ]]; then
    echo "ERROR: Proxmox services did not become ready within the readiness window" >&2
    exit 1
fi

mkdir -p "$TMP"

echo "Creating PVE configuration backup..."
{
    echo "Backup timestamp: $STAMP"
    echo
    echo "=== PVE VERSION ==="
    pveversion -v
    echo
    echo "=== STORAGE ==="
    pvesm status
    echo
    echo "=== VM $PVE_GUEST_ID ==="
    qm config "$PVE_GUEST_ID"
    echo
    echo "=== FILESYSTEMS ==="
    findmnt
} > "$TMP/manifest.txt"

echo "Creating consistent pmxcfs database snapshot..."
sqlite3 /var/lib/pve-cluster/config.db \
  ".backup '$TMP/config.db'"

DB_CHECK="$(sqlite3 "$TMP/config.db" 'PRAGMA integrity_check;')"
if [[ "$DB_CHECK" != "ok" ]]; then
    echo "ERROR: config.db integrity check failed:" >&2
    echo "$DB_CHECK" >&2
    exit 1
fi

echo "config.db integrity check: OK"

echo "Archiving selected host configuration..."

# Explicit allowlist avoids sweeping credential-bearing files into an
# unencrypted archive. Add environment-specific files only after review.
HOST_CONFIG=(
    etc/network/interfaces
    etc/hosts
    etc/resolv.conf
    etc/systemd/system/app-state-backup.service
    etc/systemd/system/app-state-backup.timer
    etc/systemd/system/pve-config-backup.service
    etc/systemd/system/pve-config-backup.timer
    root/bin/app-state-backup.sh
    root/bin/pve-config-backup.sh
)

EXISTING_CONFIG=()
for ITEM in "${HOST_CONFIG[@]}"; do
    [[ -e "/$ITEM" ]] && EXISTING_CONFIG+=("$ITEM")
done

if (( ${#EXISTING_CONFIG[@]} == 0 )); then
    echo "ERROR: no allowlisted host configuration files were found" >&2
    exit 1
fi

tar \
  --numeric-owner \
  --acls \
  -C / \
  -cf - \
  "${EXISTING_CONFIG[@]}" \
  | zstd -T0 -3 -q -o "$TMP/pve-config.tar.zst"

echo "Testing compressed archive..."
zstd -q -t "$TMP/pve-config.tar.zst"

echo "Generating checksums..."
(
    cd "$TMP"
    sha256sum \
      manifest.txt \
      config.db \
      pve-config.tar.zst \
      > SHA256SUMS

    sha256sum -c SHA256SUMS
)

mv "$TMP" "$FINAL"

echo "Applying $RETENTION-generation retention..."
mapfile -t OLD_GENERATIONS < <(
    find "$BACKUP_ROOT" \
      -mindepth 1 -maxdepth 1 -type d \
      -regextype posix-extended \
      -regex '.*/[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{6}' \
      -printf '%f\n' |
    sort -r |
    tail -n "+$((RETENTION + 1))"
)

for OLD in "${OLD_GENERATIONS[@]}"; do
    echo "  Pruning $OLD"
    rm -rf -- "$BACKUP_ROOT/$OLD"
done

echo
echo "PVE configuration backup completed:"
echo "$FINAL"
du -sh "$FINAL"
