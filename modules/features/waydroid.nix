{
  flake.nixosModules.waydroid =
    { pkgs, ... }:
    let
      waydroidScript = pkgs.fetchFromGitHub {
        owner = "casualsnek";
        repo = "waydroid_script";
        rev = "48dbfaf34a6ddbe78688c530f9ba1c26522aafb2";
        hash = "sha256-UBbnYhiRCf4sMwpEDMlpJuTEsN66B2hZ8BPz6cCGXAc=";
      };
      pythonEnv = pkgs.python3.withPackages (ps: [
        ps.requests
        ps.tqdm
        ps.inquirerpy
      ]);
    in
    {
      virtualisation.waydroid.enable = true;

      # ARM translation (libndk — best on AMD CPUs) so ARM-only apps like
      # TFT Mobile run on the x86_64 image.
      # Idempotent oneshot: skipped once the stamp exists; re-applies after
      # a fresh 'waydroid init' wipes the stamp.
      systemd.services.waydroid-arm-translation = {
        description = "Install libndk ARM translation into the Waydroid image";
        wantedBy = [ "waydroid-container.service" ];
        before = [ "waydroid-container.service" ];
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        unitConfig.ConditionPathExists = [
          "/var/lib/waydroid/images"
          "!/var/lib/waydroid/.libndk-installed"
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          # waydroid binary needed for the script's final 'waydroid upgrade -o' call
          path = [ pkgs.waydroid ];
          ExecStart = pkgs.writeShellScript "waydroid-install-libndk" ''
            set -euo pipefail
            ${pythonEnv}/bin/python ${waydroidScript}/main.py install libndk
            touch /var/lib/waydroid/.libndk-installed
          '';
        };
      };
    };
}
