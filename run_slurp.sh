#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "$SCRIPT_DIR"

docker compose -p lidarr    -f docker-compose.lidarr.yml    up -d
docker compose -p radarr    -f docker-compose.radarr.yml    up -d
docker compose -p sabnzbd   -f docker-compose.sabnzbd.yml   up -d
docker compose -p sonarr    -f docker-compose.sonarr.yml    up -d
docker compose -p overseerr -f docker-compose.overseerr.yml up -d
docker compose -p spotweb   -f docker-compose.spotweb.yml   up -d
docker compose -p jellyfin  -f docker-compose.jellyfin.yml  up -d
docker compose -p bazarr    -f docker-compose.bazarr.yml    up -d
docker compose -p prowlarr  -f docker-compose.prowlarr.yml  up -d
docker compose -p lingarr   -f docker-compose.lingarr.yml   up -d
docker compose -p watchtower -f docker-compose.watchtower.yml up -d
