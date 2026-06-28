#!/usr/bin/env bash
set -euo pipefail

PKI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$PKI_DIR/.." && pwd)"
CERTS_DIR="$PKI_DIR/out/certs"

# Container = caddy_<service>, project = <service> — geen associatieve arrays nodig
SERVICES=(
    bazarr
    jellyfin
    lidarr
    lingarr
    overseerr
    prowlarr
    radarr
    sabnzbd
    shelfarr
    sonarr
    spotweb
    transmission
)

status() {
    echo "[$(date +"%H:%M:%S")] $*"
}

# ── Voorwaarden controleren ───────────────────────────────────────────────────
if [ ! -d "$CERTS_DIR" ]; then
    echo "FOUT: $CERTS_DIR niet gevonden. Voer eerst cert_gen.sh uit."
    exit 1
fi

# ── Controleer welke services een cert hebben ─────────────────────────────────
AVAILABLE=()
for SERVICE in "${SERVICES[@]}"; do
    if [ -f "$CERTS_DIR/$SERVICE/${SERVICE}.key" ] && \
       [ -f "$CERTS_DIR/$SERVICE/${SERVICE}-chain.pem" ]; then
        AVAILABLE+=("$SERVICE")
    fi
done

if [ ${#AVAILABLE[@]} -eq 0 ]; then
    echo "FOUT: Geen server certificaten gevonden in $CERTS_DIR"
    echo "Voer eerst cert_gen.sh uit."
    exit 1
fi

# ── Controleer draaiende Caddy containers ─────────────────────────────────────
RUNNING=()
for SERVICE in "${AVAILABLE[@]}"; do
    CONTAINER="caddy_${SERVICE}"
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER}$"; then
        RUNNING+=("$CONTAINER")
    fi
done

# ── Samenvatting tonen ────────────────────────────────────────────────────────
echo ""
echo "=== Certificaatdeployment ==="
echo ""
echo "Certificaten beschikbaar voor ${#AVAILABLE[@]} services:"
for SERVICE in "${AVAILABLE[@]}"; do
    EXPIRY=$(openssl x509 -noout -enddate \
        -in "$CERTS_DIR/$SERVICE/${SERVICE}-chain.pem" 2>/dev/null \
        | sed 's/notAfter=//')
    printf "  %-14s  verloopt: %s\n" "$SERVICE" "$EXPIRY"
done

echo ""
if [ ${#RUNNING[@]} -gt 0 ]; then
    echo "Draaiende Caddy containers die gestopt worden:"
    for C in "${RUNNING[@]}"; do
        echo "  - $C"
    done
else
    echo "Geen Caddy containers actief."
fi

echo ""
echo "Acties:"
echo "  1. Caddy containers stoppen (indien actief)"
echo "  2. Certificaat en sleutel kopiëren naar config/config_caddy_<service>/data/"
echo "  3. Caddyfiles bijwerken: local_certs vervangen door tls /data/<service>.crt"
echo "  4. Gestopte containers herstarten"
echo ""
read -rp "Typ 'ja' om te bevestigen: " CONFIRM
[ "$CONFIRM" = "ja" ] || { echo "Afgebroken."; exit 0; }

echo ""
status "=== Deployment gestart ==="

# ── Caddy containers stoppen ──────────────────────────────────────────────────
if [ ${#RUNNING[@]} -gt 0 ]; then
    status "Caddy containers stoppen..."
    for SERVICE in "${AVAILABLE[@]}"; do
        CONTAINER="caddy_${SERVICE}"
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER}$"; then
            docker compose \
                -p "$SERVICE" \
                --project-directory "$PROJECT_DIR" \
                -f "$PROJECT_DIR/compose/docker-compose.${SERVICE}.yml" \
                stop caddy 2>/dev/null
            status "  gestopt: $CONTAINER"
        fi
    done
fi

# ── Certificaten uitrollen ────────────────────────────────────────────────────
for SERVICE in "${AVAILABLE[@]}"; do
    DEST_DIR="$PROJECT_DIR/config/config_caddy_${SERVICE}/data"
    CADDYFILE="$PROJECT_DIR/caddy/Caddyfile.${SERVICE}"
    FQDN="${SERVICE}.netbird.cloud"

    mkdir -p "$DEST_DIR"

    cp "$CERTS_DIR/$SERVICE/${SERVICE}-chain.pem" "$DEST_DIR/${SERVICE}.crt"
    cp "$CERTS_DIR/$SERVICE/${SERVICE}.key"        "$DEST_DIR/${SERVICE}.key"
    chmod 644 "$DEST_DIR/${SERVICE}.crt"
    chmod 600 "$DEST_DIR/${SERVICE}.key"

    # Caddyfile bijwerken via Python3 (werkt op alle platformen)
    python3 - "$CADDYFILE" "$FQDN" "$SERVICE" << 'PYEOF'
import sys, re

caddyfile, fqdn, service = sys.argv[1], sys.argv[2], sys.argv[3]
content = open(caddyfile).read()

content = re.sub(r'\n    local_certs\n', '\n', content)

tls_line = f'    tls /data/{service}.crt /data/{service}.key'
if tls_line not in content:
    content = re.sub(
        f'({re.escape(fqdn)}' + r' \{)',
        r'\1\n' + tls_line,
        content
    )

open(caddyfile, 'w').write(content)
PYEOF

    status "  $SERVICE  →  $DEST_DIR/"
done

# ── Caddy containers herstarten ───────────────────────────────────────────────
if [ ${#RUNNING[@]} -gt 0 ]; then
    status "Gestopte Caddy containers herstarten..."
    for SERVICE in "${AVAILABLE[@]}"; do
        CONTAINER="caddy_${SERVICE}"
        if printf '%s\n' "${RUNNING[@]}" | grep -q "^${CONTAINER}$"; then
            docker compose \
                -p "$SERVICE" \
                --project-directory "$PROJECT_DIR" \
                -f "$PROJECT_DIR/compose/docker-compose.${SERVICE}.yml" \
                start caddy 2>/dev/null
            status "  gestart: $CONTAINER"
        fi
    done
fi

# ── Verificatie ───────────────────────────────────────────────────────────────
echo ""
status "=== Deployment voltooid ==="
echo ""
echo "Gedeployde bestanden:"
for SERVICE in "${AVAILABLE[@]}"; do
    DEST_DIR="$PROJECT_DIR/config/config_caddy_${SERVICE}/data"
    printf "  %-14s  %s\n" "$SERVICE" "$DEST_DIR/"
done
echo ""
echo "Caddyfiles bijgewerkt in caddy/Caddyfile.*"
