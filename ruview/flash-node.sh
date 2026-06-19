#!/usr/bin/env bash
# Flash + provision one RuView ESP32-S3 CSI node.
# Usage: ./flash-node.sh <PORT> <NODE_ID> <TDM_SLOT>
# Reads WiFi creds from env: RUVIEW_SSID, RUVIEW_PASS (or from ./.wifi.env).
# Aggregator target IP defaults below; override with TARGET_IP env.
set -euo pipefail

PORT="${1:?usage: flash-node.sh <PORT> <NODE_ID> <TDM_SLOT>}"
NODE_ID="${2:?node id 0-255}"
TDM_SLOT="${3:?tdm slot 0-based}"
TDM_TOTAL=3
TARGET_IP="${TARGET_IP:-192.168.1.39}"   # aggregator (server) LAN IP — override via env
CHIP="esp32s3"

# Resolve repo root from this script's location (no hardcoded paths).
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY="$ROOT/.venv/bin/python"
FW="$ROOT/repo/firmware/esp32-csi-node"
BINS="$FW/release_bins"

# Load WiFi creds from file if present (keeps them off the command line)
[ -f "$ROOT/.wifi.env" ] && source "$ROOT/.wifi.env"
: "${RUVIEW_SSID:?set RUVIEW_SSID (or create $ROOT/.wifi.env)}"
: "${RUVIEW_PASS:?set RUVIEW_PASS (or create $ROOT/.wifi.env)}"

echo "=== Node $NODE_ID (slot $TDM_SLOT/$TDM_TOTAL) on $PORT ==="

# 0. Preflight: confirm the board is reachable in DOWNLOAD mode
echo "--- connecting (board must be in DOWNLOAD mode: hold BOOT, tap RESET, release BOOT) ---"
INFO=$("$PY" -m esptool --chip "$CHIP" --port "$PORT" flash_id 2>&1) || true
if ! grep -qi "Detected flash size" <<<"$INFO"; then
  echo "!! Could not connect to the board in download mode."
  echo "$INFO" | grep -iE 'fatal|no serial|busy|could not' | head -3
  echo ">> Put the board in download mode and rerun this command."
  exit 1
fi

# 1. Pick 4MB vs 8MB images from detected flash size
FSIZE=$(grep -i "Detected flash size" <<<"$INFO" | awk '{print $NF}')
echo "flash size: ${FSIZE:-unknown}"

# Always use the NON-DISPLAY 4MB build. The display-enabled 8MB build skips the
# RuView#893 MGMT->MGMT+DATA promiscuous-filter upgrade, which starves the CSI
# callback (yield=0pps) on display-less boards. The 4MB build (built from
# sdkconfig.defaults.4mb, CONFIG_DISPLAY_ENABLE unset) triggers the upgrade and
# yields ~5-9 pps. A 4MB image runs fine on 8/16MB boards. See SETUP-NOTES.md.
APP="$BINS/esp32-csi-node-4mb.bin"; PART="$BINS/partition-table-4mb.bin"; FS=4MB

# 2. Flash firmware (offsets per partitions_4mb.csv)
echo "--- flashing NON-DISPLAY firmware ($FS) ---"
# --after no_reset keeps the board in download mode so provisioning can
# write NVS in the same session (no second BOOT/RESET needed).
"$PY" -m esptool --chip "$CHIP" --port "$PORT" --baud 460800 --after no_reset \
  write_flash --flash_mode dio --flash_size "$FS" \
  0x0     "$BINS/bootloader.bin" \
  0x8000  "$PART" \
  0xf000  "$BINS/ota_data_initial.bin" \
  0x20000 "$APP"

# 3. Provision WiFi + aggregator + TDM slot into NVS
echo "--- provisioning NVS ---"
"$PY" "$FW/provision.py" --port "$PORT" --chip "$CHIP" \
  --ssid "$RUVIEW_SSID" --password "$RUVIEW_PASS" \
  --target-ip "$TARGET_IP" \
  --node-id "$NODE_ID" --tdm-slot "$TDM_SLOT" --tdm-total "$TDM_TOTAL"

echo "=== Node $NODE_ID done. Unplug and connect the next board. ==="
