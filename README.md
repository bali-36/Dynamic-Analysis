# Caelus — Dynamic Analysis Environment

Self-hosted MobSF + Android emulator setup for Caelus's Dynamic Analysis Agent.
Two Docker containers, bridged over ADB, with the emulator network-isolated
from the internet (see Security.md in the main repo for the threat model).

## Architecture

- `android-emulator`: budtmo/docker-android image, KVM-accelerated, runs on an
  isolated internal network (no internet access)
- `mobsf`: MobSF container, dual-homed on both the internal network (to reach
  the emulator) and a public network (so the host/other services can reach it)
- Bridged via `socat` on port 5556 — see "Known gotchas" below for why

## Prerequisites — CHECK THESE FIRST

This setup needs real hardware virtualization. Do not skip verification —
I lost significant time on this exact issue.

1. Host must support nested virtualization (if running in a VM):
   - VMware: enable "Virtualize Intel VT-x/EPT" in VM processor settings
   - Windows host: Hyper-V/WSL2's hypervisor can block this — may need
     `bcdedit /set hypervisorlaunchtype off` (disables WSL2 while active)
   - GCP: use `--enable-nested-virtualization` at instance creation (N1/N2/N2D only)

2. Verify inside the VM:
```bash
   egrep -c '(vmx|svm)' /proc/cpuinfo   # should be > 0
   ls -la /dev/kvm
   sudo apt install -y cpu-checker && kvm-ok
```

3. Find YOUR host's kvm group GID — this is host-specific, will NOT match
   what's in docker-compose.yml by default:
```bash
   getent group kvm
```
   Update `group_add` under the `android-emulator` service to match.

4. Disk space: need 20GB+ free. The AVD userdata partition alone needs ~7GB.

## Setup

```bash
cp .env.example .env
# edit .env, set MOBSF_API_KEY to a real random value:
python3 -c "import secrets; print(secrets.token_hex(32))"

docker compose up -d
docker logs -f caelus-emulator
```

Wait for `Boot completed. Starting ADB bridge on 5556...` — first cold boot
takes 2-4 minutes (creates a fresh AVD each time; this image's own AVD
auto-creation is broken, see below, so I do it myself on every start).

## Verify it's working

```bash
docker exec caelus-mobsf bash -c "adb connect caelus-emulator:5556 && adb devices"
```
Expect: `caelus-emulator:5556   device` (not `offline`, not connection refused)

```bash
curl http://localhost:8000
```
Should return MobSF's login page HTML. Login: mobsf/mobsf (CHANGE THIS, see below)

## Known gotchas (do not re-debug these — read this first)

- **MobSF needs internet on first boot only**, to download JADX. If you see
  `Internet Not Available. Skipping Update check` AND a JADX download error
  in `docker logs caelus-mobsf`, temporarily comment out `internal: true` on
  the networks, let it finish, then re-enable isolation. Already downloaded
  JADX persists in the `mobsf-data` volume afterward.

- **The emulator image's own AVD auto-creation is broken** for this image
  version — the `EMULATOR_DEVICE` env var approach produces an AVD that
  fails with `Unknown AVD name`. I bypass this entirely: `emulator-start.sh`
  creates and launches the AVD manually on every container start.

- **avdmanager's `-s` (silent) flag must come before `create avd`**, not
  after it with the other action options — putting it last causes a silent
  failure (prints usage, exits). I suppress the interactive prompt with
  `echo "no" | avdmanager ...` instead.

- **ADB port 5555 only binds to loopback** inside the emulator container by
  default (this image's own `port_forwarder` process doesn't reliably bridge
  it out). I run `socat` myself to bridge `127.0.0.1:5555` → `0.0.0.0:5556`.
  MobSF connects to port **5556**, not the standard 5555.

- **Default MobSF credentials are mobsf/mobsf** — change this before this
  is reachable from anywhere beyond localhost:
```bash
  docker exec -it caelus-mobsf python3 manage.py changepassword mobsf
```

- **`docker compose down` + `up` fully recreates the AVD from scratch**
  (cold boot every time, ~2-4 min) since this is not using snapshots currently.
  This is intentional for clean isolation between work sessions, but means
  don't tear it down between every single test run — only when you actually
  need a clean state.

## Security notes

- Emulator container has NO internet access by design (isolated network) —
  this is deliberate, not a bug, since it may run untrusted/malicious APKs.
- Don't expose port 8000 (MobSF) or 6080 (VNC debug viewer) beyond localhost
  or a tightly firewalled range — see Security.md in the main repo.
- `.env` (API key) is gitignored — get it from [wherever you're sharing it],
  never commit it.

## Day-to-day usage

```bash
./setup.sh      # full fresh start (if you don't just use docker compose up -d)
./reset_env.sh   # reset emulator state before a new scan
./teardown.sh     # stop everything
```

## Running an actual dynamic scan

See the main project's `design.md` for how scan results map to the
`Finding` schema. Quick manual test:

```bash
API_KEY=$(grep MOBSF_API_KEY .env | cut -d= -f2)
curl -F "file=@test.apk" -H "Authorization: $API_KEY" http://localhost:8000/api/v1/upload
# returns a hash — use it for scan, then dynamic/start_analysis, etc.
```

## Frida

The emulator image already provides a working Frida server (`frida-ps -U` from
the MobSF container lists device processes with no extra setup). Manual
frida-server push is therefore OFF by default (`ENABLE_FRIDA=0`).

If you ever enable it, the frida-server version MUST exactly match the `frida`
Python package in the MobSF container (`docker exec caelus-mobsf pip show frida`).
The binary is ~110MB, is gitignored, and adds ~3 minutes to every start.

## Resetting between scans

`./reset.sh` recreates everything for a clean emulator (no snapshots are used).
