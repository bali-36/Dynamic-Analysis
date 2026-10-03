#!/bin/bash

echo "Creating AVD (if not already present)..."
echo "no" | avdmanager create avd -n caelus_s10 -k "system-images;android-30;google_apis;x86_64" -d pixel_3a --force

echo "Launching emulator..."
emulator -avd caelus_s10 -no-window -no-audio -no-snapshot-save > /home/androidusr/emulator.log 2>&1 &

echo "Waiting for Android boot to complete..."
while ! adb shell getprop sys.boot_completed 2>/dev/null | grep -q 1; do
  sleep 5
done

echo "Boot completed. Starting ADB bridge on 5556..."
socat TCP-LISTEN:5556,fork,reuseaddr TCP:127.0.0.1:5555 &

echo "Ready. Holding container open."
tail -f /dev/null
