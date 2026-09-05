{
  description = "SOOP Chromium app with its Windows viewer grid agent";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        # The downloaded SOOP binaries are proprietary.
        config.allowUnfree = true;
      };
      mkApp = package: {
        type = "app";
        program = nixpkgs.lib.getExe package;
      };
      soopGrid = pkgs.callPackage ./package.nix { };
      soop = pkgs.callPackage ./webapp.nix { inherit soopGrid; };
    in
    {
      packages.${system} = {
        default = soop;
        inherit soop;
        soop-grid = soopGrid;
      };

      apps.${system} = {
        default = mkApp soop;
        soop = mkApp soop;
        soop-grid = mkApp soopGrid;
      };
    };
}
