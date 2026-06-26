{ lib, stdenv, fetchurl, autoPatchelfHook
, lz4, libgcc, xxhash, zlib, zstd
}:

let
  version = "0.33.0";
in
stdenv.mkDerivation {
  pname = "docker-sbx";
  inherit version;

  src = fetchurl {
    url = "https://github.com/docker/sbx-releases/releases/download/v${version}/DockerSandboxes-linux-amd64.tar.gz";
    hash = "sha256-3swPaWA+bEvdZOOeKpRja+sQrv813T1E4HQ17m3b8p0=";
  };

  sourceRoot = "docker-sbx";

  nativeBuildInputs = [ autoPatchelfHook ];

  buildInputs = [ lz4 libgcc xxhash zlib zstd ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/lib $out/share/docker-sbx $out/share/doc/docker-sbx

    cp sbx $out/bin/
    cp containerd-shim-nerdbox-v1 $out/bin/
    cp mkfs.erofs $out/bin/
    cp libsailor.so $out/lib/
    cp nerdbox-initrd-x86_64 nerdbox-kernel-x86_64 $out/share/docker-sbx/
    cp apparmor-profile $out/share/docker-sbx/
    cp LICENSE THIRD-PARTY-NOTICES $out/share/doc/docker-sbx/

    runHook postInstall
  '';

  meta = {
    description = "Docker Sandboxes: safe environments for agents";
    longDescription = ''
      Docker Sandboxes provides sandboxes with controlled access to your
      filesystem, network, and tools. This means your agents can work
      autonomously without putting your machine or data at risk.
    '';
    homepage = "https://github.com/docker/sbx-releases";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    mainProgram = "sbx";
  };
}
