# presence

A small collection of presence-detection experiments.

## `ruview/` — WiFi-CSI presence sensing (ESP32-S3 + RuView)

My setup and tooling for running [RuView / WiFi-DensePose](https://github.com/ruvnet/RuView)
with 3× ESP32-S3 CSI sensing nodes streaming to a local server. This directory holds **only my
wrapper scripts and notes** — not the upstream project itself.

- `SETUP-NOTES.md` — full writeup: hardware, flashing, the yield=0 fix, native vs Docker, Pi deploy.
- `FINDINGS.md` — ⚠️ why the pose/skeleton is synthetic (arms never move) — read before chasing a "pose bug".
- `flash-node.sh` — flash + provision one ESP32-S3 node.
- `ruview.sh` — start/stop/status the sensing server.
- `*.example` — templates for the gitignored secrets (`.wifi.env`, `nvs_config.csv`).

**Setup:**
```bash
cd ruview
git clone https://github.com/ruvnet/RuView.git repo   # upstream (gitignored)
cp .wifi.env.example .wifi.env && chmod 600 .wifi.env  # then edit creds
python3 -m venv .venv && .venv/bin/pip install esptool esp-idf-nvs-partition-gen
# build the server per repo/ docs, then:
./flash-node.sh <PORT> <NODE_ID> <TDM_SLOT>
./ruview.sh start
```

## `ble/` — BLE proximity presence (legacy)

An early Node.js BLE experiment: scans for a phone's advertisement and posts `in`/`out` to a
service based on RSSI threshold. Uses `noble` + `request`. Kept for reference / future revival.

```bash
cd ble && npm install && node main.js
```
