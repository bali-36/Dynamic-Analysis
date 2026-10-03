#!/usr/bin/env bash
set -euo pipefail

echo "== Caelus Dynamic Analysis Environment — Setup =="

# --- 1. Pre-flight checks ---
echo "[1/6] Checking KVM availability..."
if [ ! -e /dev/kvm ]; then
  echo "ERROR: /dev/kvm not found. Emulator will not be usable. Aborting."
  exit 1
fi

if ! groups "$USER" | grep -q '\bkvm\b'; then
  echo "WARNING: current user is not in the 'kvm' group."
  echo "Run: sudo usermod -aG kvm \$USER && newgrp kvm"
fi

if [ ! -f .env ]; then
  echo "ERROR: .env file missing. Create it with MOBSF_API_KEY set before running this script."
  exit 1
fi

# --- 2. Bring up the emulator first ---
echo "[2/6] Starting Android emulator container..."
docker compose up -d android-emulator

echo "[3/6] Waiting for emulator to boot (this can take 1-3 minutes)..."
TRIES=0
MAX_TRIES=60
until docker exec caelus-emulator adb shell getprop sys.boot_completed 2>/dev/null | grep -q 1; do
  TRIES=$((TRIES+1))
  if [ "$TRIES" -ge "$MAX_TRIES" ]; then
    echo "ERROR: emulator did not boot within expected time. Check 'docker logs caelus-emulator'."
    exit 1
  fi
  sleep 5
done
echo "Emulator booted."

# --- 3. Mobsfy the emulator (Frida server, CA cert trust, proxy config) ---
echo "[4/6] Preparing emulator for dynamic analysis (mobsfy)..."
docker exec caelus-emulator adb root
docker exec caelus-emulator bash -c \
  "curl -fsSL https://raw.githubusercontent.com/MobSF/Mobile-Security-Framework-MobSF/master/scripts/mobsfy.sh | bash"

# --- 4. Snapshot the clean, prepped state ---
echo "[5/6] Saving clean snapshot for reset-between-scans..."
docker exec caelus-emulator adb emu avd snapshot save caelus_clean

# --- 5. Bring up MobSF, pointed at the prepped emulator ---
echo "[6/6] Starting MobSF..."
docker compose up -d mobsf

TRIES=0
until curl -sf http://localhost:8000 >/dev/null 2>&1; do
  TRIES=$((TRIES+1))
  if [ "$TRIES" -ge 30 ]; then
    echo "ERROR: MobSF did not become reachable. Check 'docker logs caelus-mobsf'."
    exit 1
  fi
  sleep 3
done

echo ""
echo "===================================================="
echo " Setup complete."
echo " MobSF UI:        http://localhost:8000"
echo " Emulator (debug): http://localhost:6080   (do not expose externally)"
echo " API key is in .env"
echo "===================================================="
