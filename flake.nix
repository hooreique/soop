{
  description = "SOOP viewer grid agent wrapped for NixOS with Wine";

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
      soop-grid = pkgs.callPackage ./package.nix { };
    in
    {
      packages.${system} = {
        default = soop-grid;
        inherit soop-grid;
      };

      apps.${system} = {
        default = {
          type = "app";
          program = "${soop-grid}/bin/soop-grid";
        };
        soop-grid = {
          type = "app";
          program = "${soop-grid}/bin/soop-grid";
        };
      };
    };
}
