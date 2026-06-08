{ self, inputs, ... }:
{
  flake.darwinConfigurations.pascal-mbp-procyde = inputs.nix-darwin.lib.darwinSystem {
    inherit inputs;
    system = "aarch64-darwin";
    modules = [
      (
        {
          pkgs,
          ...
        }:
        let
          hostPlatform = "aarch64-darwin";
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

          nix.settings = {
            # Necessary for using flakes on this system.
            experimental-features = "nix-command flakes";
            trusted-users = [ "pascal" ];
            substituters = [
              "https://cache.nixos.org/"
              "https://nix-community.cachix.org"
              "https://devenv.cachix.org"
            ];
            trusted-public-keys = [
              "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
              "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
              "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
            ];
          };

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
              "holmesgpt"
            ];
            casks = [
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
            # masApps = {
            #   "1Password for Safari" = 1569813296;
            #   "Yubico Authenticator" = 1497506650;
            #   "Magnet" = 441258766;
            # };
          };
        }
      )
      inputs.nix-homebrew.darwinModules.nix-homebrew
      {
        nix-homebrew = {
          # Install Homebrew under the default prefix
          enable = true;

          # Apple Silicon Only: Also install Homebrew under the default Intel prefix for Rosetta 2
          enableRosetta = true;

          # User owning the Homebrew prefix
          user = "pascal";

          # Declarative tap management
          taps = {
            "homebrew/homebrew-core" = inputs.homebrew-core;
            "homebrew/homebrew-cask" = inputs.homebrew-cask;
            "robusta-dev/homebrew-holmesgpt" = inputs.homebrew-holmesgpt;
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
      # An existing Linux builder is needed to initially bootstrap `nix-rosetta-builder`.
      # If one isn't already available: comment out the `nix-rosetta-builder` module below,
      # uncomment this `linux-builder` module, and run `darwin-rebuild switch`:
      # { nix.linux-builder.enable = true; }
      # Then: uncomment `nix-rosetta-builder`, remove `linux-builder`, and `darwin-rebuild switch`
      # a second time. Subsequently, `nix-rosetta-builder` can rebuild itself.
      inputs.nix-rosetta-builder.darwinModules.default
      {
        # see available options in module.nix's `options.nix-rosetta-builder`
        nix-rosetta-builder.onDemand = true;
      }
    ];
  };
}
