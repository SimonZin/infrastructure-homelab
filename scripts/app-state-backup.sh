#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# Sanitized portfolio version of the live homelab workflow.
# Adjust these values for a real environment before use.
BACKUP_MOUNT="${BACKUP_MOUNT:-/mnt/backup}"
BACKUP_ROOT="${BACKUP_ROOT:-$BACKUP_MOUNT/app-state}"
REMOTE="${REMOTE:-root@10.10.20.11}"
SSH_KEY="${SSH_KEY:-/root/.ssh/id_ed25519_backup}"
REMOTE_COMPOSE_PARENT="${REMOTE_COMPOSE_PARENT:-/home/homelab}"
REMOTE_COMPOSE_NAME="${REMOTE_COMPOSE_NAME:-compose}"
REMOTE_APPDATA_PARENT="${REMOTE_APPDATA_PARENT:-/srv/library}"
REMOTE_APPDATA_NAME="${REMOTE_APPDATA_NAME:-appdata}"
RETENTION="${RETENTION:-14}"
STAMP="$(date '+%Y-%m-%d_%H%M%S')"

SSH=(
  ssh
  -i "$SSH_KEY"
  -o IdentitiesOnly=yes
  -o BatchMode=yes
  -o ConnectTimeout=5
  "$REMOTE"
)

if ! mountpoint -q "$BACKUP_MOUNT"; then
    echo "ERROR: $BACKUP_MOUNT is not a mountpoint" >&2
    exit 1
fi

mkdir -p "$BACKUP_ROOT"

# Persistent timers can catch up immediately after host boot. Wait for the
# guest network/SSH service before creating a generation or touching containers.
echo "Waiting for backup VM SSH readiness..."
REMOTE_READY=0

for attempt in $(seq 1 20); do
    if "${SSH[@]}" 'true' >/dev/null 2>&1; then
        REMOTE_READY=1
        break
    fi

    if [[ "$attempt" -lt 20 ]]; then
        sleep 10
    fi
done

if [[ "$REMOTE_READY" -ne 1 ]]; then
    echo "ERROR: backup VM did not become SSH-ready within the readiness window" >&2
    exit 1
fi

TMP="$BACKUP_ROOT/.incomplete-$STAMP"
FINAL="$BACKUP_ROOT/$STAMP"
mkdir -p "$TMP/volumes"

# Record enough source metadata to make the generation auditable.
{
    echo "Backup timestamp: $STAMP"
    echo "Source host: $("${SSH[@]}" hostname)"
    echo
    echo "=== OS ==="
    "${SSH[@]}" "grep PRETTY_NAME /etc/os-release"
    echo
    echo "=== APPLICATION DATA MOUNT ==="
    "${SSH[@]}" "findmnt '$REMOTE_APPDATA_PARENT'"
    echo
    echo "=== RUNNING CONTAINERS BEFORE BACKUP ==="
    "${SSH[@]}" "docker ps --format '{{.Names}}\t{{.Image}}\t{{.Status}}'"
    echo
    echo "=== DOCKER VOLUMES ==="
    "${SSH[@]}" "docker volume ls"
} > "$TMP/manifest.txt"

RUNNING="$("${SSH[@]}" 'docker ps -q' | tr '\n' ' ' | xargs)"
STOPPED=0

restart_containers() {
    if [[ "$STOPPED" -eq 1 && -n "$RUNNING" ]]; then
        echo "Restarting application containers after interruption..."
        "${SSH[@]}" "docker start $RUNNING" >/dev/null || true
    fi
}

trap restart_containers EXIT INT TERM

if [[ -n "$RUNNING" ]]; then
    echo "Stopping application containers..."
    STOPPED=1
    "${SSH[@]}" "docker stop -t 60 $RUNNING" >/dev/null
fi

echo "Backing up Compose configuration..."
"${SSH[@]}" \
  "tar --numeric-owner --acls --xattrs --xattrs-include='*' \
       --one-file-system \
       -C '$REMOTE_COMPOSE_PARENT' -cf - '$REMOTE_COMPOSE_NAME'" \
  | zstd -T0 -3 -q -o "$TMP/compose.tar.zst"

echo "Backing up application data..."
"${SSH[@]}" \
  "tar --numeric-owner --acls --xattrs --xattrs-include='*' \
       --one-file-system \
       --exclude='$REMOTE_APPDATA_NAME/jellyfin/cache' \
       -C '$REMOTE_APPDATA_PARENT' -cf - '$REMOTE_APPDATA_NAME'" \
  | zstd -T0 -3 -q -o "$TMP/appdata.tar.zst"

echo "Backing up Docker volumes..."
mapfile -t VOLUMES < <("${SSH[@]}" 'docker volume ls -q')

for VOL in "${VOLUMES[@]}"; do
    [[ -n "$VOL" ]] || continue
    echo "  $VOL"

    "${SSH[@]}" \
      "docker run --rm --pull=never --network none \
       -v '$VOL:/volume:ro' \
       alpine:latest \
       tar -C /volume -cf - ." \
      | zstd -T0 -3 -q -o "$TMP/volumes/$VOL.tar.zst"
done

if [[ -n "$RUNNING" ]]; then
    echo "Restarting application containers..."
    "${SSH[@]}" "docker start $RUNNING" >/dev/null
fi

STOPPED=0
trap - EXIT INT TERM

echo "Generating checksums..."
(
    cd "$TMP"
    find . -type f ! -name SHA256SUMS -print0 \
      | sort -z \
      | xargs -0 sha256sum > SHA256SUMS
)

echo "Testing compressed archives..."
while IFS= read -r -d '' ARCHIVE; do
    zstd -q -t "$ARCHIVE"
done < <(find "$TMP" -type f -name '*.tar.zst' -print0)

echo "Verifying checksums..."
(
    cd "$TMP"
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
echo "Backup completed successfully:"
echo "$FINAL"
du -sh "$FINAL"
