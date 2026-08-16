{
  lib,
  stdenvNoCC,
  fetchurl,
  writeText,
  gzip,
  icoutils,
  bashNonInteractive,
  coreutils,
  util-linux,
  iproute2,
  wineWow64Packages,
}:

let
  wine = wineWow64Packages.stable;

  upstream = {
    packageVersion = "1.0.0.1";
    streamerVersion = "26.7.14.1201";
    baseUrl = "https://creatorup.sooplive.com/SOOP";
    installerUrl = "https://creatorup.sooplive.com/SOOPStreamer_installer.exe";
    installerHash = "sha256-olSn2T+CcdWvW8LPMDeLy6BA/95pzzsrtXVKOwxUQgg=";
  };

  # Update from SOOPFileList.xml at upstream.baseUrl. Its H fields hash the
  # decompressed files; fetchurl needs the archive hash printed by:
  # nix store prefetch-file --json "$baseUrl/<name>.gz"
  appFiles = [
    {
      name = "Uninstall.exe.gz";
      hash = "sha256-yFUkZstEtVfxXTlZnsjnJO4ZamSLmp6j7vw4KmK90Ds=";
    }
    {
      name = "NetControl.dll.gz";
      hash = "sha256-8+iTCJu7FZXQJnuWExov58dOq2QmRKNwnQttnVsGrAQ=";
    }
    {
      name = "upnputil.dll.gz";
      hash = "sha256-jeG8aks1E+1ho2R+SMeyliDvYQp6zMqNcq0GbckKF1Y=";
    }
    {
      name = "SOOPPackage.exe.gz";
      hash = "sha256-Jro2GVQwqJzjXTV9qiJdUGrzsx45W2bPmqkwUh/GhB0=";
    }
    {
      name = "SOOPLogUtil.dll.gz";
      hash = "sha256-3Ap2S7f2g6d3YqLmjbJ8o0kVuxARrp4q6Dju5kEkxlQ=";
    }
    {
      name = "license.txt.gz";
      hash = "sha256-R408jxMIRw21krQmly3nTDun6FNfPIU1JQSL1WGfoYc=";
    }
    {
      name = "SOOPStreamer.exe.gz";
      hash = "sha256-gPPCshwDjEJ5MCDMXcK/t4fKT/ehlEOzuVQ5P8Kmdeo=";
    }
  ];

  runtimeFiles = [
    {
      name = "mfc71.dll.gz";
      hash = "sha256-eitkJL8irvfLHXXhUnmhu1mAlefldXp982jPT7cyqNg=";
    }
    {
      name = "mfc71u.dll.gz";
      hash = "sha256-7XtDvpYe36zDMw7VhoKJrz6zIuCz9VuKgwcvLTp4dH0=";
    }
    {
      name = "msvcp71.dll.gz";
      hash = "sha256-IjP8mqx4zbT3hwlI1WwT0YQQPcEd+Tba69DS4tLTSjw=";
    }
    {
      name = "msvcr71.dll.gz";
      hash = "sha256-BxhoN04ZIxPRUxwYCMt/ph5G9Hzbs/tFpYJJzJmN1Cg=";
    }
  ];

  fetchFile =
    file:
    file
    // {
      source = fetchurl {
        url = "${upstream.baseUrl}/${file.name}";
        inherit (file) hash;
      };
      outputName = lib.removeSuffix ".gz" file.name;
    };

  unpackFiles =
    destination: files:
    lib.concatMapStringsSep "\n" (file: ''
      gzip -dc ${file.source} > "$out/share/soop-grid/${destination}/${file.outputName}"
    '') (map fetchFile files);

  iconSizes = [
    {
      index = 1;
      size = 256;
    }
    {
      index = 2;
      size = 128;
    }
    {
      index = 3;
      size = 64;
    }
    {
      index = 4;
      size = 48;
    }
    {
      index = 5;
      size = 32;
    }
    {
      index = 6;
      size = 24;
    }
    {
      index = 7;
      size = 16;
    }
  ];

  installIcons = lib.concatMapStringsSep "\n" ({ index, size }: ''
    install -d "$out/share/icons/hicolor/${toString size}x${toString size}/apps"
    icotool -x --index=${toString index} \
      --output="$out/share/icons/hicolor/${toString size}x${toString size}/apps/soop-grid.png" \
      "$TMPDIR/soop-grid.ico"
  '') iconSizes;

  desktopFile = writeText "soop-grid.desktop" ''
    [Desktop Entry]
    Type=Application
    Version=1.0
    Name=SOOP Grid
    Comment=Start the SOOP viewer grid agent
    Exec=soop-grid
    TryExec=soop-grid
    Icon=soop-grid
    Terminal=false
    Categories=AudioVideo;
    Keywords=SOOP;live;streaming;P2P;
    StartupNotify=false
  '';

  runtimePath = lib.makeBinPath [
    coreutils
    util-linux
    iproute2
    wine
  ];
in
stdenvNoCC.mkDerivation {
  pname = "soop-grid";
  version = upstream.streamerVersion;

  dontUnpack = true;
  strictDeps = true;

  nativeBuildInputs = [
    gzip
    icoutils
  ];

  installPhase = ''
    runHook preInstall

    install -d \
      "$out/bin" \
      "$out/share/applications" \
      "$out/share/licenses/soop-grid" \
      "$out/share/soop-grid/payload" \
      "$out/share/soop-grid/runtime"

    ${unpackFiles "payload" appFiles}
    ${unpackFiles "runtime" runtimeFiles}

    chmod 0444 "$out/share/soop-grid/payload/"* "$out/share/soop-grid/runtime/"*
    install -m 0444 "$out/share/soop-grid/payload/license.txt" \
      "$out/share/licenses/soop-grid/license.txt"

    wrestool -x --type=14 --name=128 \
      "$out/share/soop-grid/payload/SOOPPackage.exe" > "$TMPDIR/soop-grid.ico"
    ${installIcons}

    install -m 0444 ${desktopFile} "$out/share/applications/soop-grid.desktop"
    substitute ${./soop-grid.sh} "$out/bin/soop-grid" \
      --subst-var-by bash ${lib.getExe bashNonInteractive} \
      --subst-var-by runtimePath ${runtimePath} \
      --subst-var-by payloadDir "$out/share/soop-grid/payload" \
      --subst-var-by runtimeDir "$out/share/soop-grid/runtime" \
      --subst-var-by seedVersion "${upstream.packageVersion}-${upstream.streamerVersion}"
    chmod 0555 "$out/bin/soop-grid"

    runHook postInstall
  '';

  passthru = {
    inherit upstream;
    updateManifest = "${upstream.baseUrl}/SOOPFileList.xml";
  };

  meta = {
    description = "SOOP viewer grid agent wrapped with Wine";
    homepage = "https://www.sooplive.com/";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "soop-grid";
  };
}
