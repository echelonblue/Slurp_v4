#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$SCRIPT_DIR/backups"

status() {
    echo "[$(date +"%H:%M:%S")] $*"
}

# Beschikbare backups ophalen
mapfile -t BACKUPS < <(ls -1t "$BACKUP_DIR"/*.tar.bz2 2>/dev/null)

if [ ${#BACKUPS[@]} -eq 0 ]; then
    echo "Geen backups gevonden in $BACKUP_DIR"
    exit 1
fi

# Keuzemenu
echo ""
echo "Beschikbare backups:"
echo ""
for i in "${!BACKUPS[@]}"; do
    FILE="${BACKUPS[$i]}"
    SIZE="$(du -sh "$FILE" | cut -f1)"
    DATE="$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$FILE" 2>/dev/null || stat -c "%y" "$FILE" 2>/dev/null | cut -d'.' -f1)"
    printf "  [%d] %-45s  %s  (%s)\n" "$((i+1))" "$(basename "$FILE")" "$DATE" "$SIZE"
done
echo ""

while true; do
    read -rp "Keuze (1-${#BACKUPS[@]}): " CHOICE
    if [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le "${#BACKUPS[@]}" ]; then
        break
    fi
    echo "Ongeldige keuze. Voer een nummer in tussen 1 en ${#BACKUPS[@]}."
done

SELECTED="${BACKUPS[$((CHOICE-1))]}"

echo ""
echo "Geselecteerde backup: $(basename "$SELECTED")"
echo ""
echo "  LET OP: alle huidige data in config/ en caddy/ wordt overschreven."
echo ""
read -rp "Typ 'ja' om te bevestigen: " CONFIRM

if [ "$CONFIRM" != "ja" ]; then
    echo "Restore geannuleerd."
    exit 0
fi

cleanup() {
    status "Containers herstarten..."
    "$SCRIPT_DIR/run_slurp.sh"
    status "Klaar."
}
trap cleanup EXIT

status "=== Slurp restore gestart ==="
status "Backup: $(basename "$SELECTED")"

status "Containers stoppen..."
"$SCRIPT_DIR/stop_slurp.sh"

status "Data terugzetten..."
tar -C "$SCRIPT_DIR" -xjf "$SELECTED"

status "Restore geslaagd."
