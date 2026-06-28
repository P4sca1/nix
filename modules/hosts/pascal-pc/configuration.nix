{ self, inputs, ... }:
{
  flake.nixosConfigurations.pascal-pc = inputs.nixpkgs.lib.nixosSystem {
    specialArgs = {
      inherit inputs;
      hostPlatform = "x86_64-linux";
    };

    modules = [
      self.nixosModules.pascal-pc
      self.nixosModules.pascal-pc-hardware
      self.nixosModules.home-manager
      self.nixosModules.niri
      inputs.nix-flatpak.nixosModules.nix-flatpak
      inputs.nur.modules.nixos.default
      self.nixosModules.sops
      self.nixosModules.hermes-agent
    ];
  };

  flake.nixosModules.pascal-pc =
    { pkgs, ... }:
    let
      pkgsUnstable = import inputs.nixpkgs-unstable { system = pkgs.stdenv.hostPlatform.system; };
    in
    {
      # Bootloader.
      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;

      # Use latest kernel.
      boot.kernelPackages = pkgs.linuxPackages_latest;

      boot.kernelModules = [
        # ntsync is a kernel driver that mimics Windows synchronization mechanisms, significantly improving performance
        # for running Windows applications, especially games, through compatibility layers like Wine and Proton
        "ntsync"
      ];

      networking.hostName = "pascal-pc";
      networking.wireless.enable = true;
      networking.networkmanager.enable = true;
      networking.nftables.enable = true;

      # Configure DNS
      networking.nameservers = ["192.168.178.1"]; # Fritz Box which routes to AdGuard Home
      # netbird requires resolved
      services.resolved.enable = true;

      time.timeZone = "Europe/Berlin";

      i18n.defaultLocale = "de_DE.UTF-8";
      i18n.extraLocaleSettings = {
        LC_ADDRESS = "de_DE.UTF-8";
        LC_IDENTIFICATION = "de_DE.UTF-8";
        LC_MEASUREMENT = "de_DE.UTF-8";
        LC_MONETARY = "de_DE.UTF-8";
        LC_NAME = "de_DE.UTF-8";
        LC_NUMERIC = "de_DE.UTF-8";
        LC_PAPER = "de_DE.UTF-8";
        LC_TELEPHONE = "de_DE.UTF-8";
        LC_TIME = "de_DE.UTF-8";
      };

      # Enable CUPS to print documents.
      services.printing.enable = true;

      # Enable sound with pipewire.
      services.pulseaudio.enable = false;
      security.rtkit.enable = true;
      services.pipewire = {
        enable = true;
        alsa.enable = true;
        alsa.support32Bit = true;
        pulse.enable = true;
        jack.enable = true;
      };

      fonts.fontconfig.defaultFonts = {
        monospace = [
          "JetBrains Mono"
          "Noto Sans Mono"
        ];
        sansSerif = [ "Noto Sans" ];
        serif = [ "Noto Serif" ];
      };
      fonts.packages = [
        pkgs.nerd-fonts.jetbrains-mono
      ];

      # Necessary for using flakes on this system.
      nix.settings.experimental-features = "nix-command flakes";
      nix.settings.trusted-users = [ "pascal" ];
      nix.gc.automatic = true;

      home-manager.users.pascal = self.homeModules.pascal;

      # Define a user account. Don't forget to set a password with ‘passwd’.
      users.users.pascal = {
        isNormalUser = true;
        description = "Pascal Sthamer";
        extraGroups = [
          "netbird-personal"
          "networkmanager"
          "wheel"
          "gamemode" # https://wiki.nixos.org/wiki/GameMode
          "i2c" # https://www.ddcutil.com/i2c_permissions_using_group_i2c/
          "input"
          "kvm" # required by docker-sbx for VM sandboxing
          "docker" # allow access to docker daemon
        ];
        shell = pkgs.zsh;
        home = "/home/pascal";
      };

      programs.zsh.enable = true;

      programs.firefox.enable = true;

      programs.steam = {
        enable = true;
        package = pkgs.steam;
        gamescopeSession = {
          enable = false;
          env = {
            PROTON_USE_NTSYNC = "1";
          };
        };
        extraCompatPackages = with pkgs; [
          # Proton GE for improved game support
          proton-ge-bin
        ];
        localNetworkGameTransfers.openFirewall = true;
        remotePlay.openFirewall = true;
      };

      programs.gamescope = {
        enable = true;
        package = pkgs.gamescope;
        capSysNice = false;
        args = [
          "--rt"
          "--mangoapp"
          "--expose-wayland"
          "--force-grab-cursor"
          "--output-width 3840"
          "--nested-width 3840"
          "--output-height 1600"
          "--nested-height 1600"
          "-r 75"
          "--fullscreen"
        ];
      };

      # https://github.com/NixOS/nixpkgs/issues/351516#issuecomment-2607156591
      services.ananicy = {
        enable = true;
        package = pkgs.ananicy-cpp;
        rulesProvider = pkgs.ananicy-cpp;
        extraRules = [
          {
            "name" = "gamescope";
            "nice" = -20;
          }
        ];
      };

      # nixos-26.05 ships netbird 0.71.4, but we need a more recent version for the kubernetes integration
      services.netbird.package = pkgsUnstable.netbird;
      services.netbird.clients.personal = {
        port = 51821;
        ui.enable = false;
        openFirewall = true;
        openInternalFirewall = true;
        hardened = true;
        autoStart = true;
      };
 
      programs.gamemode.enable = true;

      programs._1password = {
        enable = true;
        package = pkgs._1password-cli;
      };

      programs._1password-gui = {
        enable = true;
        package = pkgs._1password-gui;
        # Certain features, including CLI integration and system authentication support,
        # require enabling PolKit integration on some desktop environment
        polkitPolicyOwners = [ "pascal" ];
      };

      # Allow unfree packages
      nixpkgs.config.allowUnfreePredicate =
        pkg:
        builtins.elem (pkgs.lib.getName pkg) [
          "1password"
          "1password-cli"
          "nvidia-kernel-modules"
          "nvidia-settings"
          "nvidia-x11"
          "onepassword-password-manager" # firefox extension
          "steam"
          "steam-unwrapped"
          "tableplus"
          "uhk-agent"
          "uhk-udev-rules"
        ];

      nixpkgs.config.permittedInsecurePackages = [
        "qtwebengine-5.15.19" # used by TeamSpeak 3 client
      ];

      # List packages installed in system profile. To search, run:
      # $ nix search wget
      environment.systemPackages = with pkgs; [
        ddcutil
        ddcui
        inputs.self.packages.${pkgs.stdenv.system}.docker-sbx
        mangohud
        pciutils
        pulseaudio # Steam requires pactl
        tableplus
        uhk-agent
        vulkan-tools
        inputs.sidra.packages.${pkgs.stdenv.system}.sidra
      ];

      environment.sessionVariables = {
        SSH_AUTH_SOCK = "$HOME/.1password/t/agent.sock";
        # Required for XBOX Wireless Controller support in Steam
        # https://github.com/atar-axis/xpadneo/issues/580
        SDL_JOYSTICK_HIDAPI = "0";
      };

      services.sunshine = {
        enable = true;
        package = pkgs.sunshine;
        openFirewall = true;
        autoStart = true;
        capSysAdmin = true;
        applications = {
          apps = [
            {
              name = "Steam";
              prep-cmd = [
                {
                  do = "sudo -u pascal steam -pipewire-dmabuf steam://open/bigpicture";
                  undo = "sudo -u pascal steam steam://close/bigpicture";
                }
              ];
              exclude-global-prep-cmd = "false";
              auto-detach = "true";
              image-path = "steam.png";
            }
          ];
        };
        settings = {
          global_prep_cmd = builtins.toJSON [
            {
              do = "kscreen-doctor output.DP-1.mode.1920x1080@60";
              undo = "kscreen-doctjor output.DP-1.mode.3840x1600@75";
            }
          ];
        };
      };

      # Enable flatpack for packages that are not available via nix (e.g. teamspeak3)
      services.flatpak = {
        enable = true;
        package = pkgs.flatpak;
        packages = [
          "com.teamspeak.TeamSpeak3"
        ];
      };

      # Open ports in the firewall.
      networking.firewall.enable = true;

      virtualisation.podman.enable = true;

      # This value determines the NixOS release from which the default
      # settings for stateful data, like file locations and database versions
      # on your system were taken. It‘s perfectly fine and recommended to leave
      # this value at the release version of the first install of this system.
      # Before changing this value read the documentation for this option
      # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
      system.stateVersion = "25.11"; # Did you read the comment?
    };
}
