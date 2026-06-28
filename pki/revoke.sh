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

# ── Hulpfunctie: private key extraheren uit PFX ───────────────────────────────
pfx_extract_key() {
    local PFX="$1" PASS="$2" OUT="$3"
    openssl pkcs12 -in "$PFX" -nocerts -nodes \
        -passin "pass:$PASS" -out "$OUT" -legacy 2>/dev/null && return 0
    openssl pkcs12 -in "$PFX" -nocerts -nodes \
        -passin "pass:$PASS" -out "$OUT" 2>/dev/null && return 0
    return 1
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
if [ ! -f "$ISSUING_CONF" ] || \
   [ ! -f "$ISSUING_DIR/private/issuing-ca.pfx" ] || \
   [ ! -f "$ROOT_DIR/private/root-ca.pfx" ]; then
    echo "FOUT: CA PFX bestanden niet gevonden. Voer eerst ca_gen.sh uit."
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

# ── Wachtwoorden vragen ───────────────────────────────────────────────────────
echo ""
echo "CA private keys vereist voor intrekking en CRL-vernieuwing."
read -rsp "Wachtwoord Issuing CA PFX: " ISSUING_PFX_PASS
echo ""
read -rsp "Wachtwoord Root CA PFX:    " ROOT_PFX_PASS
echo ""

# ── Beveiligde temp-directory aanmaken ────────────────────────────────────────
SECURE_TMP="$(mktemp -d)"
chmod 700 "$SECURE_TMP"
TEMP_ISSUING_KEY="$SECURE_TMP/issuing-ca.key"
TEMP_ROOT_KEY="$SECURE_TMP/root-ca.key"

cleanup_secure() {
    for f in "$SECURE_TMP"/*; do
        [ -f "$f" ] && openssl rand -out "$f" 128 2>/dev/null || true
    done
    rm -rf "$SECURE_TMP"
}
trap cleanup_secure EXIT

# ── Private keys extraheren uit PFX ──────────────────────────────────────────
if ! pfx_extract_key \
        "$ISSUING_DIR/private/issuing-ca.pfx" \
        "$ISSUING_PFX_PASS" \
        "$TEMP_ISSUING_KEY"; then
    echo "FOUT: Kon Issuing CA private key niet extraheren."
    echo "      Controleer het wachtwoord en probeer opnieuw."
    exit 1
fi
unset ISSUING_PFX_PASS
chmod 400 "$TEMP_ISSUING_KEY"

if ! pfx_extract_key \
        "$ROOT_DIR/private/root-ca.pfx" \
        "$ROOT_PFX_PASS" \
        "$TEMP_ROOT_KEY"; then
    echo "FOUT: Kon Root CA private key niet extraheren."
    echo "      Controleer het wachtwoord en probeer opnieuw."
    exit 1
fi
unset ROOT_PFX_PASS
chmod 400 "$TEMP_ROOT_KEY"

if [ ! -s "$TEMP_ISSUING_KEY" ] || [ ! -s "$TEMP_ROOT_KEY" ]; then
    echo "FOUT: Een of meer geëxtraheerde keys zijn leeg."
    exit 1
fi

status "CA private keys geladen uit PFX."

echo ""
status "=== Certificaat intrekken ==="

# ── Intrekken ─────────────────────────────────────────────────────────────────
status "Certificaat $SELECTED_NAME intrekken (reden: $REASON)..."
openssl ca \
    -config "$ISSUING_CONF" \
    -keyfile "$TEMP_ISSUING_KEY" \
    -revoke "$SELECTED_CRT" \
    -crl_reason "$REASON" \
    2>/dev/null

# ── CRL's opnieuw genereren ───────────────────────────────────────────────────
status "Issuing CA CRL bijwerken..."
openssl ca -gencrl \
    -config "$ISSUING_CONF" \
    -keyfile "$TEMP_ISSUING_KEY" \
    -out "$ISSUING_DIR/issuing-ca.crl" \
    2>/dev/null

status "Root CA CRL bijwerken..."
openssl ca -gencrl \
    -config "$ROOT_CONF" \
    -keyfile "$TEMP_ROOT_KEY" \
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
