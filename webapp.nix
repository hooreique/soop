{
  lib,
  stdenvNoCC,
  writeText,
  bashNonInteractive,
  coreutils,
  util-linux,
  chromium,
  soopGrid,
}:

let
  iconSizes = [
    "256x256"
    "128x128"
    "64x64"
    "48x48"
    "32x32"
    "24x24"
    "16x16"
  ];

  installIcons = lib.concatMapStringsSep "\n" (size: ''
    install -d "$out/share/icons/hicolor/${size}/apps"
    ln -s ${soopGrid}/share/icons/hicolor/${size}/apps/soop-grid.png \
      "$out/share/icons/hicolor/${size}/apps/soop.png"
  '') iconSizes;

  desktopFile = writeText "soop.desktop" ''
    [Desktop Entry]
    Type=Application
    Version=1.0
    Name=SOOP
    Comment=Watch SOOP with the viewer grid agent
    Exec=soop
    TryExec=soop
    Icon=soop
    Terminal=false
    Categories=AudioVideo;Player;
    Keywords=SOOP;live;streaming;P2P;
    StartupNotify=true
    StartupWMClass=SOOP
  '';

  runtimePath = lib.makeBinPath [
    coreutils
    util-linux
  ];
in
stdenvNoCC.mkDerivation {
  pname = "soop";
  inherit (soopGrid) version;

  dontUnpack = true;
  strictDeps = true;

  installPhase = ''
    runHook preInstall

    install -d \
      "$out/bin" \
      "$out/share/applications" \
      "$out/share/licenses/soop" \
      "$out/share/soop/same-window-extension"

    ${installIcons}
    ln -s ${soopGrid}/share/licenses/soop-grid/license.txt \
      "$out/share/licenses/soop/license.txt"
    install -m 0444 ${desktopFile} "$out/share/applications/soop.desktop"
    install -m 0444 ${./extension/manifest.json} \
      "$out/share/soop/same-window-extension/manifest.json"
    install -m 0444 ${./extension/same-window.js} \
      "$out/share/soop/same-window-extension/same-window.js"
    substitute ${./soop.sh} "$out/bin/soop" \
      --subst-var-by bash ${lib.getExe bashNonInteractive} \
      --subst-var-by runtimePath ${runtimePath} \
      --subst-var-by gridBin ${lib.getExe soopGrid} \
      --subst-var-by chromiumBin ${lib.getExe chromium} \
      --subst-var-by extensionDir "$out/share/soop/same-window-extension"
    chmod 0555 "$out/bin/soop"

    runHook postInstall
  '';

  passthru.grid = soopGrid;

  meta = {
    description = "SOOP Chromium app with the Windows viewer grid agent";
    homepage = "https://www.sooplive.com/";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "soop";
  };
}
