{ self, inputs, ... }:
{
  flake.darwinConfigurations.pascal-mbp = inputs.nix-darwin.lib.darwinSystem {
    inherit inputs;
    system = "x86_64-darwin";
    modules = [
      (
        {
          pkgs,
          ...
        }:
        let
          hostPlatform = "x86_64-darwin";
          allowUnfreePredicate =
            pkg:
            builtins.elem (pkgs.lib.getName pkg) [
              "slack"
              "orbstack"
              "onepassword-password-manager" # firefox extension
            ];
        in
        {
          # List packages installed in system profile. To search by name, run:
          # $ nix-env -qaP | grep wget
          environment.systemPackages = [
            pkgs.wireshark
            pkgs.orbstack
          ];

          environment.variables = {
            SSH_AUTH_SOCK = "$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock";
          };

          fonts.packages = [
            pkgs.nerd-fonts.jetbrains-mono
          ];

          # Necessary for using flakes on this system.
          nix.settings.experimental-features = "nix-command flakes";
          nix.settings.trusted-users = [ "pascal" ];
          nix.linux-builder.enable = true;
          nix.gc.automatic = true;

          # Used for backwards compatibility, please read the changelog before changing.
          # $ darwin-rebuild changelog
          system.stateVersion = 6;

          # required to use homebrew.enable = true.
          system.primaryUser = "pascal";

          system.defaults = {
            dock.autohide = true;
            finder.FXPreferredViewStyle = "clmw";
            loginwindow.GuestEnabled = false;
            NSGlobalDomain = {
              AppleICUForce24HourTime = true;
              ApplePressAndHoldEnabled = false;
              InitialKeyRepeat = 15;
              KeyRepeat = 2;
            };
          };

          users.users.pascal = {
            description = "Pascal Sthamer";
            shell = pkgs.zsh;
            home = "/Users/pascal";
          };

          home-manager.users.pascal = self.homeModules.pascal;

          # The platform the configuration will be used on.
          nixpkgs.hostPlatform = hostPlatform;
          nixpkgs.config.allowUnfreePredicate = allowUnfreePredicate;

          # Homebrew for packages that are not available via nix
          homebrew = {
            enable = true;
            onActivation.cleanup = "zap";
            brews = [
            ];
            casks = [
              "1password-cli"
              "deskpad"
              "httpie-desktop"
              "obsidian"
              "setapp"
              "balenaetcher"
              "bambu-studio"
              "tower"
              "monitorcontrol"
              "element"
            ];
            masApps = {
              "1Password for Safari" = 1569813296;
              "Yubico Authenticator" = 1497506650;
              "Magnet" = 441258766;
            };
          };
        }
      )
      inputs.nix-homebrew.darwinModules.nix-homebrew
      {
        nix-homebrew = {
          # Install Homebrew under the default prefix
          enable = true;

          # Apple Silicon Only: Also install Homebrew under the default Intel prefix for Rosetta 2
          enableRosetta = false;

          # User owning the Homebrew prefix
          user = "pascal";

          # Declarative tap management
          taps = {
            "homebrew/homebrew-core" = inputs.homebrew-core;
            "homebrew/homebrew-cask" = inputs.homebrew-cask;
          };

          # Enable fully-declarative tap management
          #
          # With mutableTaps disabled, taps can no longer be added imperatively with `brew tap`.
          mutableTaps = false;
        };
      }
      # Align homebrew taps config with nix-homebrew
      (
        { config, ... }:
        {
          homebrew.taps = builtins.attrNames config.nix-homebrew.taps;
        }
      )
      inputs.home-manager.darwinModules.home-manager
      {
        home-manager = {
          useGlobalPkgs = true;
          useUserPackages = true;
        };
      }
      inputs.nur.modules.darwin.default
    ];
  };
}
