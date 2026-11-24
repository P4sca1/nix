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
      self.nixosModules.waydroid
    ];
  };

  flake.nixosModules.pascal-pc =
    { pkgs, ... }:
    let
      # Shared unfree whitelist for the stable and unstable nixpkgs instances.
      allowUnfreePredicate =
        pkg:
        builtins.elem (pkgs.lib.getName pkg) [
          "1password"
          "1password-cli"
          "goland"
          "github-copilot-cli"
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

      pkgsUnstable = import inputs.nixpkgs-unstable {
        system = pkgs.stdenv.hostPlatform.system;
        config.allowUnfreePredicate = allowUnfreePredicate;
      };
    in
    {
      # Bootloader.
      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;
      # EFI shell in the boot menu, needed once to find the device handle of
      # the Windows ESP on the Samsung 870 QVO (`map -c`), see
      # boot.loader.systemd-boot.windows.
      boot.loader.systemd-boot.edk2-uefi-shell.enable = true;

      # Use latest kernel.
      boot.kernelPackages = pkgsUnstable.linuxPackages_latest;

      # Jonsbo riser cable: recurring Xid 79 ("GPU has fallen off the bus")
      # freezes on Linux, across a variety of nvidia driver/kernel combos,
      # while Windows on the same hardware was stable. The GPU link runs with
      # clock power management (CLKREQ#) enabled; bundled riser cables often
      # handle that badly. Disable PCIe ASPM entirely.
      boot.kernelParams = [
        "pcie_aspm=off"
        # Keep the TV (HDMI) disabled until something explicitly enables it,
        # so SDDM shows the login screen on the desktop monitor even though
        # the TV is connected (but in standby). This forces the connector to
        # report "disconnected", so niri alone can NOT enable it later:
        # `display-mode` first lifts the force by writing "detect" to
        # /sys/class/drm/card*-HDMI-A-1/status (see udev rule below).
        "video=HDMI-A-1:d"
      ];

      # Let the video group lift/restore the forced-off state of the TV
      # connector (used by `display-mode`).
      services.udev.extraRules = ''
        ACTION=="add|change", SUBSYSTEM=="drm", KERNEL=="card*-HDMI-A-1", RUN+="${pkgs.coreutils}/bin/chgrp video /sys%p/status", RUN+="${pkgs.coreutils}/bin/chmod g+w /sys%p/status"
      '';

      # pcie_aspm=off stops the kernel from managing ASPM but leaves the
      # BIOS-set ClockPM enable bit (Link Control, CLKREQ# clock gating) in
      # place - lspci showed "LnkCtl: ... ClockPM+" on this link. Clear it on
      # both endpoints of the GPU link through the riser; also re-applied
      # after suspend, since the platform may restore the bit.
      systemd.services.gpu-link-clockpm-off = {
        description = "Clear ClockPM (CLKREQ#) on the GPU riser link";
        wantedBy = [
          "multi-user.target"
          "suspend.target"
        ];
        after = [
          "multi-user.target"
          "suspend.target"
        ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = [
            "${pkgs.pciutils}/bin/setpci -s 0000:2b:00.0 CAP_EXP+0x10.w=0000:0100"
            "${pkgs.pciutils}/bin/setpci -s 0000:00:03.1 CAP_EXP+0x10.w=0000:0100"
          ];
        };
      };

      boot.kernelModules = [
        # ntsync is a kernel driver that mimics Windows synchronization mechanisms, significantly improving performance
        # for running Windows applications, especially games, through compatibility layers like Wine and Proton
        "ntsync"
      ];

      networking.hostName = "pascal-pc";
      networking.wireless.enable = true;
      networking.networkmanager.enable = true;
      # Wi-Fi power save causes 100-400ms latency spikes and packet loss on the
      # Intel AX200, on both 2.4 GHz and 5 GHz. Keep the radio always awake.
      networking.networkmanager.wifi.powersave = false;
      networking.nftables.enable = true;

      # Configure DNS
      networking.nameservers = [ "192.168.178.1" ]; # Fritz Box which routes to AdGuard Home
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
      nix.gc.options = "--delete-older-than 30d";

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
          "video" # write /sys/class/drm/*-HDMI-A-1/status (display-mode)
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

      # Secret Service provider. Claude Desktop (and other Electron apps) use
      # it to store login tokens, SSH passphrases and extension secrets.
      services.gnome.gnome-keyring.enable = true;
      # Unlock the keyring automatically with the login password.
      security.pam.services.sddm.enableGnomeKeyring = true;

      # Claude Desktop downloads dynamically linked binaries (e.g. the Claude
      # Code CLI) at runtime and execs them from ~/.config. nix-ld provides
      # the standard Linux loader + libraries so they can run on NixOS.
      programs.nix-ld = {
        enable = true;
        libraries = with pkgs; [
          stdenv.cc.cc
          glib
          nss
          nspr
          zlib
          openssl
          curl
          expat
          icu
          xz
          libxml2
          sqlite
          libgit2
        ];
      };

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
      nixpkgs.config.allowUnfreePredicate = allowUnfreePredicate;

      nixpkgs.config.permittedInsecurePackages = [
        "qtwebengine-5.15.19" # used by TeamSpeak 3 client
      ];

      # List packages installed in system profile. To search, run:
      # $ nix search wget
      environment.systemPackages = with pkgs; [
        ddcutil
        ddcui
        dig
        jetbrains.goland
        lutris
        mangohud
        pciutils
        pulseaudio # Steam requires pactl
        tableplus
        uhk-agent
        docker-compose # compose provider for podman (`podman compose`)
        vulkan-tools
        inputs.sidra.packages.${pkgs.stdenv.system}.sidra
        # Electron only picks the libsecret backend for desktops it knows
        # (GNOME, KDE, ...). Under niri it falls back to "basic_text", which
        # Claude treats as "safeStorage not available" and keeps the login
        # token in memory only -> re-login after every reboot. Force libsecret.
        (
          let
            claude = inputs.claude-desktop.packages.${pkgs.stdenv.system}.default;
          in
          pkgs.symlinkJoin {
            name = "claude-desktop-libsecret";
            paths = [ claude ];
            nativeBuildInputs = [ pkgs.makeWrapper ];
            postBuild = ''
              wrapProgram $out/bin/claude-desktop \
                --add-flags "--password-store=gnome-libsecret"
              # .desktop files reference the unwrapped binary by store path.
              for f in $out/share/applications/*.desktop; do
                target=$(readlink -f "$f")
                rm "$f"
                sed "s|${claude}/bin/claude-desktop|$out/bin/claude-desktop|g" "$target" > "$f"
              done
            '';
          }
        )
      ];

      environment.sessionVariables = {
        SSH_AUTH_SOCK = "$HOME/.1password/agent.sock";
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
        remotes = [
          # flathub must stay declared: nix-flatpak removes any remote not listed here
          {
            name = "flathub";
            location = "https://dl.flathub.org/repo/";
          }
          # official NVIDIA GeForce NOW repository (https://www.nvidia.com/en-us/geforce-now/download/)
          # point at the .flatpakrepo file so flatpak imports its GPG key (plain repo URL fails signature checks)
          {
            name = "GeForceNOW";
            location = "https://international.download.nvidia.com/GFNLinux/flatpak/geforcenow.flatpakrepo";
          }
        ];
        packages = [
          "com.teamspeak.TeamSpeak3"
          { appId = "com.nvidia.geforcenow"; origin = "GeForceNOW"; }
        ];
        # keep runtimes/GL extensions (incl. NVIDIA) in sync with the host driver on rebuild
        update.onActivation = true;
      };

      # Open ports in the firewall.
      networking.firewall.enable = true;

      virtualisation.podman = {
        enable = true;
        # Provide a `docker` command that translates to podman (rootless), so
        # `docker ps`, `docker build`, `docker compose` etc. work unchanged.
        dockerCompat = true;
      };

      # This value determines the NixOS release from which the default
      # settings for stateful data, like file locations and database versions
      # on your system were taken. It‘s perfectly fine and recommended to leave
      # this value at the release version of the first install of this system.
      # Before changing this value read the documentation for this option
      # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
      system.stateVersion = "25.11"; # Did you read the comment?
    };
}
