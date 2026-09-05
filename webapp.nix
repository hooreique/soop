{
  lib,
  stdenvNoCC,
  makeDesktopItem,
  copyDesktopItems,
  makeShellWrapper,
  shellcheck,
  bashNonInteractive,
  coreutils,
  util-linux,
  jq,
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

  desktopItem = makeDesktopItem {
    name = "soop";
    desktopName = "SOOP";
    comment = "Watch SOOP with the viewer grid agent";
    exec = "soop";
    tryExec = "soop";
    icon = "soop";
    terminal = false;
    categories = [
      "AudioVideo"
      "Player"
    ];
    keywords = [
      "SOOP"
      "live"
      "streaming"
      "P2P"
    ];
    startupNotify = true;
    startupWMClass = "SOOP";
  };

  runtimePath = lib.makeBinPath [
    coreutils
    util-linux
    jq
  ];
in
stdenvNoCC.mkDerivation {
  pname = "soop";
  inherit (soopGrid) version;

  dontUnpack = true;
  strictDeps = true;

  nativeBuildInputs = [
    copyDesktopItems
    makeShellWrapper
  ];

  buildInputs = [ bashNonInteractive ];
  nativeCheckInputs = [
    bashNonInteractive
    shellcheck
  ];
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    bash -n ${./soop.sh}
    shellcheck ${./soop.sh}
    runHook postCheck
  '';

  desktopItems = [ desktopItem ];

  installPhase = ''
    runHook preInstall

    install -d \
      "$out/bin" \
      "$out/share/licenses/soop" \
      "$out/share/soop/same-window-extension"

    ${installIcons}
    ln -s ${soopGrid}/share/licenses/soop-grid/license.txt \
      "$out/share/licenses/soop/license.txt"
    install -m 0444 ${./extension/manifest.json} \
      "$out/share/soop/same-window-extension/manifest.json"
    install -m 0444 ${./extension/restore-close-shortcut.js} \
      "$out/share/soop/same-window-extension/restore-close-shortcut.js"
    install -m 0444 ${./extension/same-window-links.js} \
      "$out/share/soop/same-window-extension/same-window-links.js"
    install -m 0444 ${./extension/same-window-open.js} \
      "$out/share/soop/same-window-extension/same-window-open.js"
    install -m 0555 ${./soop.sh} "$out/bin/soop"

    runHook postInstall
  '';

  # Wrap after the normal fixup has patched the executable script's shebang.
  postFixup = ''
    wrapProgram "$out/bin/soop" \
      --prefix PATH : "${runtimePath}" \
      --set SOOP_GRID_BIN "${lib.getExe soopGrid}" \
      --set SOOP_CHROMIUM_BIN "${lib.getExe chromium}" \
      --set SOOP_EXTENSION_DIR "$out/share/soop/same-window-extension"
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
