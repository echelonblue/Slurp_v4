# Slurp — Minimale configuratie per dienst

Dit document beschrijft de handelingen die na de eerste start nodig zijn om elke dienst werkend te krijgen. Volg de volgorde: Netbird ACL eerst, dan SABnzbd en Transmission, dan Prowlarr, dan de *arr-apps, dan Bazarr, Jellyfin en Overseerr.

Alle diensten zijn bereikbaar via hun Netbird-hostname op poort 443 (HTTPS). Interne koppelingen tussen diensten verlopen ook via deze hostnames.

---

## 0. Netbird — Zero Trust firewall

Netbird hanteert standaard **default deny**: peers kunnen elkaar niet bereiken tenzij een policy dat expliciet toestaat. Dit is het fundament van zero trust — alleen het verkeer dat nodig is wordt toegestaan.

### Groepen aanmaken

Maak in het Netbird-dashboard (`Groups`) de volgende groepen aan en voeg de bijbehorende peers toe:

| Groep          | Peers                                                                 |
|----------------|-----------------------------------------------------------------------|
| `clients`      | Alle persoonlijke apparaten (laptop, telefoon, tablet, ...)           |
| `arr-apps`     | `sonarr`, `radarr`, `lidarr`                                          |
| `downloaders`  | `sabnzbd`, `transmission`                                             |
| `indexers`     | `prowlarr`, `spotweb`                                                 |
| `media`        | `jellyfin`                                                            |
| `support`      | `bazarr`, `overseerr`, `shelfarr`, `lingarr`, `watchtower`           |

> Peers verschijnen in het dashboard zodra de containers voor het eerst verbinding maken met Netbird. Voeg ze toe aan de juiste groep via `Peers → [peer] → Groups`.

### Policies aanmaken

Maak in `Access Control → Policies` de volgende regels aan. Elke policy heeft een source-groep, een destination-groep, een protocol en een poort.

#### Policy 1 — Clients bereiken alle diensten

| Veld        | Waarde                                                         |
|-------------|----------------------------------------------------------------|
| Source      | `clients`                                                      |
| Destination | `arr-apps`, `downloaders`, `indexers`, `media`, `support`      |
| Protocol    | TCP                                                            |
| Poort       | 443                                                            |
| Action      | Accept                                                         |

#### Policy 2 — *arr-apps sturen downloads naar downloaders

| Veld        | Waarde          |
|-------------|-----------------|
| Source      | `arr-apps`      |
| Destination | `downloaders`   |
| Protocol    | TCP             |
| Poorten     | 443, 9091       |
| Action      | Accept          |

#### Policy 3 — *arr-apps bevragen indexers

| Veld        | Waarde      |
|-------------|-------------|
| Source      | `arr-apps`  |
| Destination | `indexers`  |
| Protocol    | TCP         |
| Poort       | 443         |
| Action      | Accept      |

#### Policy 4 — Prowlarr synchroniseert terug naar *arr-apps

| Veld        | Waarde      |
|-------------|-------------|
| Source      | `indexers`  |
| Destination | `arr-apps`  |
| Protocol    | TCP         |
| Poort       | 443         |
| Action      | Accept      |

#### Policy 5 — Support-diensten koppelen met *arr-apps

Bazarr, Overseerr en Lingarr moeten Sonarr en Radarr kunnen bereiken.

| Veld        | Waarde      |
|-------------|-------------|
| Source      | `support`   |
| Destination | `arr-apps`  |
| Protocol    | TCP         |
| Poort       | 443         |
| Action      | Accept      |

#### Policy 6 — Overseerr bereikt Jellyfin

| Veld        | Waarde      |
|-------------|-------------|
| Source      | `support`   |
| Destination | `media`     |
| Protocol    | TCP         |
| Poort       | 443         |
| Action      | Accept      |

### Overzicht verkeersmatrix

```
clients       → arr-apps, downloaders, indexers, media, support  : TCP 443
arr-apps      → downloaders                                       : TCP 443, 9091
arr-apps      → indexers                                          : TCP 443
indexers      → arr-apps                                          : TCP 443
support       → arr-apps                                          : TCP 443
support       → media                                             : TCP 443
```

Alle overige verbindingen worden geblokkeerd. Downloaders kunnen bijvoorbeeld niet naar buiten communiceren via het Netbird-netwerk, en media-peers kunnen geen *arr-apps aanspreken.

> **Let op:** Transmission heeft geen Netbird-poort 443 nodig voor inkomend verkeer van clients — die verbinding loopt al via TCP 9091. Voeg eventueel TCP 9091 toe aan Policy 1 als je de Transmission web-UI ook rechtstreeks wilt bereiken zonder Caddy.

---

## 1. SABnzbd

**URL:** https://sabnzbd.netbird.cloud

### Usenet-server toevoegen

`Config → Servers → Add Server`

| Veld              | Waarde                        |
|-------------------|-------------------------------|
| Host              | `news.tweaknews.eu`           |
| Port              | `563`                         |
| SSL               | Aan                           |
| Username          | zie provider-account          |
| Password          | zie provider-account          |
| Connections       | 8–20 (afhankelijk van account)|

### Mappen instellen

`Config → Folders`

| Veld                    | Waarde                  |
|-------------------------|-------------------------|
| Temporary Download Folder | `/incomplete-downloads` |
| Completed Download Folder | `/downloads`            |
| Watched Folder          | `/watch`                |

### Categorieën instellen

`Config → Categories`

Voeg de volgende categorieën toe zodat de *arr-apps bestanden op de juiste plek afleveren:

| Naam    | Folder      |
|---------|-------------|
| `tv`    | `/downloads/tv` |
| `movies`| `/downloads/movies` |
| `music` | `/downloads/music` |

---

## 2. Transmission

**URL:** https://transmission.netbird.cloud  
**Gebruikersnaam:** `xor` | **Wachtwoord:** zie `.env` → `TRANSMISSION_PASS`

Transmission is geconfigureerd met ProtonVPN als P2P-tunnel. Geen verdere basisinstelling vereist — de download- en watch-mappen zijn al via de compose file ingesteld.

---

## 3. Prowlarr

**URL:** https://prowlarr.netbird.cloud

### Indexers toevoegen

`Indexers → Add Indexer`

Voeg de gewenste Usenet- en torrent-indexers toe. Prowlarr synchroniseert deze automatisch naar de gekoppelde *arr-apps.

### Apps koppelen

`Settings → Apps → Add Application`

Voeg Sonarr, Radarr en Lidarr toe:

| Veld           | Sonarr                              | Radarr                              | Lidarr                              |
|----------------|-------------------------------------|-------------------------------------|-------------------------------------|
| App            | Sonarr                              | Radarr                              | Lidarr                              |
| Prowlarr URL   | `https://prowlarr.netbird.cloud`    | `https://prowlarr.netbird.cloud`    | `https://prowlarr.netbird.cloud`    |
| Base URL       | `https://sonarr.netbird.cloud`      | `https://radarr.netbird.cloud`      | `https://lidarr.netbird.cloud`      |
| API Key        | zie Sonarr → Settings → General     | zie Radarr → Settings → General     | zie Lidarr → Settings → General     |

Klik op **Test** en daarna **Save**. Prowlarr stuurt indexers voortaan automatisch door naar de apps.

---

## 4. Sonarr

**URL:** https://sonarr.netbird.cloud

### Download clients toevoegen

`Settings → Download Clients → +`

**SABnzbd:**

| Veld      | Waarde                           |
|-----------|----------------------------------|
| Name      | SABnzbd                          |
| Host      | `sabnzbd.netbird.cloud`          |
| Port      | `443`                            |
| Use SSL   | Aan                              |
| API Key   | zie SABnzbd → Config → General   |
| Category  | `tv`                             |

**Transmission:**

| Veld      | Waarde                           |
|-----------|----------------------------------|
| Name      | Transmission                     |
| Host      | `transmission.netbird.cloud`     |
| Port      | `9091`                           |
| Use SSL   | Nee                              |
| URL Base  | `/transmission/`                 |
| Username  | `xor`                            |
| Password  | zie `.env` → `TRANSMISSION_PASS` |
| Category  | `tv`                             |

### Root folder instellen

`Settings → Media Management → Root Folders → Add Root Folder`

Pad: `/tv`

### Kwaliteitsprofiel

`Settings → Profiles` — kies of maak een profiel dat past bij de gewenste kwaliteit (bijv. HD-1080p).

---

## 5. Radarr

**URL:** https://radarr.netbird.cloud

### Download clients toevoegen

`Settings → Download Clients → +`

**SABnzbd:**

| Veld      | Waarde                           |
|-----------|----------------------------------|
| Name      | SABnzbd                          |
| Host      | `sabnzbd.netbird.cloud`          |
| Port      | `443`                            |
| Use SSL   | Aan                              |
| API Key   | zie SABnzbd → Config → General   |
| Category  | `movies`                         |

**Transmission:**

| Veld      | Waarde                           |
|-----------|----------------------------------|
| Name      | Transmission                     |
| Host      | `transmission.netbird.cloud`     |
| Port      | `9091`                           |
| Use SSL   | Nee                              |
| URL Base  | `/transmission/`                 |
| Username  | `xor`                            |
| Password  | zie `.env` → `TRANSMISSION_PASS` |
| Category  | `movies`                         |

### Root folder instellen

`Settings → Media Management → Root Folders → Add Root Folder`

Pad: `/movies`

---

## 6. Lidarr

**URL:** https://lidarr.netbird.cloud

### Download clients toevoegen

`Settings → Download Clients → +`

**SABnzbd:**

| Veld      | Waarde                           |
|-----------|----------------------------------|
| Name      | SABnzbd                          |
| Host      | `sabnzbd.netbird.cloud`          |
| Port      | `443`                            |
| Use SSL   | Aan                              |
| API Key   | zie SABnzbd → Config → General   |
| Category  | `music`                          |

**Transmission:**

| Veld      | Waarde                           |
|-----------|----------------------------------|
| Name      | Transmission                     |
| Host      | `transmission.netbird.cloud`     |
| Port      | `9091`                           |
| Use SSL   | Nee                              |
| URL Base  | `/transmission/`                 |
| Username  | `xor`                            |
| Password  | zie `.env` → `TRANSMISSION_PASS` |
| Category  | `music`                          |

### Root folder instellen

`Settings → Media Management → Root Folders → Add Root Folder`

Pad: `/music`

---

## 7. Bazarr

**URL:** https://bazarr.netbird.cloud

### Sonarr koppelen

`Settings → Sonarr`

| Veld    | Waarde                                        |
|---------|-----------------------------------------------|
| Host    | `sonarr.netbird.cloud`                        |
| Port    | `443`                                         |
| SSL     | Aan                                           |
| API Key | zie Sonarr → Settings → General               |

### Radarr koppelen

`Settings → Radarr`

| Veld    | Waarde                                        |
|---------|-----------------------------------------------|
| Host    | `radarr.netbird.cloud`                        |
| Port    | `443`                                         |
| SSL     | Aan                                           |
| API Key | zie Radarr → Settings → General               |

### Ondertitelproviders toevoegen

`Settings → Providers → Add Provider`

Voeg providers toe zoals OpenSubtitles, Subscene of Addic7ed. Stel de gewenste talen in via `Settings → Languages`.

---

## 8. Jellyfin

**URL:** https://jellyfin.netbird.cloud

### Eerste start

Bij de eerste keer openen doorloop je de setup-wizard:

1. Maak een admin-gebruiker aan
2. Voeg mediabibliotheken toe:

| Bibliotheek | Pad       | Type   |
|-------------|-----------|--------|
| Films       | `/media/movies` | Movies |
| Series      | `/media/tv`     | Shows  |
| Muziek      | `/media/music`  | Music  |

### Hardware-transcoding (optioneel)

Zie de sectie **Jellyfin HW Transcoding** in `README.md`.

---

## 9. Overseerr

**URL:** https://overseerr.netbird.cloud

### Jellyfin koppelen

Bij de eerste start vraagt Overseerr om een Jellyfin-koppeling:

| Veld      | Waarde                            |
|-----------|-----------------------------------|
| URL       | `https://jellyfin.netbird.cloud`  |
| API Key   | zie Jellyfin → Dashboard → API Keys |

### Sonarr koppelen

`Settings → Sonarr → Add Sonarr Server`

| Veld             | Waarde                           |
|------------------|----------------------------------|
| Hostname         | `sonarr.netbird.cloud`           |
| Port             | `443`                            |
| SSL              | Aan                              |
| API Key          | zie Sonarr → Settings → General  |
| Default Profile  | kies gewenst kwaliteitsprofiel   |
| Default Root     | `/tv`                            |

### Radarr koppelen

`Settings → Radarr → Add Radarr Server`

| Veld             | Waarde                           |
|------------------|----------------------------------|
| Hostname         | `radarr.netbird.cloud`           |
| Port             | `443`                            |
| SSL              | Aan                              |
| API Key          | zie Radarr → Settings → General  |
| Default Profile  | kies gewenst kwaliteitsprofiel   |
| Default Root     | `/movies`                        |

---

## 10. Spotweb

**URL:** https://spotweb.netbird.cloud  
**Login:** `admin` / zie database (wachtwoord via salted SHA1 opgeslagen)

### Usenet-server instellen

`Admin → Settings → Usenet providers`

Voeg dezelfde server toe als SABnzbd (TweakNews of andere provider). Spotweb gebruikt de server voor het ophalen van spot-headers.

### Spots ophalen

De retriever draait automatisch elke 30 minuten via de `retriever_spotweb`-container. Voor een handmatige run:

```bash
docker exec spotweb php /var/www/spotweb/retrieve.php
```

De eerste run kan lang duren — Spotweb haalt alle beschikbare headers op.

---

## 11. Shelfarr

**URL:** https://shelfarr.netbird.cloud

Shelfarr is een boekenbeheertool. Voeg bij de eerste start de boekenmap toe en configureer eventuele download clients of OPDS-feeds via de instellingen.

---

## 12. Lingarr

**URL:** https://lingarr.netbird.cloud

### Ollama koppelen

Stel het Ollama-adres in via `OLLAMA_HOST` in `.env`:

```env
OLLAMA_HOST=<IP van de Ollama-server>
```

Herstart de Lingarr-stack na de wijziging. Het vertaalmodel is instelbaar via de Lingarr-interface onder `Settings → Translation`.

### Sonarr/Radarr koppelen

Lingarr haalt ondertitels op via Bazarr en koppelt met Sonarr/Radarr voor het automatisch vertalen van nieuwe ondertitels. Stel de koppelingen in via `Settings → Integrations`.
