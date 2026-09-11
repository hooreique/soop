{
  description = "SOOP Chromium app with its Windows viewer grid agent";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      overlay = final: prev: {
        soop-grid = final.callPackage ./package.nix { };
        soop = final.callPackage ./webapp.nix { soopGrid = final.soop-grid; };
      };
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ overlay ];
        # The downloaded SOOP binaries are proprietary.
        config.allowUnfree = true;
      };
      mkApp = package: {
        type = "app";
        program = nixpkgs.lib.getExe package;
      };
      soopGrid = pkgs.soop-grid;
      soop = pkgs.soop;
    in
    {
      overlays.default = overlay;

      packages.${system} = {
        default = soop;
        soop = soop;
        soop-grid = soopGrid;
      };

      apps.${system} = {
        default = mkApp soop;
        soop = mkApp soop;
        soop-grid = mkApp soopGrid;
      };
    };
}
