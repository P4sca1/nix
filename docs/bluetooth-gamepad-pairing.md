# Bluetooth gamepad (DualShock 4) pairing bug — root cause & fix

## Symptom

A Bluetooth gamepad (observed with a Sony DualShock 4, `VID 054C PID 05C4`,
but this affects any BR/EDR classic HID device) pairs successfully, the light
bar flashes, then it turns itself off after a few seconds. bluetoothd logs:

```
profiles/input/device.c:hidp_add_connection() Rejected connection from !bonded device /org/bluez/hci1/dev_XX_XX_...
```

`bluetoothctl info <MAC>` eventually shows `Paired: no`, and
`/var/lib/bluetooth/<adapter-MAC>/<device-MAC>/info` contains **no
`[LinkKey]` section** — even though pairing reported success.

## Root cause

When an *unbonded* controller initiates the connection itself (e.g. you press
the PS button), the kernel performs the pairing internally and emits the link
key to bluetoothd with **`Store hint: No`** (visible in `btmon`:

```
@ MGMT Event: New Link Key (0x0009)
        Store hint: No (0x00)
```

). BlueZ therefore never persists the `[LinkKey]`. Every subsequent
connection is rejected as "not bonded", the controller gives up and powers
off. Re-pairing loops forever because each new pairing is again
kernel-initiated (the controller is still unbonded and keeps auto-connecting).

Red herrings we ruled out on this machine (pascal-pc, NixOS):
- `bluetooth.disable_ertm=1` (toggled, no effect)
- the flaky onboard Bluetooth adapter `hci0` (fails with it blocked, too)
- `ds4drv` (obsolete; kernel `hid_playstation` works fine once bonded)

## One-off manual fix

1. Capture the pairing with `sudo btmon | tee /tmp/btmon.log` running in
   another terminal, and pair the device (`bluetoothctl pair <MAC>`).
2. Find the last `Link key[16]:` block in the capture and note the 16 bytes.
3. Append to `/var/lib/bluetooth/<adapter>/<device>/info`:

   ```
   [LinkKey]
   Key=<32 hex chars, uppercase>
   Type=4
   PINLength=0
   ```

   (`Type=4` = "Unauthenticated Combination key from P-192", what the DS4 uses;
   `btmon` prints the exact type in `Key type: ...`.)
4. `sudo systemctl restart bluetooth`, then press the PS button. The light bar
   turns solid blue and `/sys/class/input/js*/device/name` shows
   `Wireless Controller`.

## Automated fix

`scripts/fix-bt-bond.sh <MAC>` automates all of the above (capture, key
extraction, storage injection, service restart). Run it as root.

## Upstream references

- bluez#642 — "DualShock 4 controller doesn't stay connected until the
  bluetooth service is reloaded":
  https://github.com/bluez/bluez/issues/642 (same symptom, closed stale, unfixed)
- Arch forum (solved): "PS4 Dualshock controller does not connect using
  bluetooth" — the `ClassicBondedOnly=false` in input.conf workaround:
  https://bbs.archlinux.org/viewtopic.php?id=292399
- Kernel regression reports affecting DS4/DualSense BT connects in specific
  kernel versions: https://bbs.archlinux.org/viewtopic.php?id=305211

## Persistent config on this machine

`modules/hosts/pascal-pc/hardware.nix` sets
`hardware.bluetooth.input.General.ClassicBondedOnly = false` (writes
`ClassicBondedOnly=false` to `/etc/bluetooth/input.conf`), which stops BlueZ
from rejecting the controller's HID connection while bonding is incomplete —
breaking the loop for future pairings. Minor security tradeoff: classic HID
devices may connect without being bonded (relevant mostly in hostile RF
environments; the DS4 itself does not support stricter modes well).

## Pairing new controllers in the future

Always pair in this order to *avoid* the bug:

1. Make sure the controller is **off / asleep** before you start (hold PS
   until the light is off), so it cannot auto-connect while unbonded.
2. `bluetoothctl scan on`, find its MAC, `bluetoothctl trust <MAC>`.
3. Put it into pairing mode (DS4: hold **PS + Share** until the light bar
   double-flashes white) and run `bluetoothctl pair <MAC>` **quickly** — a
   userspace-initiated pairing stores the link key correctly with
   `Store hint: Yes`.
4. If it still ends up unbonded (check `sudo cat
   /var/lib/bluetooth/<adapter>/<dev>/info` for `[LinkKey]`), run
   `scripts/fix-bt-bond.sh <MAC>`.
