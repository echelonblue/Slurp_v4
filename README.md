# Slurp — *arr stack met Netbird VPN-tunnels

Elke service draait in een eigen Docker Compose-stack en is individueel bereikbaar via HTTPS (poort 443) over een aparte Netbird-tunnel. Er is geen open poort nodig op de host of router.

---

## Services

| Service      | Functie                        | URL                                      |
|--------------|--------------------------------|------------------------------------------|
| Lidarr       | Muziekbeheer                   | https://lidarr.netbird.cloud             |
| Radarr       | Filmbeheer                     | https://radarr.netbird.cloud             |
| SABnzbd      | NZB-downloader                 | https://sabnzbd.netbird.cloud            |
| Transmission | BitTorrent-client (P2P VPN)    | https://transmission.netbird.cloud       |
| Sonarr       | Seriebeheer                    | https://sonarr.netbird.cloud             |
| Overseerr    | Verzoekenbeheer                | https://overseerr.netbird.cloud          |
| Spotweb      | Usenet-indexer                 | https://spotweb.netbird.cloud            |
| Jellyfin     | Mediaserver                    | https://jellyfin.netbird.cloud           |
| Bazarr       | Ondertitelbeheer               | https://bazarr.netbird.cloud             |
| Prowlarr     | Indexerbeheer                  | https://prowlarr.netbird.cloud           |
| Shelfarr     | Boekenbeheer                   | https://shelfarr.netbird.cloud           |
| Lingarr      | Ondertitelvertaling (AI)       | https://lingarr.netbird.cloud            |
| Watchtower   | Automatische updates           | —                                        |

> Hostnamen zijn gebaseerd op het Netbird-domein `netbird.cloud`. Pas de Caddyfiles aan als jouw account een ander domein gebruikt.

---

## Hoe het werkt

Elke service-stack bestaat uit containers die hetzelfde netwerk-namespace delen:

```
netbird_xxx   →  verbindt met Netbird VPN, krijgt een Netbird-IP (bijv. 100.x.x.x)
    ├── app   →  luistert op localhost:<poort>
    └── caddy →  termineert HTTPS op :443, proxyt naar de app via localhost
```

Spotweb heeft een extra container voor de database:

```
netbird_spotweb  →  Netbird VPN
    ├── db       →  MariaDB op localhost:3306
    ├── spotweb  →  Apache op localhost:80
    └── caddy    →  HTTPS op :443, proxyt naar localhost:80
```

Transmission gebruikt WireGuard als basis-namespace — al het verkeer gaat via ProtonVPN:

```
wireguard_transmission  →  wg0: ProtonVPN P2P-tunnel (default route voor alle containers)
    ├── netbird         →  Netbird VPN — verbindt via ProtonVPN, beheert wt0
    ├── transmission    →  BitTorrent-client; al het verkeer via wg0
    └── caddy           →  HTTPS op :443, bereikbaar via wt0 (Netbird-IP)
```

`AllowedIPs = 0.0.0.0/0` stuurt al het uitgaande verkeer door `wg0` — dit zorgt voor de kill-switch: als de VPN wegvalt, heeft Transmission geen internetverbinding meer.

Doordat alle containers het netwerk-namespace van de Netbird-container delen, is elke service alleen bereikbaar via het Netbird-IP. Er hoeven geen poorten op de host geopend te worden.

---

## Installatie

### Stap 1 — Vereisten

- Docker met de Compose-plugin
- Een Netbird-account — gratis op [app.netbird.io](https://app.netbird.io)
- Netbird-client op elk apparaat dat de services moet bereiken

### Stap 2 — `.env` invullen

Maak in het Netbird-dashboard voor **elke service een aparte setup key** aan via `Setup Keys → Create Setup Key`. Gebruik **Reusable** als je containers regelmatig opnieuw aanmaakt.

Open `.env` en vul de waarden in:

```env
NB_SETUP_KEY_LIDARR=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
NB_SETUP_KEY_RADARR=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
NB_SETUP_KEY_SABNZBD=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
NB_SETUP_KEY_TRANSMISSION=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
NB_SETUP_KEY_SONARR=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
NB_SETUP_KEY_OVERSEERR=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
NB_SETUP_KEY_SPOTWEB=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
NB_SETUP_KEY_JELLYFIN=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
NB_SETUP_KEY_BAZARR=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
NB_SETUP_KEY_PROWLARR=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
NB_SETUP_KEY_SHELFARR=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
NB_SETUP_KEY_LINGARR=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

OLLAMA_HOST=1.2.3.4

SPOTWEB_DB_ROOT_PASSWORD=kies-een-sterk-wachtwoord
SPOTWEB_DB_PASSWORD=kies-een-sterk-wachtwoord

TRANSMISSION_USER=xor
TRANSMISSION_PASS=kies-een-sterk-wachtwoord
```

### Stap 3 — Mappen aanmaken

```bash
mkdir -p config/config_lidarr config/config_radarr/data config/config_sabznbd \
    config/config_transmission config/config_wireguard_transmission/wg_confs \
    config/config_sonarr/data config/config_overseerr config/config_spotweb \
    config/config_spotweb_db config/config_jellyfin config/config_jellyfin_cache \
    config/config_bazarr config/config_prowlarr config/config_shelfarr config/config_lingarr

mkdir -p config/config_netbird_{lidarr,radarr,sabnzbd,transmission,sonarr,overseerr,spotweb,jellyfin,bazarr,prowlarr,shelfarr,lingarr}/{etc,var}
mkdir -p config/config_caddy_{lidarr,radarr,sabnzbd,transmission,sonarr,overseerr,spotweb,jellyfin,bazarr,prowlarr,shelfarr,lingarr}/{data,config}
mkdir -p tmp/tmp_transmission tmp/tmp_sabnzbd tmp/tmp_sabnzbd_watch
mkdir -p downloads/complete downloads/incomplete music movies tv
```

### Stap 4 — PKI opzetten

De Caddy-webservers gebruiken certificaten van een eigen Root CA en Issuing CA. Genereer de PKI eenmalig vóór de eerste start:

```bash
cd pki
./ca_gen.sh       # Root CA + Issuing CA aanmaken — bewaar de getoonde PFX-wachtwoorden!
./cert_gen.sh     # Servercertificaten genereren voor alle 12 diensten
./deploy_certs.sh # Certificaten uitrollen naar de Caddy-containers
cd ..
```

Zie [`pki/README.md`](pki/README.md) voor een volledige beschrijving van de PKI-structuur, certificaatbeheer en de stappen om de Root CA op clients te vertrouwen.

### Stap 5 — Netbird ACL instellen

Netbird hanteert **default deny** — peers kunnen elkaar niet bereiken tenzij een policy dat toestaat. Stel de zero trust firewall in vóór de eerste start.

De volledige configuratie met groepen en gerichte policies staat beschreven in [`SETUP.md → Netbird Zero Trust firewall`](SETUP.md).

### Stap 6 — Starten

```bash
./run_slurp.sh
```

### Stap 7 — Root CA vertrouwen op clients

Importeer het Root CA-certificaat eenmalig op elk apparaat dat de services bezoekt. Op macOS:

```bash
sudo security add-trusted-cert \
    -d -r trustRoot \
    -k /Library/Keychains/System.keychain \
    pki/out/root-ca/root-ca.crt
```

Sluit de browser daarna volledig af en open hem opnieuw. Zie [`pki/README.md → Stap 4`](pki/README.md) voor instructies voor Windows, Linux, iOS en Firefox.

### Stap 8 — Eenmalige setup per service

Na de eerste start moet elke service minimaal worden geconfigureerd: download client koppelen, indexers toevoegen, mediamappen instellen. Zie [`SETUP.md`](SETUP.md) voor een overzicht per dienst.

---

## Gebruik

### Starten en stoppen

```bash
./run_slurp.sh    # alle services starten
./stop_slurp.sh   # alle services stoppen
```

### Losse service beheren

```bash
docker compose -p sonarr --project-directory . -f compose/docker-compose.sonarr.yml up -d    # starten
docker compose -p sonarr --project-directory . -f compose/docker-compose.sonarr.yml down     # stoppen
docker compose -p sonarr --project-directory . -f compose/docker-compose.sonarr.yml logs -f  # logs
```

### Netbird-IP van een service opvragen

```bash
docker exec netbird_sonarr netbird status
```

Het IP en de FQDN zijn ook zichtbaar in het Netbird-dashboard onder **Peers**.

### Verbinding testen

Zorg dat de Netbird-client actief is op het apparaat waarmee je verbinding maakt:

```bash
netbird status
```

Open daarna de browser via de URL uit de servicetabel bovenaan.

---

## Backup en herstel

```bash
./backup_slurp.sh    # maakt een bzip2-archief van alle persistente data in backups/
./restore_slurp.sh   # toont een menu met beschikbare backups en herstelt na bevestiging
```

Uitgesloten van de backup: `downloads/`, `movies/`, `music/`, `tv/`, `tmp/`, `backups/`.

---

## Optioneel

### Jellyfin hardware-transcodering

Hardware-acceleratie is uitgeschakeld via commentaar in `compose/docker-compose.jellyfin.yml`. Verwijder het juiste blok om het te activeren.

**Intel / AMD (VA-API):**

```bash
getent group video  | cut -d: -f3   # doorgaans 44
getent group render | cut -d: -f3   # doorgaans 104
```

Uncomment `devices` en `group_add` in de compose file en pas de waarden aan.

**NVIDIA:**

Vereist `nvidia-container-toolkit` op de host. Uncomment `runtime: nvidia` en de bijbehorende environment variabelen.

Herstart na activeren:

```bash
docker compose -p jellyfin --project-directory . -f compose/docker-compose.jellyfin.yml down
docker compose -p jellyfin --project-directory . -f compose/docker-compose.jellyfin.yml up -d
```

Activeer hardware-transcodering daarna in Jellyfin via `Dashboard → Afspelen → Transcodering`.

### Eigen Netbird management server

Voeg `NB_MANAGEMENT_URL` toe aan de `environment` van elke `netbird`-container in de compose files:

```yaml
environment:
  - NB_SETUP_KEY=${NB_SETUP_KEY_RADARR}
  - NB_HOSTNAME=radarr
  - NB_MANAGEMENT_URL=${NB_MANAGEMENT_URL}
```

Voeg de variabele toe aan `.env`:

```env
NB_MANAGEMENT_URL=https://netbird.jouwdomein.nl
```

Pas daarna alle hostnamen in de Caddyfiles aan van `<service>.netbird.cloud` naar `<service>.jouwdomein.nl`.

---

## Automatische updates

Watchtower controleert elke nacht om 04:00 op nieuwe images en herstart de containers automatisch. Het schema is aan te passen in `compose/docker-compose.watchtower.yml` via `WATCHTOWER_SCHEDULE` (cron-notatie met seconden: `s m h d M w`).
