{ ... }:
{
  flake.nixosModules.pascal-pc-hardware =
    {
      config,
      lib,
      ...
    }:

    {
      boot.initrd.availableKernelModules = [
        "nvme"
        "xhci_pci"
        "ahci"
        "usb_storage"
        "usbhid"
        "sd_mod"
      ];
      boot.initrd.kernelModules = [ ];
      boot.kernelModules = [ "kvm-amd" ];
      boot.extraModulePackages = [ ];

      fileSystems."/" = {
        device = "/dev/disk/by-uuid/3b9b849d-3471-4497-84ee-01d20a242988";
        fsType = "ext4";
      };

      fileSystems."/boot" = {
        device = "/dev/disk/by-uuid/AD7B-0DD5";
        fsType = "vfat";
        options = [
          "fmask=0077"
          "dmask=0077"
        ];
      };

      fileSystems."/games" = {
        device = "/dev/disk/by-uuid/509e98f7-0bed-462c-80fd-b7445f7a5386";
        fsType = "ext4";
      };

      fileSystems."/data" = {
        device = "/dev/disk/by-uuid/ad9fbb99-41e9-4bfd-b6d0-85e1127e8151";
        fsType = "ext4";
      };

      swapDevices = [
        { device = "/dev/disk/by-uuid/6ee56abd-707f-45d0-9b85-c28d7603c023"; }
      ];

      nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
      hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

      hardware.graphics = {
        enable = true;
        enable32Bit = true;
      };

      hardware.nvidia = {
        modesetting.enable = true;
        powerManagement.enable = true;
        open = false; # Use unfree kernel driver for improved game support;
        # 610.57.04 fixes the strncpy removal in kernel 7.2 that breaks 595.x.
        # See https://github.com/NixOS/nixpkgs/issues/554125 — remove once
        # nixpkgs updates the stable driver to >= 610.57.04.
        package = config.boot.kernelPackages.nvidiaPackages.mkDriver {
          version = "610.57.04";
          sha256_64bit = "sha256-suk1xmuDuwDAyFe8jg7g/VLekoa0DJzB7sKafOfrEW0=";
          sha256_aarch64 = "sha256-QCefrMBCmpOwuOyXv1k5Gj0iB2CYlPgnG3JToUw/j54=";
          openSha256 = "sha256-rQHOOOY4KL92Ww3KDwh+j4eGU7oNAH8LutZC5wmFnPo=";
          settingsSha256 = "sha256-ZEMo8I8Zc2Tq6RVDNYpAH+f094dUaZiBqO+5f6lIjRI=";
          persistencedSha256 = "sha256-aXmD2VY1RLlgAnlHhOUMWzvMyhI6JTClcFLm4imF/mA=";
        };
      };
      services.xserver.videoDrivers = [ "nvidia" ];

      hardware.enableRedistributableFirmware = true; # required for Intel Wifi drivers
      hardware.uinput.enable = true;
      hardware.bluetooth.enable = true;
      hardware.xpadneo.enable = true;
      hardware.steam-hardware.enable = true;
      hardware.keyboard.uhk.enable = true;
      hardware.logitech.wireless.enable = true;
      hardware.logitech.wireless.enableGraphical = true;
      hardware.i2c.enable = true;
    };
}
