#!/bin/bash
# Full reset: recreates both containers and a fresh emulator (cold boot, ~2-4 min).
# Run this before each new APK to guarantee a clean state.
docker compose down
docker compose up -d
echo "Follow progress with: docker logs -f caelus-emulator"
