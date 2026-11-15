#!/usr/bin/env bash
# fix-bt-bond.sh — repair Bluetooth bonds for gamepads (DualShock 4 etc.)
#
# Symptom: controller pairs ("Pairing successful") but is not actually bonded
# (no [LinkKey] in /var/lib/bluetooth/<adapter>/<dev>/info). The controller
# connects for a moment, then gets rejected and powers off. bluetoothd logs:
#   "Rejected connection from !bonded device ..."
# Kernel/root cause: when an unbonded controller initiates the connection,
# the kernel bonds on its own with Store hint: No, so BlueZ discards the link
# key. The key can be recovered from an `btmon` capture and injected manually.
#
# Usage:
#   sudo ./fix-bt-bond.sh <MAC>      e.g. sudo ./fix-bt-bond.sh D0:27:88:57:54:3F
#
# Steps it performs:
#   1. starts btmon in the background
#   2. waits for you to pair the device (bluetoothctl pair <MAC>) — you do this
#      in a second terminal, or it attempts it automatically
#   3. extracts the newest "Link key[16]" hex dump from the btmon capture
#   4. appends a [LinkKey] section to the device info file
#   5. restarts bluetooth.service
# Then press the PS button — the controller should connect and stay connected.

set -euo pipefail

MAC="${1:?Usage: sudo $0 <MAC> (e.g. D0:27:88:57:54:3F)}"
CAPTURE="$(mktemp /tmp/btmon-capture.XXXX.log)"
trap 'rm -f "$CAPTURE"' EXIT

ADAPTER_DIR=""
for d in /var/lib/bluetooth/*/; do
    if [ -d "$d${MAC}" ]; then ADAPTER_DIR="$d${MAC}"; fi
done
[ -n "$ADAPTER_DIR" ] || { echo "No storage dir for $MAC yet — pair once first so the device object exists."; exit 1; }
INFO="$ADAPTER_DIR/info"

echo ">> Capturing HCI traffic with btmon (leave this terminal open)..."
btmon > "$CAPTURE" 2>&1 &
BTMON_PID=$!

echo ">> Now pair the device:"
echo "   - put the controller in pairing mode (PS + Share until white flashes)"
echo "   - run:  bluetoothctl pair $MAC"
echo "   (or press the PS button to let it connect; either way a link key"
echo "    notification will appear in the capture)"
read -rp "Press Enter once pairing reported success..."

kill "$BTMON_PID" 2>/dev/null || true
wait "$BTMON_PID" 2>/dev/null || true

# Extract the LAST link key notification from the capture (the newest bond):
# scan forward, keep the most recent 16-byte hex line following a
# "Link key[16]:" marker. The hex line looks like:
#   "  13 d0 ... 44 0f  ..Y...JD."  (hex bytes, whitespace, then ASCII art)
KEY_HEX=$(awk '
    /MGMT Event: New Link Key/ {pending=1; next}
    pending && /Key type:/ {ktype=$0; sub(/.*\(/,"",ktype); sub(/\).*/,"",ktype); next}
    /Link key\[16\]:/ {f=1; buf=""; next}
    f && /^[[:space:]]*[0-9a-f]{2}( [0-9a-f]{2}){3}/ {line=$0; gsub(/[[:space:]]/,"",line); buf=substr(line,1,32); f=0; pending=0; k=buf; t=ktype}
    END {print k "\n" t}
' "$CAPTURE")
KEY_HEX=$(echo "$KEY_HEX" | sed -n 1p)
TYPE_NUM=$(echo "$KEY_HEX" | sed -n 2p)
[ -n "$KEY_HEX" ] || { echo "!! No link key found in capture. Did pairing happen while btmon ran?"; exit 1; }
[ ${#KEY_HEX} -eq 32 ] || { echo "!! Could not parse a full 16-byte key (got '$KEY_HEX'). Inspect $CAPTURE manually."; exit 1; }
TYPE_NUM=${TYPE_NUM#0x}
TYPE_NUM=${TYPE_NUM:-4}

if grep -q '^\[LinkKey\]' "$INFO"; then
    echo ">> $INFO already has a [LinkKey] section — removing the old one first."
    sed -i '/^\[LinkKey\]/,/^$/d' "$INFO"
fi

echo ">> Appending link key (type $TYPE_NUM) to $INFO"
cat >> "$INFO" <<EOF

[LinkKey]
Key=${KEY_HEX^^}
Type=${TYPE_NUM#0x}
PINLength=0
EOF

echo ">> Restarting bluetooth.service"
systemctl restart bluetooth.service

echo
echo ">> Done. Press the PS button on the controller now — the light bar"
echo "   should turn blue and /dev/input/js* should show 'Wireless Controller'."
echo "   Verify with:  cat /sys/class/input/js*/device/name"
