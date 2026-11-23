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

      # Windows (Samsung 870 QVO). ntfs-3g instead of the in-kernel ntfs3,
      # which refuses this volume ("Can't open blockdev"). If Windows was
      # hibernated / fast-started, ntfs-3g falls back to read-only.
      # nofail: never block NixOS boot on this disk.
      fileSystems."/windows" = {
        device = "/dev/disk/by-uuid/F22A5B9F2A5B5FA1";
        fsType = "ntfs-3g";
        noCheck = true; # there is no fsck for NTFS on Linux
        options = [
          "uid=1000"
          "gid=100"
          "windows_names"
          "nofail"
          "x-systemd.device-timeout=10s"
        ];
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
        package = config.boot.kernelPackages.nvidiaPackages.production;
      };
      services.xserver.videoDrivers = [ "nvidia" ];

      hardware.enableRedistributableFirmware = true; # required for Intel Wifi drivers
      hardware.uinput.enable = true;
      hardware.bluetooth.enable = true;
      # Workaround for the DualShock 4 / classic-HID bonding bug (see
      # docs/bluetooth-gamepad-pairing.md and bluez issue #642): BlueZ
      # otherwise rejects HID connections from not-yet-bonded devices
      # ("Rejected connection from !bonded device"), which makes DS4
      # pairing/connecting loop forever.
      hardware.bluetooth.input.General.ClassicBondedOnly = false;
      hardware.xpadneo.enable = true;
      hardware.steam-hardware.enable = true;
      hardware.keyboard.uhk.enable = true;
      hardware.logitech.wireless.enable = true;
      hardware.logitech.wireless.enableGraphical = true;
      hardware.i2c.enable = true;
    };
}
