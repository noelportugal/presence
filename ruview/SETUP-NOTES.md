# RuView / WiFi-DensePose — Setup Notes

_Last updated: 2026-06-08_

Setup of 3× ESP32-S3 WiFi-CSI sensing nodes + RuView server on macOS (Apple Silicon).

## TL;DR status

| Component | Status |
|---|---|
| 3× ESP32-S3 flashed (**non-display 4MB build**) + provisioned | ✅ done |
| Boards joined WiFi `<YOUR_SSID>`, mesh time-sync working | ✅ |
| RuView server | ✅ running **natively** on the Mac (not Docker — see "Why native") |
| Network path boards → server | ✅ proven |
| **Sustained CSI capture** | ✅ **FIXED** — yield 5–11 pps, server detects presence + vitals |

**RESOLVED.** Root cause was flashing the **display-enabled** 8MB build onto display-less
boards, which skips the RuView#893 MGMT→MGMT+DATA promiscuous-filter upgrade and starves the
CSI callback (`yield=0`). Fix: flash the **non-display 4MB build** (`esp32-csi-node-4mb.bin`,
built from `sdkconfig.defaults.4mb` with `CONFIG_DISPLAY_ENABLE` unset). `flash-node.sh` now
uses this build by default. Confirmed by maintainer in issue #954 (2026-06-08).

Remaining quality lever: **WiFi signal/placement.** Boards far from the AP (RSSI -85..-89)
yield only 1–4 pps and park in DEGRADED (state 8); a well-placed board (RSSI ~-78) yields ~11 pps.
Move boards closer to the router for reliable sensing.

---

## Hardware

3× ESP32-S3 (16 MB flash, 8 MB PSRAM, native USB-Serial/JTAG), display-less boards.

| Node | TDM slot | MAC |
|------|----------|-----|
| 0 | 0/3 | `<node-0-mac>` |
| 1 | 1/3 | `<node-1-mac>` |
| 2 | 2/3 | `<node-2-mac>` (the one kept on the Mac for console reads) |

- WiFi: SSID `<YOUR_SSID>` (2.4 GHz; creds in `.wifi.env`, perms 600).
- Aggregator (this Mac) LAN IP: **192.168.1.39**. Boards stream CSI to `192.168.1.39:5005/udp`.
- Boards got DHCP IPs in `192.168.1.x` (e.g. board 2 = 192.168.1.62), AP on **channel 1**.

## Key paths

- `flash-node.sh` — flash + provision one board. Usage: `./flash-node.sh <PORT> <NODE_ID> <TDM_SLOT>`
- `.wifi.env` — WiFi creds (sourced by flash-node.sh). **Not committed.**
- `.venv/` — Python venv with `esptool` 4.11 + `esp-idf-nvs-partition-gen`.
- `repo/` — sparse clone of github.com/ruvnet/RuView (`firmware/esp32-csi-node` + `v2`).
- `repo/v2/target/release/sensing-server` — natively built RuView server binary.
- `/tmp/sensing-server.log` — native server log.

## Firmware

- Used prebuilt bins: `repo/firmware/esp32-csi-node/release_bins/` (root = S3 v0.7.0).
- Flash offsets (8 MB S3): `bootloader@0x0`, `partition-table@0x8000`, `ota_data@0xf000`, `app@0x20000`.
- Also tested `release_bins/s3-adr110/` (same partition layout) — same yield=0 result.
- Provisioning writes NVS only (WiFi + aggregator IP + TDM slot + edge tier).
  No `--mesh-key` support in this build (despite docs), so nodes run as a plain TDM mesh.

### Reflash / reprovision one board (e.g. board on /dev/cu.usbmodemXXXX)
```bash
cd ~/code/presence/ruview
./flash-node.sh /dev/cu.usbmodem1101 <NODE_ID> <TDM_SLOT>
```
Notes:
- A *fresh* board needs manual download mode for the first flash: hold **BOOT**, tap **RESET/EN**,
  release BOOT (port re-enumerates, often to `/dev/cu.usbmodem1101`). After that the S3
  USB-JTAG lets esptool reset itself; no button needed.
- If "port is busy": a PlatformIO/serial monitor is holding it — `lsof /dev/cu.usbmodem*` then kill.

## RuView server (native — recommended on macOS)

### Why native instead of Docker
Docker here runs under **Colima (Apple VirtualizationFramework, NAT 192.168.5.x)**. Colima only
forwards published ports to the Mac's **loopback**, so ESP32 UDP hitting `192.168.1.39:5005`
never reaches the container. The native binary binds the Mac's LAN directly and works.
(Docker is fine for simulated mode / UI only.)

### Build (already done)
```bash
cd repo/v2 && cargo build --release -p wifi-densepose-sensing-server --bin sensing-server
```

### Control script (easiest): `./ruview.sh`
```bash
./ruview.sh start      # start (frictionless/loopback mode by default)
./ruview.sh stop       # stop
./ruview.sh restart    # stop + start
./ruview.sh status     # show pid + live /health + UI URL
./ruview.sh logs       # tail -f the server log
./ruview.sh ui         # open the dashboard in the browser
MODE=lan ./ruview.sh start   # LAN-exposed + bearer token instead of loopback
```

### Run — frictionless mode (what the script does by default: loopback UI, no token, full dashboard)
HTTP/WS bind to 127.0.0.1 so the whole UI works with no token and isn't exposed to the LAN.
The UDP CSI receiver always binds `0.0.0.0:5005` (hardcoded), so the boards still stream.
```bash
cd ~/code/presence/ruview
nohup repo/v2/target/release/sensing-server \
  --source esp32 --bind-addr 127.0.0.1 \
  --udp-port 5005 --http-port 3000 --ws-port 3001 \
  --ui-path ~/code/presence/ruview/repo/ui \
  > /tmp/sensing-server.log 2>&1 &
```
**Visualize:** open http://localhost:3000/ui/index.html (Sensing/Dashboard tabs are live).
The repo UI lives at `repo/ui/` — must pass `--ui-path` to it or the server serves 404s.

### Run — token-secured / LAN-exposed variant
Use only if you need the UI/API reachable from other machines. Requires the bearer token.
```bash
RUVIEW_API_TOKEN=<RUVIEW_API_TOKEN> \
  repo/v2/target/release/sensing-server \
  --source esp32 --bind-addr 0.0.0.0 \
  --udp-port 5005 --http-port 3000 --ws-port 3001 \
  --ui-path ~/code/presence/ruview/repo/ui \
  > /tmp/sensing-server.log 2>&1 &
```
- UI: http://localhost:3000/ui/index.html
- Health (no auth): `curl http://localhost:3000/health`
- API needs `Authorization: Bearer <RUVIEW_API_TOKEN>`.
- For simulated data instead, use `--source simulate`.
- Stop: `pkill -f sensing-server`. macOS firewall may prompt on first LAN bind — click Allow.

### API token
`RUVIEW_API_TOKEN = <RUVIEW_API_TOKEN>`
(Server refuses to expose live streams on 0.0.0.0 without a token unless
`RUVIEW_ALLOW_UNAUTHENTICATED=1` or bound to 127.0.0.1.)

---

## The yield=0 problem (RESOLVED — kept for reference)

**FIX (TL;DR):** flash the non-display 4MB build. The display-enabled 8MB build skips the
RuView#893 filter upgrade on display-less boards → `yield=0`. `flash-node.sh` now defaults to
the 4MB non-display build. After reflashing all 3 boards: yield 5–11 pps, server `source: esp32`,
presence + vitals detected. The detail below is the original investigation.

---



**Symptom:** boards associate to WiFi and mesh-sync fine, but the serial console shows
`adaptive_ctrl: ... yield=0pps` continuously. CSI capture produces ~0 frames/sec, so the
server stays at `source: esp32:offline` with only a trickle of frames.

**What we proved it is NOT:**
- Not the network: native server received real frames (valid RSSI/features) — path works.
- Not edge-gating: `yield=0` on both `--edge-tier 2` and `--edge-tier 0` (raw passthrough).
- Not one firmware build: same on root v0.7.0 and `s3-adr110`.
- Not reset type: same after soft reset and after physical power cycle.

**What it is:** a CSI-capture bug in the prebuilt firmware on **ESP32-S3**. The firmware uses
MGMT-only promiscuous (RuView#396) and is supposed to yield ~10 Hz from beacons + injected
probe requests, but yields ~0 on these display-less S3 boards. The repo's own release note
(`release_bins/version.txt`, RuView#893) says the "CSI yield 0pps fix" was
**"hardware-verified on ESP32-C6"** — not S3. Matches TROUBLESHOOTING.md §1 ("limping state").

**Observed pattern:** a brief burst of ~15 CSI frames at WiFi association (tick 0→17), then
capture dies and tick freezes. Frames trickle a few/min, far below the ~20 Hz needed.

### Things still worth trying (next session)
1. **Move boards closer to the router** — RSSI sank to -82…-88 (was -72). Weak signal starves
   CSI further. Do this regardless.
2. **ESP32-C6** — firmware verified working there (0→27 pps). Fastest path to live sensing.
   Use `release_bins/c6-adr110/` and `--chip esp32c6` in a flash command.
3. **Firmware watchdog**: fw 0.8.0+ adds a zero-CSI watchdog (auto-reset). Not in these bins.
4. **Rebuild firmware from source** (`repo/firmware/esp32-csi-node`, needs ESP-IDF) to enable
   sustained DATA-frame capture on S3 — heavy, uncertain since the fix is unverified on S3.
5. **File upstream issue** at github.com/ruvnet/RuView with the serial logs above.

## Sensing quality / testing (status: plumbing proven, discrimination noise-limited)

End-to-end pipeline is validated: all 3 nodes capture CSI, stream to the native server,
features compute, frame rate ~34/sec. **But presence discrimination is not reliable yet** —
an empty-vs-occupied A/B test showed presence pinned `True` in both phases and motion_power
*higher* when empty (243) than occupied (196). Root cause: weak signal (RSSI -80..-89) →
noisy CSI saturates the motion/presence detector, and the startup baseline calibration was
polluted (server calibrated while people/boards were moving).

### To get real presence detection (do these, then retest)
1. **Improve signal** (biggest lever): place each board within good range of the router,
   target **RSSI better than ~-70**. Spread them around the area so a person crosses the
   board↔board / board↔AP paths. Antennas in the clear, not against metal/walls.
2. **Clean baseline**: after repositioning, restart the server and keep the area **empty for
   ~40s** so the 30s field-model calibration (ADR-135 empty-room baseline) locks onto a true
   empty room. Then run the A/B test.

### Re-run the A/B test
```bash
# restart server fresh (clean baseline), keep room EMPTY ~40s first
pkill -f sensing-server; sleep 1
RUVIEW_API_TOKEN=<token> repo/v2/target/release/sensing-server \
  --source esp32 --bind-addr 0.0.0.0 --udp-port 5005 --http-port 3000 --ws-port 3001 \
  > /tmp/sensing-server.log 2>&1 &
# then poll /api/v1/sensing/latest empty vs occupied and compare motion_band_power + presence
```
A good result = occupied motion_power clearly > empty, and presence flips False→True when you
enter. With weak signal it won't; fix placement first.

## Raspberry Pi deployment (the recommended production target)

**Status:** validated — the sensing-server has been built and run on a 64-bit Raspberry Pi
(Pi 4 8GB) as a long-lived `systemd` unit (`ruview.service`, native build, not Docker), so it
survives reboots and runs headless 24/7. Give the Pi a reserved IP and point the boards at it
(see Step 1 / Step 3). Tip: prefer the Pi's IP over its `.local` mDNS name — mDNS resolution can
be flaky across the LAN.

**Why a Pi is better than the Mac here:** the macOS pain was Colima/Apple-VZ NAT dropping
ESP32 UDP. On a Pi (real Linux) Docker binds the host network directly, so UDP "just works"
with `--network host`. The official image is multi-arch (`linux/amd64` + `linux/arm64`), so a
64-bit Pi runs it directly. The Mac-built binary (`Mach-O arm64`) will NOT run on the Pi — use
the Docker image or a fresh Linux build.

**Requirements:** Raspberry Pi 4 or 5 (Pi 3 works but tighter), **64-bit Raspberry Pi OS**
(`uname -m` must say `aarch64`). 3 nodes is light load; Pi 5 if you later want heavy pose/NN.

### Step 1 — give the Pi a fixed IP
Reserve/static-assign an IP on your router, e.g. `192.168.1.50`. The boards stream to a fixed
target IP, so it must not change. (Below assumes `192.168.1.50` — substitute yours.)

### Step 2 (recommended) — run via Docker on the Pi
```bash
# on the Pi:
sudo apt update && sudo apt install -y docker.io
sudo usermod -aG docker $USER   # then log out/in
docker pull ruvnet/wifi-densepose:latest
docker run -d --name ruview --restart unless-stopped \
  --network host \
  -e CSI_SOURCE=esp32 \
  -e RUVIEW_API_TOKEN=$(openssl rand -hex 32) \
  ruvnet/wifi-densepose:latest
docker logs -f ruview          # watch it come up
```
- `--network host` gives UDP 5005 + HTTP 3000 + WS 3001 with no port-mapping fuss (Linux only).
- The image bundles its own UI → open `http://192.168.1.50:3000/ui/index.html`.
- `--restart unless-stopped` survives reboots (headless 24/7).
- Save the token it generates if you want API access (the live UI WS doesn't need it).
- Manage: `docker stop ruview` / `docker start ruview` / `docker rm -f ruview`.

### Step 2 (alternative) — native binary on the Pi
Two ways to get the Linux/arm64 binary:
- **Build on the Pi:** install Rust (`curl https://sh.rustup.rs -sSf | sh`), clone the repo,
  `cd v2 && cargo build --release -p wifi-densepose-sensing-server` (slow: tens of minutes; needs
  ~4GB RAM, so Pi 4 4GB+ / Pi 5). Then run like the Mac command in this file but `--bind-addr 0.0.0.0`.
- **Cross-compile from the Mac** (faster): ask Claude to build for `aarch64-unknown-linux-gnu`
  (needs `cross` or a linux-gnu linker), then `scp` the binary + the `repo/ui/` dir to the Pi.
  Run there with `--ui-path /path/to/ui`. `ruview.sh` can be adapted for the Pi.

### Step 3 — re-point the 3 boards at the Pi (REQUIRED)
Boards are currently provisioned to `192.168.1.39` (the Mac). Re-point each to the Pi's IP — this
is NVS-only, **no reflash needed**, just plug each board into USB on the Mac and run:
```bash
cd ~/code/presence/ruview
source .wifi.env
PORT=$(ls /dev/cu.usbmodem* | head -1)
# node 0 / slot 0 — repeat for node 1/slot 1 and node 2/slot 2, swapping boards:
.venv/bin/python repo/firmware/esp32-csi-node/provision.py --port "$PORT" --chip esp32s3 \
  --ssid "$RUVIEW_SSID" --password "$RUVIEW_PASS" \
  --target-ip 192.168.1.50 --node-id 0 --tdm-slot 0 --tdm-total 3
```
Or just edit `TARGET_IP` in `flash-node.sh` to the Pi's IP and re-run `./flash-node.sh <port> <node> <slot>`
for each board (that also reflashes the non-display firmware — harmless/idempotent).

### Step 4 — verify on the Pi
```bash
curl http://192.168.1.50:3000/health           # source should be "esp32", tick climbing
```
Same weak-signal caveat applies — place boards near the router for clean detection.

### Notes / gotchas
- 64-bit OS is mandatory for the arm64 image (`aarch64`). 32-bit Raspberry Pi OS won't pull it.
- If not using `--network host`, map ports explicitly: `-p 3000:3000 -p 3001:3001 -p 5005:5005/udp`.
- The Pi and boards must be on the same WiFi/LAN as before (`<YOUR_SSID>` / 192.168.1.x).
- Once the Pi works, you can stop the Mac server (`./ruview.sh stop`) and shut Colima (`colima stop`).

## Console / debugging cheatsheet
```bash
# Find the board port
ls /dev/cu.usbmodem*
# Read serial console (115200) — watch the 'yield=' field
.venv/bin/python -c "import serial,time; s=serial.Serial('/dev/cu.usbmodem1101',115200,timeout=1); t=time.time(); \
  [print(s.readline().decode('utf-8','replace').rstrip()) for _ in iter(lambda: time.time()<t+12, False)]"
# Confirm boards transmit UDP to the Mac (needs sudo)
sudo tcpdump -i en0 -n udp port 5005
# Server liveness
curl -s http://localhost:3000/health     # watch "tick" climb = frames arriving
```
