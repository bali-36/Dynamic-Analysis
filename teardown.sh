#!/usr/bin/env bash
set -euo pipefail

echo "Stopping Caelus dynamic analysis environment..."
docker compose down
echo "Stopped. Data volume (mobsf-data) preserved. Run setup.sh to start again."
