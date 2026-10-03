#!/usr/bin/env bash
set -euo pipefail

echo "Restoring clean emulator snapshot..."
docker exec caelus-emulator adb emu avd snapshot load caelus_clean
echo "Emulator reset to clean state."
