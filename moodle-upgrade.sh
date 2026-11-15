#!/bin/sh
set -eu

echo "Running Moodle upgrade..."
docker compose exec app php admin/cli/upgrade.php

echo "Purging Moodle caches..."
docker compose exec app php admin/cli/purge_caches.php

echo "Moodle upgrade and cache purge completed."
