#!/bin/bash

# Set ENABLE_FRIDA=0 in docker-compose.yml (environment) to skip the manual
# frida-server push and let MobSF handle Frida itself.
ENABLE_FRIDA="${ENABLE_FRIDA:-0}"

echo "Creating AVD (if not already present)..."
echo "no" | avdmanager create avd -n caelus_s10 -k "system-images;android-30;google_apis;x86_64" -d pixel_3a --force

echo "Launching emulator..."
emulator -avd caelus_s10 -no-window -no-audio -no-snapshot-save > /home/androidusr/emulator.log 2>&1 &

echo "Waiting for Android boot to complete..."
while ! adb shell getprop sys.boot_completed 2>/dev/null | grep -q 1; do
  sleep 5
done
echo "Android booted."

echo "Restarting adbd as root..."
adb root
ROOT_OK=0
for i in $(seq 1 24); do
  if adb shell id 2>/dev/null | grep -q "uid=0"; then
    echo "adbd is running as root."
    ROOT_OK=1
    break
  fi
  sleep 5
done
if [ "$ROOT_OK" -ne 1 ]; then
  echo "WARNING: could not confirm root. Frida and some MobSF features may not work."
fi

if [ "$ENABLE_FRIDA" = "1" ]; then
  if [ -f /frida-server ]; then
    echo "Pushing frida-server to emulator (this can take 2-3 minutes)..."
    adb push /frida-server /data/local/tmp/frida-server
    adb shell "chmod 755 /data/local/tmp/frida-server"

    echo "Starting frida-server..."
    adb shell "/data/local/tmp/frida-server -D"

    FRIDA_OK=0
    for i in $(seq 1 10); do
      if adb shell "pidof frida-server" 2>/dev/null | grep -q "[0-9]"; then
        echo "frida-server is running."
        FRIDA_OK=1
        break
      fi
      sleep 2
    done
    if [ "$FRIDA_OK" -ne 1 ]; then
      echo "WARNING: frida-server did not start. Check version match with MobSF's frida package."
    fi
  else
    echo "WARNING: /frida-server not found (check the volume mount). Skipping Frida setup."
  fi
else
  echo "ENABLE_FRIDA=0, skipping manual Frida setup."
fi

echo "Starting ADB bridge on 5556..."
socat TCP-LISTEN:5556,fork,reuseaddr TCP:127.0.0.1:5555 &

echo "Ready. Holding container open."
tail -f /dev/null
