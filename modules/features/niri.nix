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

            case "''${1:-}" in
              desktop)
                niri msg output "$TV" off
                niri msg output "$DESKTOP" on
                ;;

              tv-gaming)
                niri msg output "$DESKTOP" off
                niri msg output "$TV" on

                sleep 1

                steam steam://open/bigpicture
                ;;

              extended)
                niri msg output "$DESKTOP" on
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
              mode = "3980x1600@75";
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
            "Shift+Mod+Space".spawn-sh = "1password --quick-access";

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
