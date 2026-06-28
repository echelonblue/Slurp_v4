#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP="$(date +"%Y-%m-%d_%H-%M-%S")"
BACKUP_DIR="$SCRIPT_DIR/backups"
BACKUP_FILE="$BACKUP_DIR/slurp_backup_$TIMESTAMP.tar.bz2"

status() {
    echo "[$(date +"%H:%M:%S")] $*"
}

mkdir -p "$BACKUP_DIR"

cleanup() {
    status "Containers herstarten..."
    "$SCRIPT_DIR/run_slurp.sh"
    status "Klaar."
}
trap cleanup EXIT

status "=== Slurp backup gestart ==="

status "Te backuppen mappen:"
du -sh "$SCRIPT_DIR/config" "$SCRIPT_DIR/caddy" "$SCRIPT_DIR/compose" 2>/dev/null \
    | awk '{printf "    %-8s %s\n", $1, $2}'

EXISTING_BACKUPS=$(ls -1 "$BACKUP_DIR"/*.tar.bz2 2>/dev/null | wc -l | tr -d ' ')
status "Bestaande backups in $BACKUP_DIR: $EXISTING_BACKUPS"

status "Containers stoppen..."
"$SCRIPT_DIR/stop_slurp.sh"

status "Backup aanmaken: $(basename "$BACKUP_FILE")"
tar -C "$SCRIPT_DIR" -cjf "$BACKUP_FILE" \
    --exclude="./backups" \
    --exclude="./downloads" \
    --exclude="./movies" \
    --exclude="./music" \
    --exclude="./tv" \
    --exclude="./tmp" \
    .

SIZE="$(du -sh "$BACKUP_FILE" | cut -f1)"
status "Backup geslaagd: $BACKUP_FILE ($SIZE)"
