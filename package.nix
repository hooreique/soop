{
  lib,
  stdenvNoCC,
  fetchurl,
  makeDesktopItem,
  copyDesktopItems,
  makeShellWrapper,
  shellcheck,
  python3,
  gzip,
  icoutils,
  bashNonInteractive,
  coreutils,
  util-linux,
  iproute2,
  xorg-server,
  wineWow64Packages,
}:

let
  wine = wineWow64Packages.stable;

  upstream = {
    launcherVersion = "1.0.0.0";
    streamerVersion = "2.3.32.0";
    baseUrl = "https://creatorup.sooplive.com/SOOP";
    installerUrl = "https://creatorup.sooplive.com/SOOPStreamer_installer.exe";
    installerHash = "sha256-KA/yXxdcZitMVA7PQKDM8/nLsazBqWguQiPvqsTkp/0=";
  };

  # Update from SOOPFileList.xml at upstream.baseUrl. Its H fields hash the
  # decompressed files; fetchurl needs the archive hash printed by:
  # nix store prefetch-file --json "$baseUrl/<name>.gz"
  appFiles = [
    {
      name = "Uninstall.exe.gz";
      hash = "sha256-YpeW2iwzUAbxAEuA/rB5XUhA/JDqFU+XMziiOzYI07Q=";
    }
    {
      name = "SOOPLiveLauncher.exe.gz";
      hash = "sha256-KeoItPEyXpcFzcGfZzgELAxzEGK3abKc9Xc6a7M/5G8=";
    }
    {
      name = "license.txt.gz";
      hash = "sha256-R408jxMIRw21krQmly3nTDun6FNfPIU1JQSL1WGfoYc=";
    }
    {
      name = "SOOPStreamer.exe.gz";
      hash = "sha256-n7yP9tvfAUwfNEk5eutfhsb/NkoR1FY5Dzz/pSYKehg=";
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

  installIcons = lib.concatMapStringsSep "\n" (
    { index, size }:
    ''
      install -d "$out/share/icons/hicolor/${toString size}x${toString size}/apps"
      icotool -x --index=${toString index} \
        --output="$out/share/icons/hicolor/${toString size}x${toString size}/apps/soop-grid.png" \
        "$TMPDIR/soop-grid.ico"
    ''
  ) iconSizes;

  desktopItem = makeDesktopItem {
    name = "soop-grid";
    desktopName = "SOOP Grid";
    comment = "Start the SOOP viewer grid agent";
    exec = "soop-grid";
    tryExec = "soop-grid";
    icon = "soop-grid";
    terminal = false;
    categories = [ "AudioVideo" ];
    keywords = [
      "SOOP"
      "live"
      "streaming"
      "P2P"
    ];
    startupNotify = false;
  };

  runtimePath = lib.makeBinPath [
    coreutils
    util-linux
    iproute2
    xorg-server
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
    copyDesktopItems
    makeShellWrapper
  ];

  buildInputs = [ bashNonInteractive ];
  nativeCheckInputs = [
    bashNonInteractive
    shellcheck
    python3
    iproute2
  ];
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    bash -n ${./soop-grid.sh}
    shellcheck ${./soop-grid.sh}
    python3 ${./tests/socket-status.py} bash ${./soop-grid.sh}
    runHook postCheck
  '';

  desktopItems = [ desktopItem ];

  installPhase = ''
    runHook preInstall

    install -d \
      "$out/bin" \
      "$out/share/licenses/soop-grid" \
      "$out/share/soop-grid/payload"

    ${unpackFiles "payload" appFiles}

    chmod 0444 "$out/share/soop-grid/payload/"*
    install -m 0444 "$out/share/soop-grid/payload/license.txt" \
      "$out/share/licenses/soop-grid/license.txt"

    wrestool -x --type=14 --name=IDI_ICON1 \
      "$out/share/soop-grid/payload/SOOPLiveLauncher.exe" > "$TMPDIR/soop-grid.ico"
    ${installIcons}

    install -m 0555 ${./soop-grid.sh} "$out/bin/soop-grid"

    runHook postInstall
  '';

  # Wrap after the normal fixup has patched the executable script's shebang.
  postFixup = ''
    wrapProgram "$out/bin/soop-grid" \
      --prefix PATH : "${runtimePath}" \
      --set SOOP_GRID_PAYLOAD_DIR "$out/share/soop-grid/payload" \
      --set SOOP_GRID_SEED_VERSION "${upstream.launcherVersion}-${upstream.streamerVersion}-${builtins.hashString "sha256" (builtins.toJSON appFiles)}"
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
