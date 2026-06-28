#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "$SCRIPT_DIR"

docker compose -p watchtower   --project-directory "$SCRIPT_DIR" -f compose/docker-compose.watchtower.yml   down
docker compose -p lingarr      --project-directory "$SCRIPT_DIR" -f compose/docker-compose.lingarr.yml      down
docker compose -p shelfarr     --project-directory "$SCRIPT_DIR" -f compose/docker-compose.shelfarr.yml     down
docker compose -p transmission --project-directory "$SCRIPT_DIR" -f compose/docker-compose.transmission.yml down
docker compose -p prowlarr     --project-directory "$SCRIPT_DIR" -f compose/docker-compose.prowlarr.yml     down
docker compose -p bazarr       --project-directory "$SCRIPT_DIR" -f compose/docker-compose.bazarr.yml       down
docker compose -p jellyfin     --project-directory "$SCRIPT_DIR" -f compose/docker-compose.jellyfin.yml     down
docker compose -p spotweb      --project-directory "$SCRIPT_DIR" -f compose/docker-compose.spotweb.yml      down
docker compose -p overseerr    --project-directory "$SCRIPT_DIR" -f compose/docker-compose.overseerr.yml    down
docker compose -p sonarr       --project-directory "$SCRIPT_DIR" -f compose/docker-compose.sonarr.yml       down
docker compose -p sabnzbd      --project-directory "$SCRIPT_DIR" -f compose/docker-compose.sabnzbd.yml      down
docker compose -p radarr       --project-directory "$SCRIPT_DIR" -f compose/docker-compose.radarr.yml       down
docker compose -p lidarr       --project-directory "$SCRIPT_DIR" -f compose/docker-compose.lidarr.yml       down
