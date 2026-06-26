{ ... }: {
  perSystem = { pkgs, ... }: {
    packages.docker-sbx = pkgs.callPackage ../pkgs/docker-sbx { };
  };
}
