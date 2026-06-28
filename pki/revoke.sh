#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$SCRIPT_DIR/out"
ISSUING_DIR="$OUT_DIR/issuing-ca"
ROOT_DIR="$OUT_DIR/root-ca"
CERTS_DIR="$OUT_DIR/certs"
ISSUING_CONF="$ISSUING_DIR/issuing-ca.cnf"
ROOT_CONF="$ROOT_DIR/root-ca.cnf"

# RFC 5280 intrekkingsredenen
REASONS=(
    "unspecified"
    "keyCompromise"
    "CACompromise"
    "affiliationChanged"
    "superseded"
    "cessationOfOperation"
    "certificateHold"
)

status() {
    echo "[$(date +"%H:%M:%S")] $*"
}

cert_info() {
    local CRT="$1"
    local SUBJECT EXPIRY SERIAL
    SUBJECT=$(openssl x509 -noout -subject -in "$CRT" 2>/dev/null | sed 's/subject=//')
    EXPIRY=$(openssl x509  -noout -enddate -in "$CRT" 2>/dev/null | sed 's/notAfter=//')
    SERIAL=$(openssl x509  -noout -serial  -in "$CRT" 2>/dev/null | sed 's/serial=//')
    echo "    Subject: $SUBJECT"
    echo "    Verloopt: $EXPIRY"
    echo "    Serienr:  $SERIAL"
}

# ── Voorwaarden controleren ───────────────────────────────────────────────────
if [ ! -f "$ISSUING_CONF" ]; then
    echo "FOUT: Issuing CA niet gevonden. Voer eerst ca_gen.sh uit."
    exit 1
fi

# ── Beschikbare certificaten verzamelen ───────────────────────────────────────
mapfile -t CERTS < <(find "$CERTS_DIR" -name "*.crt" 2>/dev/null | sort)

if [ ${#CERTS[@]} -eq 0 ]; then
    echo "Geen server certificaten gevonden in $CERTS_DIR"
    echo "Voer eerst cert_gen.sh uit."
    exit 1
fi

# ── Certificaatkeuze ──────────────────────────────────────────────────────────
echo ""
echo "Beschikbare certificaten:"
echo ""
for i in "${!CERTS[@]}"; do
    CRT="${CERTS[$i]}"
    NAME="$(basename "$(dirname "$CRT")")"
    printf "  [%2d] %s\n" "$((i+1))" "$NAME"
    cert_info "$CRT"
    echo ""
done

while true; do
    read -rp "Keuze (1-${#CERTS[@]}): " CHOICE
    if [[ "$CHOICE" =~ ^[0-9]+$ ]] && \
       [ "$CHOICE" -ge 1 ] && \
       [ "$CHOICE" -le "${#CERTS[@]}" ]; then
        break
    fi
    echo "Ongeldige keuze."
done

SELECTED_CRT="${CERTS[$((CHOICE-1))]}"
SELECTED_NAME="$(basename "$(dirname "$SELECTED_CRT")")"

# ── Intrekkingsreden kiezen ───────────────────────────────────────────────────
echo ""
echo "Intrekkingsreden:"
echo ""
for i in "${!REASONS[@]}"; do
    printf "  [%d] %s\n" "$((i+1))" "${REASONS[$i]}"
done
echo ""

while true; do
    read -rp "Keuze (1-${#REASONS[@]}): " REASON_CHOICE
    if [[ "$REASON_CHOICE" =~ ^[0-9]+$ ]] && \
       [ "$REASON_CHOICE" -ge 1 ] && \
       [ "$REASON_CHOICE" -le "${#REASONS[@]}" ]; then
        break
    fi
    echo "Ongeldige keuze."
done

REASON="${REASONS[$((REASON_CHOICE-1))]}"

# ── Bevestiging ───────────────────────────────────────────────────────────────
echo ""
echo "Certificaat intrekken:"
echo "  Service: $SELECTED_NAME"
cert_info "$SELECTED_CRT"
echo "  Reden:   $REASON"
echo ""
echo "  LET OP: intrekking is onomkeerbaar (tenzij certificateHold)."
echo ""
read -rp "Typ 'ja' om te bevestigen: " CONFIRM

if [ "$CONFIRM" != "ja" ]; then
    echo "Afgebroken."
    exit 0
fi

echo ""
status "=== Certificaat intrekken ==="

# ── Intrekken ─────────────────────────────────────────────────────────────────
status "Certificaat $SELECTED_NAME intrekken (reden: $REASON)..."
openssl ca \
    -config "$ISSUING_CONF" \
    -revoke "$SELECTED_CRT" \
    -crl_reason "$REASON" \
    2>/dev/null

# ── CRL's opnieuw genereren ───────────────────────────────────────────────────
status "Issuing CA CRL bijwerken..."
openssl ca -gencrl \
    -config "$ISSUING_CONF" \
    -out "$ISSUING_DIR/issuing-ca.crl" \
    2>/dev/null

status "Root CA CRL bijwerken..."
openssl ca -gencrl \
    -config "$ROOT_CONF" \
    -out "$ROOT_DIR/root-ca.crl" \
    2>/dev/null

# ── Verificatie ───────────────────────────────────────────────────────────────
echo ""
status "Ingetrokken certificaten in Issuing CA CRL:"
openssl crl -noout -text -in "$ISSUING_DIR/issuing-ca.crl" 2>/dev/null \
    | grep -A2 "Revoked Certificates\|Serial Number\|Revocation Date" \
    | grep -v "^--$" \
    | sed 's/^/    /'

echo ""
status "Certificaat $SELECTED_NAME succesvol ingetrokken."
status "Issuing CA CRL: $ISSUING_DIR/issuing-ca.crl"
status "Root CA CRL:    $ROOT_DIR/root-ca.crl"
echo ""
echo "Distribueer de bijgewerkte CRL naar alle vertrouwende systemen."
