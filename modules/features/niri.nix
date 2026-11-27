{
  inputs,
  self,
  ...
}:
{
  flake.nixosModules.niri =
    { pkgs, ... }:
    {
      programs.niri = {
        enable = true;
        package = self.packages.${pkgs.stdenv.hostPlatform.system}.niri;
        useNautilus = true;
      };

      services.displayManager.sddm.enable = true;
      services.displayManager.sddm.wayland.enable = true;
      services.displayManager.sddm.extraPackages = [ pkgs.sddm-astronaut ];
      services.displayManager.sddm.theme = "sddm-astronaut-theme";

      services.displayManager.defaultSession = "niri";

      environment.systemPackages =
        let
          displayMode = pkgs.writeShellScriptBin "display-mode" ''
            set -euo pipefail

            TV="HDMI-A-1"
            DESKTOP="DP-1"
            # Seconds to wait for the TV to show up before giving up.
            TV_TIMEOUT=10

            notify() {
              echo "display-mode: $*" >&2
              ${pkgs.libnotify}/bin/notify-send -a display-mode "display-mode" "$*" 2>/dev/null || true
            }

            # The kernel cmdline keeps the TV connector forced off
            # (video=HDMI-A-1:d) so SDDM stays on the monitor. A forced-off
            # connector always reports "disconnected", so niri can never
            # enable it. Writing "detect"/"off" to the DRM status attribute
            # lifts/restores that force (write access via udev rule).
            tv_force() {
              local f
              for f in /sys/class/drm/card*-"$TV"/status; do
                if [ -w "$f" ]; then echo "$1" > "$f" || true; fi
              done
            }

            # niri only lists connected outputs in its JSON.
            tv_connected() {
              niri msg --json outputs | jq -e --arg tv "$TV" 'has($tv)' >/dev/null
            }

            tv_active() {
              niri msg --json outputs | jq -e --arg tv "$TV" '.[$tv].current_mode != null' >/dev/null
            }

            PACTL="${pkgs.pulseaudio}/bin/pactl"
            # Default sink before tv-gaming, restored by `desktop`.
            SINK_STATE="''${XDG_RUNTIME_DIR:-/tmp}/display-mode.sink"

            # The GPU's HDMI/DP audio card has one profile per connector and
            # only one can be active. WirePlumber keeps the one it picked at
            # login (the monitor's DP audio) when the TV shows up, so the
            # "HDMI" sink kept pointing at the monitor until pipewire was
            # restarted. Find the card port whose ELD names the TV (same
            # model name niri reports) and activate that profile explicitly.
            tv_audio() {
              local model="" sel="" card profile sink
              model=$(niri msg --json outputs | jq -r --arg tv "$TV" '.[$tv].model // empty')
              [ -n "$model" ] || return 1
              for _ in $(seq 1 10); do
                sel=$(LC_ALL=C "$PACTL" --format=json list cards 2>/dev/null | jq -r --arg m "$model" '
                  def norm: ascii_downcase | gsub("^\\s+|\\s+$"; "");
                  [.[] as $c | $c.ports | to_entries[]
                   | select((.value.properties["device.product.name"] // "" | norm) == ($m | norm))
                   | "\($c.name) \(.value.profiles[0])"][0] // empty')
                [ -n "$sel" ] && break
                sleep 1
              done
              [ -n "$sel" ] || return 1
              card=''${sel% *}
              profile=''${sel#* }
              "$PACTL" set-card-profile "$card" "$profile"
              sink="alsa_output.''${card#alsa_card.}.''${profile#output:}"
              for _ in $(seq 1 10); do
                if "$PACTL" set-default-sink "$sink" 2>/dev/null; then return 0; fi
                sleep 0.5
              done
              return 1
            }

            case "''${1:-}" in
              desktop)
                # Monitor first, so there is never a moment without picture.
                niri msg output "$DESKTOP" on
                niri msg output "$TV" off
                tv_force off
                if [ -s "$SINK_STATE" ]; then
                  "$PACTL" set-default-sink "$(cat "$SINK_STATE")" || true
                  rm -f "$SINK_STATE"
                fi
                ;;

              tv-gaming)
                tv_force detect
                for _ in $(seq 1 "$TV_TIMEOUT"); do
                  tv_connected && break
                  sleep 1
                done
                if ! tv_connected; then
                  notify "TV ($TV) not connected - switched on, right input? Staying on $DESKTOP."
                  tv_force off
                  exit 1
                fi

                # Enable the TV first; turn the monitor off only once the TV
                # actually has a mode, otherwise roll back.
                niri msg output "$TV" on
                for _ in $(seq 1 5); do
                  tv_active && break
                  sleep 1
                done
                if ! tv_active; then
                  notify "TV ($TV) did not come up. Staying on $DESKTOP."
                  niri msg output "$TV" off
                  tv_force off
                  exit 1
                fi
                niri msg output "$DESKTOP" off

                sleep 1

                # Route audio to the TV.
                [ -s "$SINK_STATE" ] || "$PACTL" get-default-sink > "$SINK_STATE" 2>/dev/null || true
                if ! tv_audio; then
                  # Last resort, the same thing that helped manually.
                  systemctl --user restart wireplumber || true
                  sleep 3
                  tv_audio || notify "No audio sink for the TV found - audio stays on $("$PACTL" get-default-sink 2>/dev/null)."
                fi

                steam steam://open/bigpicture

                # The Big Picture window opens with the title "Steam" and is
                # only renamed to "Steam Big Picture Mode" (German:
                # "Big-Picture-Modus") later, so open-fullscreen window rules
                # never match it. A cold Steam start (updates, login) easily
                # takes longer than 30 s, so wait up to 2 min, then fullscreen
                # it. fullscreen-window toggles and niri's JSON has no
                # fullscreen flag, so judge by size: only toggle while the
                # window is smaller than the TV, and stop once it stays at
                # least TV-sized for a few seconds.
                read -r TV_W TV_H < <(niri msg --json outputs | jq -r --arg tv "$TV" '.[$tv].logical | "\(.width) \(.height)"')
                stable=0
                toggles=0
                for _ in $(seq 1 120); do
                  read -r BP_ID BP_W BP_H < <(niri msg --json windows 2>/dev/null | jq -r '
                    [.[] | select(.title | test("Big.Picture"))][0]
                    | if . then "\(.id) \(.layout.window_size[0]) \(.layout.window_size[1])" else "" end') || true
                  if [ -n "''${BP_ID:-}" ]; then
                    if [ "$BP_W" -ge "$TV_W" ] && [ "$BP_H" -ge "$TV_H" ]; then
                      stable=$((stable + 1))
                      [ "$stable" -ge 3 ] && break
                    elif [ "$toggles" -lt 3 ]; then
                      stable=0
                      toggles=$((toggles + 1))
                      niri msg action fullscreen-window --id "$BP_ID"
                    fi
                  fi
                  sleep 1
                done
                [ "$stable" -ge 3 ] || notify "Could not put Steam Big Picture into fullscreen."
                ;;

              extended)
                niri msg output "$DESKTOP" on
                tv_force detect
                sleep 2
                tv_connected || notify "TV ($TV) not connected."
                niri msg output "$TV" on
                ;;

              *)
                echo "Usage: display-mode {desktop|tv-gaming|extended}"
                exit 1
                ;;
            esac
          '';
        in
        [
          pkgs.ddcutil
          pkgs.feh
          pkgs.mission-center
          pkgs.nautilus
          pkgs.sddm-astronaut
          pkgs.xwayland-satellite # https://niri-wm.github.io/niri/Xwayland.html
          displayMode
        ];

      # https://docs.noctalia.dev/v4/getting-started/nixos/
      security.polkit.enable = true;

      # Niri doesn't ship a polkit authentication agent; without one, apps like
      # 1Password report that system authentication (unlock with system
      # credentials) is "not supported in this environment".
      systemd.user.services.polkit-gnome-authentication-agent-1 = {
        description = "polkit-gnome Authentication Agent";
        wantedBy = [ "graphical-session.target" ];
        wants = [ "graphical-session.target" ];
        after = [ "graphical-session.target" ];
        serviceConfig = {
          ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
          Restart = "on-failure";
          RestartSec = 1;
          TimeoutStopSec = 10;
        };
      };
      services.power-profiles-daemon.enable = true;
      services.upower.enable = true;

      xdg.portal = {
        enable = true;
        extraPortals = [ pkgs.xdg-desktop-portal-gtk ]; # Fixes OpenURI and cursor themes in flatpaks
      };
    };

  perSystem =
    {
      self',
      pkgs,
      lib,
      ...
    }:
    {
      packages.niri = inputs.wrapper-modules.wrappers.niri.wrap {
        inherit pkgs;
        settings = {
          spawn-at-startup = [
            (lib.getExe self'.packages.noctalia)
            "1password --silent"
          ];

          xwayland-satellite.path = lib.getExe pkgs.xwayland-satellite;

          window-rule = {
            # Rounded corners for a modern look.
            geometry-corner-radius = 20;
            # Clips window contents to the rounded corner boundaries.
            clip-to-geometry = true;
          };

          window-rules = [
            {
              # Steam games (app-id steam_app_<id>) open fullscreen.
              matches = [
                {
                  app-id = _: {
                    custom = ''r#"^steam_app_[0-9]+$"#'';
                  };
                }
              ];
              open-fullscreen = true;
            }
          ];

          # Honor xdg-activation requests even with invalid serials, so
          # single-instance apps (browser opened via a link, launcher opening
          # an already-running app) raise and focus their existing window
          # instead of only being marked urgent.
          debug = {
            honor-xdg-activation-with-invalid-serial = true;
          };

          cursor = {
            hide-when-typing = false;
          };

          input = {
            mod-key = "Alt";
            keyboard = {
              xkb.layout = "eu";
              repeat-delay = 500;
              repeat-rate = 50;
            };
            mouse = {
              natural-scroll = { };
              accel-speed = 0.0;
              accel-profile = "flat"; # disable pointer acceleration
              scroll-factor = 1.0;
            };
          };

          layout = {
            gaps = 5;
            focus-ring = {
              width = 2;
              active-color = "#7daea3";
            };
          };

          outputs = {
            "DP-1" = {
              focus-at-startup = { };
              mode = "3840x1600@75";
            };
            "HDMI-A-1" = {
              off = { };
              mode = "1920x1080@60";
            };
          };

          binds = {
            # Misc
            "Mod+Return".spawn-sh = lib.getExe pkgs.alacritty;
            "Mod+Space".spawn-sh = "${lib.getExe self'.packages.noctalia} ipc call launcher toggle";
            "Control+Mod+Q".spawn-sh = "${lib.getExe self'.packages.noctalia} ipc call lockScreen lock";
            "Mod+Comma".spawn-sh = "${lib.getExe self'.packages.noctalia} ipc call settings toggle";
            "Mod+Q".close-window = { };
            "Mod+Shift+Slash".show-hotkey-overlay = { };
            # 1Password Quick Access, matching the new macOS default
            # (Option+Cmd+Backslash, changed due to a conflict with macOS
            # Golden Gate's Visual Intelligence / Siri shortcut).
            # macOS Option -> Alt (Mod), Command -> Ctrl on Linux.
            "Mod+Control+Backslash".spawn-sh = "1password --quick-access";

            # Screenshots
            "Print".screenshot = { };
            "Ctrl+Print".screenshot-screen = { };
            "Mod+Print".screenshot-window = { };

            # Layout / Window management
            "Mod+F".maximize-column = { };
            "Mod+G".fullscreen-window = { };
            "Mod+Shift+F".toggle-window-floating = { };
            "Mod+C".center-column = { };

            "Mod+H".focus-column-left = { };
            "Mod+L".focus-column-right = { };
            "Mod+K".focus-window-up = { };
            "Mod+J".focus-window-down = { };

            "Mod+Left".focus-column-left = { };
            "Mod+Right".focus-column-right = { };
            "Mod+Up".focus-window-up = { };
            "Mod+Down".focus-window-down = { };

            "Mod+Shift+H".move-column-left = { };
            "Mod+Shift+L".move-column-right = { };
            "Mod+Shift+K".move-window-up = { };
            "Mod+Shift+J".move-window-down = { };

            "Mod+1".focus-workspace = "w0";
            "Mod+2".focus-workspace = "w1";
            "Mod+3".focus-workspace = "w2";
            "Mod+4".focus-workspace = "w3";
            "Mod+5".focus-workspace = "w4";
            "Mod+6".focus-workspace = "w5";
            "Mod+7".focus-workspace = "w6";
            "Mod+8".focus-workspace = "w7";
            "Mod+9".focus-workspace = "w8";
            "Mod+0".focus-workspace = "w9";

            "Mod+Shift+1".move-column-to-workspace = "w0";
            "Mod+Shift+2".move-column-to-workspace = "w1";
            "Mod+Shift+3".move-column-to-workspace = "w2";
            "Mod+Shift+4".move-column-to-workspace = "w3";
            "Mod+Shift+5".move-column-to-workspace = "w4";
            "Mod+Shift+6".move-column-to-workspace = "w5";
            "Mod+Shift+7".move-column-to-workspace = "w6";
            "Mod+Shift+8".move-column-to-workspace = "w7";
            "Mod+Shift+9".move-column-to-workspace = "w8";
            "Mod+Shift+0".move-column-to-workspace = "w9";

            "Mod+Ctrl+H".set-column-width = "-5%";
            "Mod+Ctrl+L".set-column-width = "+5%";
            "Mod+Ctrl+J".set-window-height = "-5%";
            "Mod+Ctrl+K".set-window-height = "+5%";

            "Mod+WheelScrollDown".focus-column-left = { };
            "Mod+WheelScrollUp".focus-column-right = { };
            "Mod+Ctrl+WheelScrollDown".focus-workspace-down = { };
            "Mod+Ctrl+WheelScrollUp".focus-workspace-up = { };

            "Ctrl+Up".toggle-overview = { };

            # Audio & Brightness
            "XF86AudioRaiseVolume".spawn-sh = "${lib.getExe self'.packages.noctalia} ipc call volume increase";
            "XF86AudioLowerVolume".spawn-sh = "${lib.getExe self'.packages.noctalia} ipc call volume decrease";
            "XF86AudioMute".spawn-sh = "${lib.getExe self'.packages.noctalia} ipc call volume muteOutput";
            "XF86MonBrightnessUp".spawn-sh = "${lib.getExe pkgs.ddcutil} setvcp 10 + 5";
            "XF86MonBrightnessDown".spawn-sh = "${lib.getExe pkgs.ddcutil} setvcp 10 - 5";
          };
        };
      };
    };
}
