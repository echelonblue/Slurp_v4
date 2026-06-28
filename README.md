# Slurp — *arr stack met Netbird VPN-tunnels

Elke service draait in een eigen Docker Compose-stack en is individueel bereikbaar via HTTPS (poort 443) over een aparte Netbird-tunnel. Er is geen open poort nodig op de host of router.

## Services

| Service    | Functie                  | Interne poort | URL                              |
|------------|--------------------------|---------------|----------------------------------|
| Lidarr     | Muziekbeheer             | 8686          | https://lidarr.netbird.cloud     |
| Radarr     | Filmbeheer               | 7878          | https://radarr.netbird.cloud     |
| SABnzbd    | NZB-downloader           | 8080          | https://sabnzbd.netbird.cloud    |
| Transmission | BitTorrent-client (via P2P VPN) | 9091 | https://transmission.netbird.cloud |
| Sonarr     | Seriebeheer              | 8989          | https://sonarr.netbird.cloud     |
| Overseerr  | Verzoekenbeheer          | 5055          | https://overseerr.netbird.cloud  |
| Spotweb    | Usenet-indexer           | 80            | https://spotweb.netbird.cloud    |
| Jellyfin   | Mediaserver              | 8096          | https://jellyfin.netbird.cloud   |
| Bazarr     | Ondertitelbeheer         | 6767          | https://bazarr.netbird.cloud     |
| Prowlarr   | Indexerbeheer            | 9696          | https://prowlarr.netbird.cloud   |
| Shelfarr   | Boekenbeheer             | 80            | https://shelfarr.netbird.cloud   |
| Lingarr    | Ondertitelvertaling (AI) | 80            | https://lingarr.netbird.cloud    |
| Watchtower | Automatische updates     | —             | —                                |

> De hostnamen gelden voor een Netbird-account met het domein `netbird.cloud`. Pas de Caddyfiles aan als jouw account een ander domein gebruikt.

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

WireGuard is de base-container. Alle containers delen zijn netwerk-namespace en sturen al hun verkeer via `wg0` (ProtonVPN). Netbird verbindt door via ProtonVPN en maakt `wt0` aan voor beheer-toegang. Een healthcheck garandeert dat de WireGuard-handshake geslaagd is vóór de andere containers starten; DNS loopt via `1.1.1.1` en is bereikbaar door de tunnel.

Doordat alle containers het netwerk-namespace van de Netbird-container delen, is de service alleen bereikbaar via het Netbird-IP. Er hoeven geen poorten op de host geopend te worden.

## Mapstructuur

```
.
├── .env                              # Setup keys en wachtwoorden (niet committen!)
├── run_slurp.sh                      # Start alle containers
├── stop_slurp.sh                     # Stopt alle containers
├── compose/
│   ├── docker-compose.lidarr.yml
│   ├── docker-compose.radarr.yml
│   ├── docker-compose.sabnzbd.yml
│   ├── docker-compose.transmission.yml
│   ├── docker-compose.sonarr.yml
│   ├── docker-compose.overseerr.yml
│   ├── docker-compose.spotweb.yml
│   ├── docker-compose.jellyfin.yml
│   ├── docker-compose.bazarr.yml
│   ├── docker-compose.prowlarr.yml
│   ├── docker-compose.shelfarr.yml
│   ├── docker-compose.lingarr.yml
│   └── docker-compose.watchtower.yml
├── caddy/
│   ├── Caddyfile.lidarr
│   ├── Caddyfile.radarr
│   ├── Caddyfile.sabnzbd
│   ├── Caddyfile.transmission
│   ├── Caddyfile.sonarr
│   ├── Caddyfile.overseerr
│   ├── Caddyfile.spotweb
│   ├── Caddyfile.jellyfin
│   ├── Caddyfile.bazarr
│   ├── Caddyfile.prowlarr
│   ├── Caddyfile.shelfarr
│   └── Caddyfile.lingarr
├── config/                           # Persistente configuratie per app
│   ├── config_lidarr/
│   ├── config_radarr/data/
│   ├── config_sabznbd/
│   ├── config_transmission/
│   ├── config_wireguard_transmission/wg_confs/wg0.conf  # P2P VPN config
│   ├── config_sonarr/data/
│   ├── config_overseerr/
│   ├── config_spotweb/
│   ├── config_spotweb_db/            # MariaDB data
│   ├── config_jellyfin/
│   ├── config_jellyfin_cache/
│   ├── config_bazarr/
│   ├── config_prowlarr/
│   ├── config_shelfarr/
│   ├── config_lingarr/
│   ├── config_netbird_<service>/{etc,var}/
│   └── config_caddy_<service>/{data,config}/
├── downloads/                        # Gedeelde downloadmap
├── music/                            # Lidarr en Jellyfin mediamap
├── movies/                           # Radarr, Bazarr en Jellyfin mediamap
├── tv/                               # Sonarr, Bazarr en Jellyfin mediamap
├── tmp/tmp_sabnzbd/                  # SABnzbd tijdelijke bestanden
```

## Installatie

### 1. Vereisten

- Docker met de Compose-plugin
- Een Netbird-account — gratis aan te maken op [app.netbird.io](https://app.netbird.io)
- Netbird-client geïnstalleerd op elk apparaat dat de services moet bereiken

### 2. Setup keys aanmaken

Maak in het Netbird-dashboard voor **elke service een aparte setup key** aan:
`Setup Keys → Create Setup Key`

Gebruik het type **Reusable** als je containers regelmatig opnieuw aanmaakt, of **One-time** voor eenmalig gebruik.

### 3. `.env` invullen

Open `.env` en vul per service de bijbehorende waarden in:

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
```

### 4. Mappen aanmaken

```bash
mkdir -p config/config_lidarr config/config_radarr/data config/config_sabznbd config/config_transmission config/config_wireguard_transmission/wg_confs config/config_sonarr/data config/config_overseerr config/config_spotweb config/config_spotweb_db config/config_jellyfin config/config_jellyfin_cache config/config_bazarr config/config_prowlarr config/config_shelfarr config/config_lingarr
mkdir -p config/config_netbird_{lidarr,radarr,sabnzbd,transmission,sonarr,overseerr,spotweb,jellyfin,bazarr,prowlarr,shelfarr,lingarr}/{etc,var}
mkdir -p config/config_caddy_{lidarr,radarr,sabnzbd,transmission,sonarr,overseerr,spotweb,jellyfin,bazarr,prowlarr,shelfarr,lingarr}/{data,config}
mkdir -p tmp/tmp_transmission tmp/tmp_sabnzbd tmp/tmp_sabnzbd_watch
mkdir -p downloads/complete downloads/incomplete music movies tv
```

### 5. Netbird ACL instellen

Netbird hanteert **default deny** — peers kunnen elkaar niet bereiken tenzij een policy dat toestaat. De volledige zero trust configuratie met groepen en gerichte policies staat beschreven in [`SETUP.md → Netbird Zero Trust firewall`](SETUP.md).

> Tijdelijke workaround als een policy niet direct werkt:
> ```bash
> docker exec netbird_<service> iptables -I INPUT 1 -i wt0 -p tcp --dport 443 -j ACCEPT
> ```

### 6. Starten

```bash
./run_slurp.sh
```

### 7. Eenmalige setup per service

**Spotweb — database initialiseren:**

```bash
docker exec spotweb php /var/www/spotweb/bin/upgrade-db.php
```

**Jellyfin — mediabibliotheken toevoegen:**

Voeg na de eerste login de volgende mappen toe als bibliotheek:

| Type    | Pad in container |
|---------|-----------------|
| Films   | `/media/movies` |
| Series  | `/media/tv`     |
| Muziek  | `/media/music`  |

**SABnzbd — mappen instellen:**

Stel in `Config → Folders` de volgende paden in:

| Instelling            | Pad in container        |
|-----------------------|-------------------------|
| Temporary Download    | `/incomplete-downloads` |
| Completed Download    | `/downloads`            |
| Watched Folder        | `/watch`                |

**Transmission — P2P VPN instellen:**

De WireGuard-config staat in `config/config_wireguard_transmission/wg_confs/wg0.conf`. Dit is een standaard WireGuard/ProtonVPN-config zonder aanpassingen — de `DNS`-regel wordt weggelaten omdat Docker de DNS-resolver (`1.1.1.1`) zelf instelt:

```ini
[Interface]
PrivateKey = <jouw private key>
Address = 10.2.0.2/32

[Peer]
PublicKey = <server public key>
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = <server>:51820
PersistentKeepalive = 25
```

`AllowedIPs = 0.0.0.0/0` stuurt al het uitgaande verkeer door wg0 — dit zorgt voor de kill-switch: als de VPN wegvalt, heeft Transmission geen internetverbinding meer.

Bij een andere VPN-provider: vervang het `[Interface]`- en `[Peer]`-blok volledig door de config van de provider. De bestandsnaam moet `wg0.conf` blijven. Herstart na wijzigingen:

```bash
docker compose -p transmission --project-directory . -f compose/docker-compose.transmission.yml down
docker compose -p transmission --project-directory . -f compose/docker-compose.transmission.yml up -d
```

Controleer of Transmission via de VPN verbindt:

```bash
docker exec --user=1000 transmission curl -s https://ipinfo.io/ip
```

Dit toont het IP van de VPN-server (niet het thuisnetwerk).

**Transmission — download client in Sonarr, Radarr en Lidarr:**

Voeg in elk van de drie apps via `Settings → Download Clients → +` een nieuwe Transmission-client toe:

| Veld      | Waarde                                                        |
|-----------|---------------------------------------------------------------|
| Name      | Transmission                                                  |
| Host      | `transmission.netbird.cloud`                                  |
| Port      | `9091`                                                        |
| Use SSL   | Nee                                                           |
| URL Base  | `/transmission/`                                              |
| Username  | `xor`                                                         |
| Password  | zie `.env` → `TRANSMISSION_PASS`                             |
| Category  | `tv` (Sonarr) / `movies` (Radarr) / `music` (Lidarr)        |

Klik na het invullen op **Test** om de verbinding te controleren. Het Netbird-IP is op te vragen met:

```bash
docker exec netbird_transmission netbird status
```

**Lingarr — Ollama koppelen:**

Het Ollama-adres wordt ingesteld via `OLLAMA_HOST` in `.env`. De standaardpoort is `11434`. Pas het IP aan naar de server waarop Ollama draait en herstart de stack.

**Bazarr — integraties instellen:**

Verbind Bazarr met Sonarr en Radarr via `Instellingen → Sonarr / Radarr`:

| Veld    | Waarde                          |
|---------|---------------------------------|
| Host    | `sonarr.netbird.cloud` (of radarr) |
| Poort   | `443`                           |
| SSL     | Aan                             |
| API Key | Te vinden in Sonarr/Radarr onder `Instellingen → Algemeen` |

## Gebruik

### Alles starten / stoppen

```bash
./run_slurp.sh
./stop_slurp.sh
```

### Losse service beheren

```bash
docker compose -p sonarr --project-directory . -f compose/docker-compose.sonarr.yml up -d    # starten
docker compose -p sonarr --project-directory . -f compose/docker-compose.sonarr.yml down     # stoppen
docker compose -p sonarr --project-directory . -f compose/docker-compose.sonarr.yml logs -f  # logs bekijken
```

### Netbird-IP van een service opvragen

```bash
docker exec netbird_sonarr netbird status
```

Het IP (bijv. `100.x.x.x`) en de FQDN zijn ook zichtbaar in het Netbird-dashboard onder **Peers**.

### Service bereiken

Zorg dat de Netbird-client actief is op het apparaat waarmee je verbinding maakt:

```bash
netbird status
```

Open daarna de browser via de URL uit de servicetabel bovenaan.

## HTTPS-certificaat vertrouwen (eenmalig per service)

Caddy genereert een self-signed certificaat via een ingebouwde CA. De browser toont een waarschuwing totdat je het root-certificaat vertrouwt.

**Root-certificaat exporteren:**

```bash
docker cp caddy_sonarr:/data/caddy/pki/authorities/local/root.crt ./caddy-root-sonarr.crt
```

Voeg het `.crt`-bestand toe aan je systeem- of browsertruststore. Op macOS:

```bash
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ./caddy-root-sonarr.crt
```

> Elke Caddy-instantie heeft een eigen CA. Je hebt dus één root-cert per service.

## Jellyfin HW Transcoding

Hardware-acceleratie is optioneel en uitgeschakeld door commentaar in `compose/docker-compose.jellyfin.yml`. Verwijder het juiste blok om het te activeren.

**Intel / AMD (VA-API):**

Vraag eerst de group ID's op de host op:

```bash
getent group video  | cut -d: -f3   # doorgaans 44
getent group render | cut -d: -f3   # doorgaans 104
```

Uncomment daarna `devices` en `group_add` in de compose file en pas de waarden aan.

**NVIDIA:**

Vereist `nvidia-container-toolkit` op de host. Uncomment `runtime: nvidia` en de bijbehorende environment variabelen.

Na het activeren, herstart de stack:

```bash
docker compose -p jellyfin --project-directory . -f compose/docker-compose.jellyfin.yml down
docker compose -p jellyfin --project-directory . -f compose/docker-compose.jellyfin.yml up -d
```

Activeer hardware-transcoding daarna in Jellyfin via `Dashboard → Afspelen → Transcodering`.

## Optie: eigen Netbird management server

Standaard verbinden de Netbird-containers met Netbird's cloud (`netbird.cloud`). Bij gebruik van een self-hosted Netbird-server zijn twee aanpassingen nodig.

### 1. Management URL toevoegen aan elke compose file

Voeg `NB_MANAGEMENT_URL` toe aan de `environment` van elke `netbird`-container:

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

### 2. Hostnamen in alle Caddyfiles aanpassen

De hostnamen `<service>.netbird.cloud` zijn gekoppeld aan Netbird's cloud-DNS. Een self-hosted server gebruikt een eigen magic DNS-domein (ingesteld in de management server configuratie). Pas alle Caddyfiles aan:

```
# Van:
radarr.netbird.cloud

# Naar:
radarr.jouwdomein.nl
```

Dit geldt voor alle negen Caddyfiles in de `caddy/`-map.

---

## Automatische updates

Watchtower controleert elke nacht om 04:00 of er nieuwe images beschikbaar zijn en herstart de containers automatisch. Oude images worden na de update opgeruimd.

Het update-schema is aan te passen in `compose/docker-compose.watchtower.yml` via `WATCHTOWER_SCHEDULE` (standaard cron-notatie met seconden: `s m h d M w`).
