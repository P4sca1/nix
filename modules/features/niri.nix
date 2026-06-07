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
      services.displayManager.sddm.extraPackages =
        let
          basePath = "$out/share/sddm/themes/sddm-noctalia-theme";
          sddmNoctaliaTheme = pkgs.stdenvNoCC.mkDerivation {
            pname = "sddm-noctalia";
            version = "0.0.0";

            src = pkgs.fetchFromGitHub {
              owner = "mahaveergurjar";
              repo = "sddm";
              rev = "40012eecd7f8be7ff4c3ae02241e5f58d28f82f6";
              sha256 = "sha256-e/gYI6znHXxlDCOVh4p265x3kO0nQUU897hCY1yEz88=";
            };

            dontWrapQtApps = true;
            propagatedBuildInputs = with pkgs.kdePackages; [
              # avoid .dev outputs propagation
              qtsvg.out
              qtmultimedia.out
              qtvirtualkeyboard.out
            ];

            installPhase = ''
              mkdir -p ${basePath}
              cp -r $src/* ${basePath}
            '';
          };
        in
        [ sddmNoctaliaTheme ];
      services.displayManager.sddm.theme = "sddm-noctalia-theme";

      services.displayManager.defaultSession = "niri";

      # Enable the X11 windowing system to support programs such as Steam and some games.
      services.xserver.enable = true;
      # Configure keymap in X11
      services.xserver.xkb = {
        layout = "eu";
      };

      environment.systemPackages = with pkgs; [
        ddcutil
        mission-center
        nautilus
        xwayland-satellite # https://niri-wm.github.io/niri/Xwayland.html
      ];

      # https://docs.noctalia.dev/v4/getting-started/nixos/
      security.polkit.enable = true;
      services.power-profiles-daemon.enable = true;
      services.upower.enable = true;

      security.rtkit.enable = true;
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
              natural-scroll = true;
              accel-speed = 0.0;
              accel-profile = "flat"; # disable pointer acceleration
              scroll-factor = {
                vertical = 1.0;
                horizontal = 1.0;
              };
            };
          };

          layout.gaps = 5;

          binds = {
            # Misc
            "Mod+Return".spawn-sh = lib.getExe pkgs.alacritty;
            "Mod+Space".spawn-sh = "${lib.getExe self'.packages.noctalia} ipc call launcher toggle";
            "Control+Mod+Q".spawn-sh = "${lib.getExe self'.packages.noctalia} ipc call lockScreen lock";
            "Mod+Comma".spawn-sh = "${lib.getExe self'.packages.noctalia} ipc call settings toggle";
            "Mod+Q".close-window = { };

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

            # Audio & Brightness
            "XF86AudioRaiseVolume".spawn-sh = "${lib.getExe self'.packages.noctalia} ipc call volume increase";
            "XF86AudioLowerVolume".spawn-sh = "${lib.getExe self'.packages.noctalia} ipc call volume decrease";
            "XF86AudioMute".spawn-sh = "${lib.getExe self'.packages.noctalia} ipc call volume muteOutput";
            "XF86MonBrightnessUp".spawn-sh =
              "${lib.getExe self'.packages.noctalia} ipc call brightness increase";
            "XF86MonBrightnessDown".spawn-sh =
              "${lib.getExe self'.packages.noctalia} ipc call brightness decrease";
          };
        };
      };
    };
}
