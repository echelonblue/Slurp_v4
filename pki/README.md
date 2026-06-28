# Slurp PKI

Eigen certificaatinfrastructuur voor de Slurp-stack. Alle HTTPS-verbindingen naar de Caddy-webservers worden beveiligd met certificaten die zijn uitgegeven door een eigen Root CA en Issuing CA.

## Vereisten

- `openssl` (versie 1.1.1 of hoger)
- `python3` (voor het bijwerken van Caddyfiles bij deployment)
- Docker (voor deployment en containerbeheer)

## Mapstructuur

```
pki/
├── ca_gen.sh          # Stap 1 — Root CA en Issuing CA aanmaken
├── cert_gen.sh        # Stap 2 — Servercertificaten genereren
├── deploy_certs.sh    # Stap 3 — Certificaten uitrollen naar Caddy
├── revoke.sh          # Stap 4 — Certificaten intrekken (indien nodig)
└── out/               # Gegenereerd sleutel- en certificaatmateriaal (niet in git)
    ├── root-ca/
    │   ├── private/root-ca.key        *** bewaar offline ***
    │   ├── root-ca.crt                vertrouw dit op alle clients
    │   ├── root-ca.crl
    │   └── root-ca.cnf
    └── issuing-ca/
        ├── private/issuing-ca.key
        ├── issuing-ca.crt
        ├── issuing-ca.crl
        ├── chain.pem                  issuing CA + root CA
        ├── issuing-ca.cnf
        └── certs/                     door Caddy gebruikte servercerts
            ├── <service>.crt
            └── <service>-chain.pem
```

---

## Stap 1 — Root CA en Issuing CA aanmaken

```bash
cd pki
./ca_gen.sh
```

Genereert:

| Onderdeel     | Sleutel  | Handtekening | Geldigheid |
|---------------|----------|--------------|------------|
| Root CA       | P-521    | ECDSA/SHA-384 | 20 jaar   |
| Issuing CA    | P-384    | ECDSA/SHA-384 | 10 jaar   |
| Root CA CRL   | —        | ECDSA/SHA-384 | 90 dagen  |
| Issuing CA CRL| —        | ECDSA/SHA-384 | 90 dagen  |

> **Beveiligingsadvies:** Verplaats `out/root-ca/private/root-ca.key` na aanmaak naar offline opslag (USB, hardware key). De Root CA wordt alleen gebruikt om een nieuwe Issuing CA te ondertekenen.

---

## Stap 2 — Servercertificaten genereren

```bash
./cert_gen.sh
```

Genereert voor elke dienst (`lidarr`, `radarr`, `sabnzbd`, `transmission`, `sonarr`, `overseerr`, `spotweb`, `jellyfin`, `bazarr`, `prowlarr`, `shelfarr`, `lingarr`):

| Bestand                   | Inhoud                                      |
|---------------------------|---------------------------------------------|
| `<service>.key`           | P-384 private key (`chmod 400`)             |
| `<service>.crt`           | Servercertificaat, 397 dagen, SAN inbegrepen |
| `<service>-chain.pem`     | Servercert + Issuing CA (voor Caddy)        |

Certificaten worden geplaatst in `out/certs/<service>/`.

> Vereist dat Stap 1 is uitgevoerd en `out/issuing-ca/` bestaat.

---

## Stap 3 — Certificaten uitrollen naar Caddy

```bash
./deploy_certs.sh
```

Het script:

1. Toont een overzicht van alle te deployen certificaten en hun verloopdatum
2. Controleert welke Caddy-containers actief zijn
3. Vraagt om bevestiging vóór elke handeling
4. Stopt actieve Caddy-containers
5. Kopieert `<service>-chain.pem` en `<service>.key` naar `config/config_caddy_<service>/data/`
6. Vervangt `local_certs` door `tls /data/<service>.crt /data/<service>.key` in elke Caddyfile
7. Herstart de Caddy-containers die door het script gestopt zijn

> Vereist dat Stap 2 is uitgevoerd.

---

## Stap 4 — Root CA vertrouwen op clients

Importeer `out/root-ca/root-ca.crt` eenmalig op elk apparaat dat de diensten bezoekt. Alleen het Root CA certificaat hoeft vertrouwd te worden — de Issuing CA wordt automatisch gevalideerd via de certificaatketen.

---

### macOS

**Via terminal (systeembreed, alle gebruikers):**

```bash
sudo security add-trusted-cert \
    -d -r trustRoot \
    -k /Library/Keychains/System.keychain \
    out/root-ca/root-ca.crt
```

**Via Sleutelhanger (alleen huidige gebruiker):**

```bash
security add-trusted-cert \
    -d -r trustRoot \
    -k ~/Library/Keychains/login.keychain-db \
    out/root-ca/root-ca.crt
```

**Verificatie:**

```bash
security find-certificate -c "Slurp Root CA" /Library/Keychains/System.keychain
```

**Verwijderen:**

```bash
sudo security delete-certificate \
    -c "Slurp Root CA" \
    /Library/Keychains/System.keychain
```

> Safari en Chrome gebruiken de macOS Sleutelhanger. Firefox heeft een eigen certificaatopslag — zie het Firefox-kopje hieronder.

---

### iOS / iPadOS

1. Stuur `root-ca.crt` naar het apparaat via AirDrop of e-mail
2. Open het bestand → **Toestaan** → het profiel wordt geïnstalleerd
3. Ga naar `Instellingen → Algemeen → VPN en apparaatbeheer`
4. Tik op het Slurp Root CA profiel → **Installeer**
5. Activeer vertrouwen via `Instellingen → Info → Certificaatvertrouwensinstellingen`
6. Zet de schakelaar bij **Slurp Root CA** op aan

---

### Windows

**Via GUI:**

1. Dubbelklik op `root-ca.crt`
2. Klik op **Certificaat installeren**
3. Kies **Lokale computer** → Volgende
4. Kies **Certificaten in het volgende archief opslaan** → Bladeren
5. Selecteer **Vertrouwde basiscertificeringsinstanties** → OK → Volgende → Voltooien

**Via PowerShell (als Administrator):**

```powershell
Import-Certificate `
    -FilePath "root-ca.crt" `
    -CertStoreLocation Cert:\LocalMachine\Root
```

**Verificatie:**

```powershell
Get-ChildItem Cert:\LocalMachine\Root | Where-Object { $_.Subject -like "*Slurp*" }
```

**Verwijderen:**

```powershell
Get-ChildItem Cert:\LocalMachine\Root |
    Where-Object { $_.Subject -like "*Slurp Root CA*" } |
    Remove-Item
```

> Chrome en Edge gebruiken de Windows certificaatopslag. Firefox heeft een eigen opslag — zie het Firefox-kopje hieronder.

---

### Linux

**Debian / Ubuntu / Linux Mint:**

```bash
sudo cp out/root-ca/root-ca.crt /usr/local/share/ca-certificates/slurp-root-ca.crt
sudo update-ca-certificates
```

**RHEL / Fedora / CentOS / Rocky Linux:**

```bash
sudo cp out/root-ca/root-ca.crt /etc/pki/ca-trust/source/anchors/slurp-root-ca.crt
sudo update-ca-trust extract
```

**Arch Linux:**

```bash
sudo cp out/root-ca/root-ca.crt /etc/ca-certificates/trust-source/anchors/slurp-root-ca.crt
sudo update-ca-trust
```

**Verificatie (alle distributies):**

```bash
openssl verify -CAfile /etc/ssl/certs/ca-certificates.crt out/issuing-ca/issuing-ca.crt
```

**Verwijderen:**

```bash
# Debian/Ubuntu
sudo rm /usr/local/share/ca-certificates/slurp-root-ca.crt
sudo update-ca-certificates --fresh

# RHEL/Fedora
sudo rm /etc/pki/ca-trust/source/anchors/slurp-root-ca.crt
sudo update-ca-trust extract
```

> De systeemopslag wordt gebruikt door `curl`, `wget` en de meeste CLI-tools. Chrome op Linux gebruikt de systeemopslag. Firefox heeft een eigen opslag — zie hieronder.

---

### Firefox (alle platformen)

Firefox gebruikt een eigen certificaatopslag, onafhankelijk van het besturingssysteem.

**Via de interface:**

1. Open `about:preferences#privacy`
2. Scroll naar beneden → **Certificaten weergeven**
3. Tabblad **Certificeringsinstanties** → **Importeren**
4. Selecteer `root-ca.crt`
5. Vink aan: **Deze CA vertrouwen voor het identificeren van websites** → OK

**Via beleid (organisatiebrede uitrol, alle platformen):**

Maak `/etc/firefox/policies/policies.json` aan (Linux) of het equivalent voor Windows/macOS:

```json
{
  "policies": {
    "Certificates": {
      "Install": [
        "/pad/naar/root-ca.crt"
      ]
    }
  }
}
```

---

## CRL's vernieuwen (elke 90 dagen)

CRL's verlopen na 90 dagen. Vernieuw ze vóór de vervaldatum:

```bash
# Root CA CRL
openssl ca -gencrl \
    -config out/root-ca/root-ca.cnf \
    -out out/root-ca/root-ca.crl

# Issuing CA CRL
openssl ca -gencrl \
    -config out/issuing-ca/issuing-ca.cnf \
    -out out/issuing-ca/issuing-ca.crl
```

---

## Certificaat intrekken

```bash
./revoke.sh
```

Het script toont alle uitstaande servercertificaten, vraagt om een intrekkingsreden (RFC 5280) en bevestiging, trekt het certificaat in en genereert beide CRL's opnieuw.

**Intrekkingsredenen:**

| Reden                  | Wanneer                                          |
|------------------------|--------------------------------------------------|
| `keyCompromise`        | Private key gelekt of gestolen                   |
| `superseded`           | Vervangen door nieuw certificaat                 |
| `cessationOfOperation` | Dienst buiten gebruik gesteld                    |
| `affiliationChanged`   | Wijziging in organisatie of domein               |
| `certificateHold`      | Tijdelijke opschorting (omkeerbaar)              |
| `unspecified`          | Overige redenen                                  |

Na intrekking: genereer nieuwe certificaten met `cert_gen.sh` en rol ze uit met `deploy_certs.sh`.

---

## Certificaten vernieuwen (na 397 dagen)

Servercertificaten verlopen na 397 dagen. Vernieuwen:

```bash
./cert_gen.sh        # nieuwe certificaten genereren
./deploy_certs.sh    # uitrollen naar Caddy
```

De Issuing CA en Root CA hoeven hierbij niet opnieuw aangemaakt te worden.
