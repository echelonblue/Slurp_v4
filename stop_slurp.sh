#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "$SCRIPT_DIR"

docker compose -p watchtower -f docker-compose.watchtower.yml down
docker compose -p lingarr    -f docker-compose.lingarr.yml    down
docker compose -p prowlarr   -f docker-compose.prowlarr.yml   down
docker compose -p bazarr     -f docker-compose.bazarr.yml     down
docker compose -p jellyfin   -f docker-compose.jellyfin.yml   down
docker compose -p spotweb    -f docker-compose.spotweb.yml    down
docker compose -p overseerr  -f docker-compose.overseerr.yml  down
docker compose -p sonarr     -f docker-compose.sonarr.yml     down
docker compose -p sabnzbd    -f docker-compose.sabnzbd.yml    down
docker compose -p radarr     -f docker-compose.radarr.yml     down
docker compose -p lidarr     -f docker-compose.lidarr.yml     down
