{
  inputs,
  ...
}:
{
  flake.nixosModules.sops =
    { pkgs, config, ... }:
    {
      imports = [ inputs.sops-nix.nixosModules.sops ];

      environment.systemPackages = [
        pkgs.sops
      ];

      sops.defaultSopsFile = ../../secrets/secrets.yaml;
      sops.defaultSopsFormat = "yaml";
      sops.age.keyFile = "${config.users.users.pascal.home}/.config/sops/age/keys.txt";
    };
}
