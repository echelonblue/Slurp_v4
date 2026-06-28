#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$SCRIPT_DIR/out"

# ── Algoritmen ────────────────────────────────────────────────────────────────
ROOT_CURVE="P-521"      # sterkste ECC curve voor offline root CA
ISSUING_CURVE="P-384"   # P-384 voor online issuing CA
HASH="sha384"           # handtekening-hash

# ── Geldigheidsduren (dagen) ──────────────────────────────────────────────────
ROOT_DAYS=7300          # 20 jaar
ISSUING_DAYS=3650       # 10 jaar
CRL_DAYS=90             # CRL-geldigheid

# ── Distinguished Name ────────────────────────────────────────────────────────
COUNTRY="NL"
ORG="Slurp"
ROOT_CN="Slurp Root CA"
ISSUING_CN="Slurp Issuing CA"

# ── Paden ─────────────────────────────────────────────────────────────────────
ROOT_DIR="$OUT_DIR/root-ca"
ISSUING_DIR="$OUT_DIR/issuing-ca"
ROOT_CONF="$ROOT_DIR/root-ca.cnf"
ISSUING_CONF="$ISSUING_DIR/issuing-ca.cnf"

status() {
    echo "[$(date +"%H:%M:%S")] $*"
}

# ── Bestaande output controleren ──────────────────────────────────────────────
if [ -d "$OUT_DIR" ]; then
    echo "WAARSCHUWING: $OUT_DIR bestaat al en bevat sleutelmateriaal."
    read -rp "Volledig overschrijven? Typ 'ja' om te bevestigen: " CONFIRM
    [ "$CONFIRM" = "ja" ] || { echo "Afgebroken."; exit 0; }
    rm -rf "$OUT_DIR"
fi

# ── Mapstructuur aanmaken ─────────────────────────────────────────────────────
mkdir -p "$ROOT_DIR/private" "$ROOT_DIR/db"
mkdir -p "$ISSUING_DIR/private" "$ISSUING_DIR/db" "$ISSUING_DIR/certs"
chmod 700 "$ROOT_DIR/private" "$ISSUING_DIR/private"

# ── CA-databases initialiseren ────────────────────────────────────────────────
touch "$ROOT_DIR/db/index.txt" "$ISSUING_DIR/db/index.txt"
printf '1000\n' > "$ROOT_DIR/db/serial"
printf '1000\n' > "$ROOT_DIR/db/crlnumber"
printf '1000\n' > "$ISSUING_DIR/db/serial"
printf '1000\n' > "$ISSUING_DIR/db/crlnumber"

# ── Root CA OpenSSL configuratie ──────────────────────────────────────────────
cat > "$ROOT_CONF" << EOF
[ca]
default_ca = CA_default

[CA_default]
database          = $ROOT_DIR/db/index.txt
serial            = $ROOT_DIR/db/serial
crlnumber         = $ROOT_DIR/db/crlnumber
certificate       = $ROOT_DIR/root-ca.crt
private_key       = $ROOT_DIR/private/root-ca.key
new_certs_dir     = $ROOT_DIR/db
default_md        = $HASH
default_days      = $ISSUING_DAYS
default_crl_days  = $CRL_DAYS
unique_subject    = no
preserve          = no
policy            = policy_strict
copy_extensions   = copy

[policy_strict]
countryName             = match
organizationName        = match
commonName              = supplied

[req]
default_md          = $HASH
distinguished_name  = req_dn
prompt              = no
string_mask         = utf8only

[req_dn]
C  = $COUNTRY
O  = $ORG
CN = $ROOT_CN

[root_ca_ext]
subjectKeyIdentifier    = hash
authorityKeyIdentifier  = keyid:always
basicConstraints        = critical, CA:true, pathlen:1
keyUsage                = critical, keyCertSign, cRLSign

[issuing_ca_ext]
subjectKeyIdentifier    = hash
authorityKeyIdentifier  = keyid:always
basicConstraints        = critical, CA:true, pathlen:0
keyUsage                = critical, keyCertSign, cRLSign

[crl_ext]
authorityKeyIdentifier  = keyid:always
EOF

# ── Issuing CA OpenSSL configuratie ──────────────────────────────────────────
cat > "$ISSUING_CONF" << EOF
[ca]
default_ca = CA_default

[CA_default]
database          = $ISSUING_DIR/db/index.txt
serial            = $ISSUING_DIR/db/serial
crlnumber         = $ISSUING_DIR/db/crlnumber
certificate       = $ISSUING_DIR/issuing-ca.crt
private_key       = $ISSUING_DIR/private/issuing-ca.key
new_certs_dir     = $ISSUING_DIR/certs
default_md        = $HASH
default_days      = 397
default_crl_days  = $CRL_DAYS
unique_subject    = no
preserve          = no
policy            = policy_loose
copy_extensions   = copy

[policy_loose]
countryName             = optional
organizationName        = optional
commonName              = supplied

[req]
default_md          = $HASH
distinguished_name  = req_dn
prompt              = no
string_mask         = utf8only

[req_dn]
C  = $COUNTRY
O  = $ORG
CN = $ISSUING_CN

[server_cert_ext]
subjectKeyIdentifier    = hash
authorityKeyIdentifier  = keyid:always
basicConstraints        = critical, CA:false
keyUsage                = critical, digitalSignature
extendedKeyUsage        = serverAuth, clientAuth

[crl_ext]
authorityKeyIdentifier  = keyid:always
EOF

status "=== Slurp PKI aanmaken ==="

# ── 1. Root CA private key (P-521) ────────────────────────────────────────────
status "Root CA private key aanmaken (${ROOT_CURVE})..."
openssl genpkey \
    -algorithm EC \
    -pkeyopt "ec_paramgen_curve:${ROOT_CURVE}" \
    -out "$ROOT_DIR/private/root-ca.key"
chmod 400 "$ROOT_DIR/private/root-ca.key"

# ── 2. Root CA zelfondertekend certificaat ────────────────────────────────────
status "Root CA certificaat aanmaken (geldig ${ROOT_DAYS} dagen, ${HASH})..."
openssl req -new -x509 \
    -config "$ROOT_CONF" \
    -extensions root_ca_ext \
    -days "$ROOT_DAYS" \
    -key "$ROOT_DIR/private/root-ca.key" \
    -out "$ROOT_DIR/root-ca.crt"

# ── 3. Issuing CA private key (P-384) ────────────────────────────────────────
status "Issuing CA private key aanmaken (${ISSUING_CURVE})..."
openssl genpkey \
    -algorithm EC \
    -pkeyopt "ec_paramgen_curve:${ISSUING_CURVE}" \
    -out "$ISSUING_DIR/private/issuing-ca.key"
chmod 400 "$ISSUING_DIR/private/issuing-ca.key"

# ── 4. Issuing CA CSR ─────────────────────────────────────────────────────────
status "Issuing CA CSR aanmaken..."
openssl req -new \
    -config "$ISSUING_CONF" \
    -key "$ISSUING_DIR/private/issuing-ca.key" \
    -out "$ISSUING_DIR/issuing-ca.csr"

# ── 5. Issuing CA ondertekenen met Root CA ────────────────────────────────────
status "Issuing CA ondertekenen met Root CA..."
openssl ca -batch \
    -config "$ROOT_CONF" \
    -extensions issuing_ca_ext \
    -days "$ISSUING_DAYS" \
    -in "$ISSUING_DIR/issuing-ca.csr" \
    -out "$ISSUING_DIR/issuing-ca.crt" \
    -notext

# ── 6. Root CA CRL ────────────────────────────────────────────────────────────
status "Root CA CRL aanmaken (geldig ${CRL_DAYS} dagen)..."
openssl ca -gencrl \
    -config "$ROOT_CONF" \
    -out "$ROOT_DIR/root-ca.crl"

# ── 7. Issuing CA CRL ─────────────────────────────────────────────────────────
status "Issuing CA CRL aanmaken (geldig ${CRL_DAYS} dagen)..."
openssl ca -gencrl \
    -config "$ISSUING_CONF" \
    -out "$ISSUING_DIR/issuing-ca.crl"

# ── 8. Certificaatketen ───────────────────────────────────────────────────────
status "Certificaatketen aanmaken..."
cat "$ISSUING_DIR/issuing-ca.crt" "$ROOT_DIR/root-ca.crt" \
    > "$ISSUING_DIR/chain.pem"

# ── 9. PFX bestanden aanmaken met willekeurige wachtwoorden ──────────────────
status "Root CA private key verpakken in PFX (PKCS#12)..."
ROOT_PFX_PASS="$(openssl rand -hex 24)"
openssl pkcs12 -export \
    -in  "$ROOT_DIR/root-ca.crt" \
    -inkey "$ROOT_DIR/private/root-ca.key" \
    -out "$ROOT_DIR/private/root-ca.pfx" \
    -passout "pass:${ROOT_PFX_PASS}" \
    -name "$ROOT_CN" \
    -legacy 2>/dev/null
chmod 400 "$ROOT_DIR/private/root-ca.pfx"

status "Issuing CA private key verpakken in PFX (PKCS#12)..."
ISSUING_PFX_PASS="$(openssl rand -hex 24)"
openssl pkcs12 -export \
    -in  "$ISSUING_DIR/issuing-ca.crt" \
    -inkey "$ISSUING_DIR/private/issuing-ca.key" \
    -certfile "$ROOT_DIR/root-ca.crt" \
    -out "$ISSUING_DIR/private/issuing-ca.pfx" \
    -passout "pass:${ISSUING_PFX_PASS}" \
    -name "$ISSUING_CN" \
    -legacy 2>/dev/null
chmod 400 "$ISSUING_DIR/private/issuing-ca.pfx"

# ── Samenvatting ──────────────────────────────────────────────────────────────
echo ""
status "=== PKI gereed ==="
echo ""
echo "Root CA:"
openssl x509 -noout -subject -issuer -dates \
    -fingerprint -sha256 -in "$ROOT_DIR/root-ca.crt"
echo ""
echo "Issuing CA:"
openssl x509 -noout -subject -issuer -dates \
    -fingerprint -sha256 -in "$ISSUING_DIR/issuing-ca.crt"
echo ""
echo "Gegenereerde bestanden:"
echo "  out/root-ca/root-ca.crt               Root CA certificaat (vertrouw dit op clients)"
echo "  out/root-ca/private/root-ca.key        Root CA private key  (chmod 400)"
echo "  out/root-ca/private/root-ca.pfx        Root CA private key  (PKCS#12, wachtwoord zie onder)"
echo "  out/root-ca/root-ca.crl                Root CA CRL"
echo "  out/issuing-ca/issuing-ca.crt          Issuing CA certificaat"
echo "  out/issuing-ca/private/issuing-ca.key  Issuing CA private key  (chmod 400)"
echo "  out/issuing-ca/private/issuing-ca.pfx  Issuing CA private key  (PKCS#12, wachtwoord zie onder)"
echo "  out/issuing-ca/issuing-ca.crl          Issuing CA CRL"
echo "  out/issuing-ca/chain.pem               Keten: issuing-ca + root-ca"
echo ""
echo "┌─────────────────────────────────────────────────────────────────┐"
echo "│                  PFX WACHTWOORDEN — BEWAAR VEILIG               │"
echo "├─────────────────────────────────────────────────────────────────┤"
printf "│  Root CA    : %-51s │\n" "$ROOT_PFX_PASS"
printf "│  Issuing CA : %-51s │\n" "$ISSUING_PFX_PASS"
echo "└─────────────────────────────────────────────────────────────────┘"
echo ""
echo "Vernieuw de CRL's vóór dag ${CRL_DAYS} met:"
echo "  openssl ca -gencrl -config out/root-ca/root-ca.cnf -out out/root-ca/root-ca.crl"
echo "  openssl ca -gencrl -config out/issuing-ca/issuing-ca.cnf -out out/issuing-ca/issuing-ca.crl"
