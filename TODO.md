# TODO

## Handmatige configuratie na eerste start

### Transmission toevoegen als download client in Sonarr, Radarr en Lidarr

Voeg in elk van de drie apps via `Settings → Download Clients → +` een nieuwe Transmission-client toe:

| Veld      | Waarde                                      |
|-----------|---------------------------------------------|
| Name      | Transmission                                |
| Host      | `100.122.117.129`                           |
| Port      | `9091`                                      |
| Use SSL   | Nee                                         |
| URL Base  | `/transmission/`                            |
| Username  | *(leeg)*                                    |
| Password  | *(leeg)*                                    |
| Category  | `tv` (Sonarr) / `movies` (Radarr) / `music` (Lidarr) |

Klik na het invullen op **Test** om de verbinding te controleren.

> Het Netbird-IP van Transmission (`100.122.117.129`) is op te vragen met:
> ```bash
> docker exec netbird_transmission netbird status
> ```
