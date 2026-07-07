{
  inputs,
  ...
}:
{
  flake.nixosModules.herdr =
    { pkgs, ... }:
    {
      environment.systemPackages = [
        inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.herdr
      ];
    };
}
