#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "$SCRIPT_DIR"

docker compose -p lidarr       --project-directory "$SCRIPT_DIR" -f compose/docker-compose.lidarr.yml       up -d
docker compose -p radarr       --project-directory "$SCRIPT_DIR" -f compose/docker-compose.radarr.yml       up -d
docker compose -p sabnzbd      --project-directory "$SCRIPT_DIR" -f compose/docker-compose.sabnzbd.yml      up -d
docker compose -p sonarr       --project-directory "$SCRIPT_DIR" -f compose/docker-compose.sonarr.yml       up -d
docker compose -p overseerr    --project-directory "$SCRIPT_DIR" -f compose/docker-compose.overseerr.yml    up -d
docker compose -p spotweb      --project-directory "$SCRIPT_DIR" -f compose/docker-compose.spotweb.yml      up -d
docker compose -p jellyfin     --project-directory "$SCRIPT_DIR" -f compose/docker-compose.jellyfin.yml     up -d
docker compose -p bazarr       --project-directory "$SCRIPT_DIR" -f compose/docker-compose.bazarr.yml       up -d
docker compose -p prowlarr     --project-directory "$SCRIPT_DIR" -f compose/docker-compose.prowlarr.yml     up -d
docker compose -p transmission --project-directory "$SCRIPT_DIR" -f compose/docker-compose.transmission.yml up -d
docker compose -p shelfarr     --project-directory "$SCRIPT_DIR" -f compose/docker-compose.shelfarr.yml     up -d
docker compose -p lingarr      --project-directory "$SCRIPT_DIR" -f compose/docker-compose.lingarr.yml      up -d
docker compose -p watchtower   --project-directory "$SCRIPT_DIR" -f compose/docker-compose.watchtower.yml   up -d
