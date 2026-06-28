#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$SCRIPT_DIR/out"
ISSUING_DIR="$OUT_DIR/issuing-ca"
CERTS_DIR="$OUT_DIR/certs"
ISSUING_CONF="$ISSUING_DIR/issuing-ca.cnf"

CURVE="P-384"
HASH="sha384"
DAYS=397        # maximale browservertrouwing voor server certs
DOMAIN="netbird.cloud"

COUNTRY="NL"
ORG="Slurp"

# ── Services ──────────────────────────────────────────────────────────────────
SERVICES=(
    lidarr
    radarr
    sabnzbd
    transmission
    sonarr
    overseerr
    spotweb
    jellyfin
    bazarr
    prowlarr
    shelfarr
    lingarr
)

status() {
    echo "[$(date +"%H:%M:%S")] $*"
}

# ── Voorwaarden controleren ───────────────────────────────────────────────────
if [ ! -f "$ISSUING_DIR/issuing-ca.crt" ] || [ ! -f "$ISSUING_DIR/private/issuing-ca.key" ]; then
    echo "FOUT: Issuing CA niet gevonden. Voer eerst ca_gen.sh uit."
    exit 1
fi

status "=== Server certificaten aanmaken ==="
status "Issuing CA: $ISSUING_DIR/issuing-ca.crt"
status "Domein:     *.${DOMAIN}"
status "Curve:      ${CURVE}  |  Hash: ${HASH}  |  Geldigheid: ${DAYS} dagen"
echo ""

mkdir -p "$CERTS_DIR"

for SERVICE in "${SERVICES[@]}"; do
    FQDN="${SERVICE}.${DOMAIN}"
    CERT_DIR="$CERTS_DIR/$SERVICE"
    KEY="$CERT_DIR/${SERVICE}.key"
    CSR="$CERT_DIR/${SERVICE}.csr"
    CRT="$CERT_DIR/${SERVICE}.crt"
    CHAIN="$CERT_DIR/${SERVICE}-chain.pem"
    CONF="$CERT_DIR/${SERVICE}.cnf"

    mkdir -p "$CERT_DIR"
    chmod 700 "$CERT_DIR"

    # Per-service OpenSSL config met SAN
    cat > "$CONF" << EOF
[req]
default_md          = $HASH
distinguished_name  = req_dn
prompt              = no
string_mask         = utf8only
req_extensions      = req_ext

[req_dn]
C  = $COUNTRY
O  = $ORG
CN = $FQDN

[req_ext]
subjectAltName = DNS:$FQDN

[server_cert_ext]
subjectKeyIdentifier    = hash
authorityKeyIdentifier  = keyid:always
basicConstraints        = critical, CA:false
keyUsage                = critical, digitalSignature
extendedKeyUsage        = serverAuth
subjectAltName          = DNS:$FQDN
EOF

    # Private key
    openssl genpkey \
        -algorithm EC \
        -pkeyopt "ec_paramgen_curve:${CURVE}" \
        -out "$KEY" 2>/dev/null
    chmod 400 "$KEY"

    # CSR
    openssl req -new \
        -config "$CONF" \
        -key "$KEY" \
        -out "$CSR" 2>/dev/null

    # Ondertekenen met Issuing CA
    openssl ca -batch \
        -config "$ISSUING_CONF" \
        -extensions server_cert_ext \
        -extfile "$CONF" \
        -days "$DAYS" \
        -in "$CSR" \
        -out "$CRT" \
        -notext 2>/dev/null

    # Keten: server cert + issuing CA
    cat "$CRT" "$ISSUING_DIR/issuing-ca.crt" > "$CHAIN"

    # Verifieer
    FINGERPRINT=$(openssl x509 -noout -fingerprint -sha256 -in "$CRT" | cut -d= -f2)
    status "${FQDN}  →  ${FINGERPRINT}"
done

echo ""
status "=== Alle certificaten aangemaakt ==="
echo ""
echo "Bestanden per service in out/certs/<service>/:"
echo "  <service>.key          Private key (P-384, chmod 400)"
echo "  <service>.crt          Servercertificaat (${DAYS} dagen)"
echo "  <service>-chain.pem    Keten: server cert + issuing CA"
echo "  <service>.cnf          OpenSSL config"
echo ""
echo "Root CA certificaat om te vertrouwen op clients:"
echo "  ${OUT_DIR}/root-ca/root-ca.crt"
echo ""
echo "Verloopdatum certificaten:"
openssl x509 -noout -enddate -in "$CERTS_DIR/${SERVICES[0]}/${SERVICES[0]}.crt"
